import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../core/app_errors.dart';
import '../../../core/constants.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mr_icon_button.dart';
import '../../../shared/ai/domain/ai_service.dart';
import '../../../shared/ai/domain/classification.dart';
import '../../calendar/domain/event.dart';
import '../../calendar/domain/event_repo.dart';
import '../../ideas/domain/idea_repo.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_category.dart';
import '../../notes/domain/note_repo.dart';
import '../../recap/domain/recap.dart';
import '../../recap/domain/recap_repo.dart';
import '../../todo/domain/todo.dart';
import '../../todo/domain/todo_category.dart';
import '../../todo/domain/todo_repo.dart';

class _CatMeta {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _CatMeta(this.key, this.label, this.icon, this.color);
}

const _kBaseCats = <_CatMeta>[
  _CatMeta('calendar', '行事曆', LucideIcons.calendar, AppColors.sage),
  _CatMeta('todo', '待辦', LucideIcons.check, AppColors.blue),
  _CatMeta('idea', '靈感', LucideIcons.lightbulb, AppColors.amber),
  _CatMeta('note', '札記', LucideIcons.fileText, AppColors.rose),
];
const _kRecapCat =
    _CatMeta('recap', '回顧', LucideIcons.bookOpen, AppColors.muted);

/// Smart Add overlay — collects free text + attachments, auto-detects category
/// via AI (step 1), lets the user confirm / adjust category buttons (step 2),
/// then writes to the matching repo (step 3).
class AddOverlay extends StatefulWidget {
  const AddOverlay({super.key});

  @override
  State<AddOverlay> createState() => _AddOverlayState();
}

class _AddOverlayState extends State<AddOverlay> {
  final _textCtrl = TextEditingController();
  final List<PendingAttachment> _attachments = [];
  final _recorder = AudioRecorder();
  String? _recordingPath;
  bool _recording = false;
  bool _processing = false;
  bool _detecting = false;
  String _status = '';
  Timer? _debounceTimer;
  int _detectGen = 0; // incremented on each trigger; stale results are discarded

  // Detection results & user overrides
  List<ClassificationItem>? _detectedItems;
  final Set<String> _selectedMainCats = {};
  String _todoCatId = kUndefinedCategoryId;
  String _noteCatId = kUndefinedCategoryId;

  // Category lists (loaded once on open)
  List<TodoCategory> _todoCats = [];
  List<NoteCategory> _noteCats = [];
  bool _catsLoaded = false;

  bool get _attachmentsEnabled => !kIsWeb;
  bool get _busy => _detecting || _processing;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_catsLoaded) {
      _catsLoaded = true;
      _loadCategories();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Clear stale detection whenever text changes.
    if (_detectedItems != null) {
      setState(() {
        _detectedItems = null;
        _selectedMainCats.clear();
      });
    }
    // Invalidate any in-flight detection by bumping the generation counter.
    _detectGen++;
    _debounceTimer?.cancel();
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      if (_detecting) setState(() => _detecting = false);
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_processing) _detect();
    });
  }

  Future<void> _loadCategories() async {
    final todoRepo = context.read<TodoRepo>();
    final noteRepo = context.read<NoteRepo>();
    final todoCats = await todoRepo.watchTodoCategories().first;
    final noteCats = await noteRepo.watchNoteCategories().first;
    if (!mounted) return;
    setState(() {
      _todoCats = todoCats;
      _noteCats = noteCats;
    });
  }

  // ── Attachment picking / recording ─────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg', 'jpeg', 'png', 'gif', 'webp',
        'mp3', 'm4a', 'wav', 'ogg',
        'txt', 'md', 'pdf',
      ],
    );
    if (result == null || result.files.isEmpty) return;

    final additions = <PendingAttachment>[];
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      if (bytes.length > kMaxAttachmentBytes) {
        _toast('「${f.name}」超過 10MB，無法加入');
        continue;
      }
      final ext = (f.extension ?? '').toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        additions.add(PendingAttachment(
            type: 'image', filename: f.name, bytes: bytes, ext: ext));
      } else if (['mp3', 'm4a', 'wav', 'ogg'].contains(ext)) {
        additions.add(PendingAttachment(
            type: 'audio', filename: f.name, bytes: bytes, ext: ext));
      } else if (['txt', 'md'].contains(ext)) {
        additions.add(PendingAttachment(
          type: 'file',
          filename: f.name,
          bytes: bytes,
          ext: ext,
          extractedText: utf8.decode(bytes, allowMalformed: true),
        ));
      } else if (ext == 'pdf') {
        additions.add(PendingAttachment(
          type: 'file',
          filename: f.name,
          bytes: bytes,
          ext: ext,
          extractedText: await _extractPdfText(bytes),
        ));
      }
    }
    if (additions.isNotEmpty && mounted) {
      setState(() => _attachments.addAll(additions));
    }
  }

  Future<String> _extractPdfText(Uint8List bytes) async {
    try {
      final doc = await PdfDocument.openData(bytes);
      final buf = StringBuffer();
      for (int i = 1; i <= doc.pages.length; i++) {
        final text = await doc.pages[i - 1].loadText();
        buf.write(text?.fullText);
        buf.write('\n');
      }
      return buf.toString().trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _recordingPath = path;
    await _recorder.start(const RecordConfig(), path: path);
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    if (!mounted) return;
    setState(() => _recording = false);
    final path = _recordingPath;
    _recordingPath = null;
    if (path == null) return;
    final f = File(path);
    if (!await f.exists()) return;
    final bytes = await f.readAsBytes();
    await f.delete();
    if (bytes.length > kMaxAttachmentBytes) {
      _toast('錄音超過 10MB，無法加入');
      return;
    }
    setState(() => _attachments.add(PendingAttachment(
          type: 'audio',
          filename: 'recording.m4a',
          bytes: bytes,
          ext: 'm4a',
        )));
  }

  // ── Step 1: AI category detection ─────────────────────────────────────────

  Future<void> _detect() async {
    final text = _textCtrl.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) || _processing) return;
    // Don't unfocus — the user may still be typing.

    final ai = context.read<AiService>();
    final gen = ++_detectGen; // snapshot generation before any await

    setState(() {
      _detecting = true;
      _detectedItems = null;
      _selectedMainCats.clear();
      _status = '偵測中…';
    });

    // Transcribe any un-transcribed audio first.
    for (int i = 0; i < _attachments.length; i++) {
      final a = _attachments[i];
      if (a.type == 'audio' &&
          (a.extractedText == null || a.extractedText!.isEmpty)) {
        if (mounted) setState(() => _status = '轉錄語音中…');
        final r = await ai.transcribe(audioBytes: a.bytes, filename: a.filename);
        if (r is Ok<String>) {
          _attachments[i] = PendingAttachment(
            type: a.type,
            filename: a.filename,
            bytes: a.bytes,
            ext: a.ext,
            extractedText: r.value,
          );
        }
      }
    }

    // Build classification payload.
    final images = <String>[];
    final fileTextParts = <String>[];
    final manifest = <AiAttachmentRef>[];
    for (int i = 0; i < _attachments.length; i++) {
      final a = _attachments[i];
      manifest.add(AiAttachmentRef(i: i, type: a.type, name: a.filename));
      if (a.type == 'image') {
        images.add(base64Encode(a.bytes));
      } else if (a.extractedText != null && a.extractedText!.isNotEmpty) {
        fileTextParts.add('【${a.filename}】\n${a.extractedText}');
      }
    }

    if (mounted) setState(() => _status = 'AI 分類中…');
    final result = await ai.classifyMultiInput(
      text: text,
      images: images,
      fileText: fileTextParts.join('\n\n'),
      attachments: manifest,
    );

    // Discard result if the user has already typed new text (gen mismatch).
    if (!mounted || gen != _detectGen) return;

    if (result is! Ok<List<ClassificationItem>>) {
      setState(() {
        _detecting = false;
        _status = '';
      });
      return;
    }

    final items = result.value;
    if (items.isEmpty) {
      setState(() {
        _detecting = false;
        _status = '';
      });
      _toast('AI 沒有辨識出可新增的項目');
      return;
    }

    // Extract detected categories and default sub-cat IDs.
    final detected = <String>{};
    String todoCatId = kUndefinedCategoryId;
    String noteCatId = kUndefinedCategoryId;
    for (final item in items) {
      switch (item) {
        case ClassifiedTodo t:
          detected.add('todo');
          todoCatId = t.catId;
        case ClassifiedTodoWithTime _:
          detected.add('calendar');
        case ClassifiedIdea _:
          detected.add('idea');
        case ClassifiedNote n:
          detected.add('note');
          noteCatId = n.noteCatId;
        case ClassifiedRecap _:
          detected.add('recap');
      }
    }

    setState(() {
      _detecting = false;
      _status = '';
      _detectedItems = items;
      _selectedMainCats
        ..clear()
        ..addAll(detected);
      _todoCatId = todoCatId;
      _noteCatId = noteCatId;
    });
  }

  // ── Step 2: Confirm and save ───────────────────────────────────────────────

  Future<void> _submit() async {
    if (_detectedItems == null || _processing) return;
    if (_selectedMainCats.isEmpty) {
      _toast('請至少選擇一個類別');
      return;
    }
    FocusScope.of(context).unfocus();

    final todoRepo = context.read<TodoRepo>();
    final eventRepo = context.read<EventRepo>();
    final ideaRepo = context.read<IdeaRepo>();
    final noteRepo = context.read<NoteRepo>();
    final recapRepo = context.read<RecapRepo>();
    final navigator = Navigator.of(context);

    setState(() {
      _processing = true;
      _status = '寫入中…';
    });

    int count = 0;
    for (final cat in _selectedMainCats) {
      final forCat =
          _detectedItems!.where((i) => _itemCatKey(i) == cat).toList();

      if (forCat.isNotEmpty) {
        // Save AI-detected items, applying the user's sub-cat override.
        for (final item in forCat) {
          switch (item) {
            case ClassifiedTodo t:
              await todoRepo.add(Todo(
                id: '',
                title: t.text,
                category: _todoRef(_todoCatId, _todoCats),
              ));
              count++;
            case ClassifiedTodoWithTime tt:
              await eventRepo.add(CalendarEvent(
                id: '',
                title: tt.text,
                startTime: tt.start,
                endTime: tt.end,
                color: AppColors.sage,
                createdAt: DateTime.now(),
              ));
              count++;
            case ClassifiedIdea idea:
              await ideaRepo.add(idea.text);
              count++;
            case ClassifiedNote note:
              final routed = note.attachmentIndices
                  .where((i) => i >= 0 && i < _attachments.length)
                  .map((i) => _attachments[i])
                  .toList();
              await noteRepo.add(
                Note(
                  id: '',
                  dateKey: note.dateKey,
                  content: note.content,
                  category: _noteRef(_noteCatId, _noteCats),
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
                attachments: routed,
              );
              count++;
            case ClassifiedRecap r:
              await recapRepo.add(Recap(
                id: '',
                title: r.title.isEmpty ? '回顧' : r.title,
                content: r.description,
                createdAt: DateTime.now(),
              ));
              count++;
          }
        }
      } else {
        // User manually enabled a category the AI didn't detect — create a
        // basic item from the raw input text.
        final rawText = _textCtrl.text.trim();
        if (rawText.isEmpty) continue;
        switch (cat) {
          case 'todo':
            await todoRepo.add(Todo(
              id: '',
              title: rawText,
              category: _todoRef(_todoCatId, _todoCats),
            ));
            count++;
          case 'idea':
            await ideaRepo.add(rawText);
            count++;
          case 'note':
            await noteRepo.add(
              Note(
                id: '',
                dateKey: _todayKey(),
                content: rawText,
                category: _noteRef(_noteCatId, _noteCats),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
              attachments: _attachments.toList(),
            );
            count++;
          // 'calendar' and 'recap' require structured data; skip if not detected.
        }
      }
    }

    if (!mounted) return;
    navigator.pop();
    scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('已新增 $count 個項目',
            style: AppText.body(size: 13, color: Colors.white)),
        backgroundColor: AppColors.dark,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _itemCatKey(ClassificationItem item) => switch (item) {
        ClassifiedTodoWithTime() => 'calendar',
        ClassifiedTodo() => 'todo',
        ClassifiedIdea() => 'idea',
        ClassifiedNote() => 'note',
        ClassifiedRecap() => 'recap',
      };

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  TodoCategoryRef _todoRef(String id, List<TodoCategory> cats) {
    for (final c in cats) {
      if (c.id == id) {
        return TodoCategoryRef(id: c.id, label: c.label, color: c.color);
      }
    }
    return TodoCategoryRef.undefined;
  }

  NoteCategoryRef _noteRef(String id, List<NoteCategory> cats) {
    for (final c in cats) {
      if (c.id == id) {
        return NoteCategoryRef(
            id: c.id, label: c.label, color: c.color, iconName: c.iconName);
      }
    }
    return NoteCategoryRef.undefined;
  }

  void _toast(String msg) {
    scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: AppText.body(size: 13, color: Colors.white)),
        backgroundColor: AppColors.dark,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Title bar
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Row(
                children: [
                  MrIconButton(
                    icon: LucideIcons.x,
                    iconSize: 17,
                    onTap: _busy ? () {} : () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text('隨手記',
                      style:
                          AppText.display(size: 23, weight: FontWeight.w400)),
                  const Spacer(),
                  const SizedBox(width: 36),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.sparkles,
                            size: 16, color: AppColors.amber),
                        const SizedBox(width: 6),
                        Text('輸入任何內容，AI 會自動分類',
                            style: AppText.body(
                                size: 13,
                                weight: FontWeight.w600,
                                color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '行程、待辦、靈感、札記或回顧都可以混在一起。',
                      style: AppText.caption(size: 11, color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),

                    // Text input
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [kCardShadow],
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: TextField(
                        controller: _textCtrl,
                        maxLines: 8,
                        minLines: 5,
                        enabled: !_processing,
                        decoration: InputDecoration(
                          hintText:
                              '例如：明天早上十點開會、記得買牛奶、想學插畫、今天心情很好…',
                          hintStyle: AppText.body(
                              size: 14, color: AppColors.muted, height: 1.6),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: AppText.body(size: 14, height: 1.6),
                      ),
                    ),

                    // Attachments
                    if (_attachmentsEnabled && _attachments.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('附件',
                          style: AppText.label(
                              size: 12,
                              weight: FontWeight.w500,
                              color: AppColors.dark)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in _attachments)
                            _attachmentChip(
                                a,
                                _busy
                                    ? null
                                    : () =>
                                        setState(() => _attachments.remove(a))),
                        ],
                      ),
                    ],

                    // Recording badge
                    if (_recording) ...[
                      const SizedBox(height: 12),
                      _recordingBadge(),
                    ],

                    // Category section (shown after detection)
                    const SizedBox(height: 16),
                    if (_detecting)
                      _buildDetectingBadge()
                    else if (_detectedItems != null)
                      _buildCategorySection(),
                  ],
                ),
              ),
            ),

            // Action bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(child: _buildPrimaryButton()),
                  if (_attachmentsEnabled) ...[
                    const SizedBox(width: 8),
                    _actionBtn(
                      icon: LucideIcons.paperclip,
                      onTap: _busy ? null : _pickFile,
                    ),
                    const SizedBox(width: 8),
                    _actionBtn(
                      icon: _recording
                          ? LucideIcons.squareSlash
                          : LucideIcons.mic,
                      iconColor: _recording ? AppColors.rose : null,
                      borderColor:
                          _recording ? AppColors.rose.withOpacity(0.4) : null,
                      onTap: _busy ? null : _toggleRecording,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton() {
    // Tapping submits if detection is done; falls back to manual detect otherwise.
    void onTap() {
      if (_processing) return;
      if (_detectedItems != null) {
        _submit();
      } else if (!_detecting) {
        _detect();
      }
    }

    final canTap = !_processing &&
        (_detectedItems != null || (!_detecting && _textCtrl.text.trim().isNotEmpty));

    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: canTap ? AppColors.dark : AppColors.dark.withOpacity(0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: _processing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text(_status,
                        style: AppText.body(size: 14, color: Colors.white)),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.check, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      '確認新增',
                      style: AppText.body(
                          size: 15,
                          weight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDetectingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.muted),
          ),
          const SizedBox(width: 8),
          Text(_status,
              style: AppText.body(size: 13, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _buildCategorySection() {
    // Show recap button only when AI detected a recap item.
    final showRecap = _detectedItems!.any((i) => i is ClassifiedRecap);
    final cats = [..._kBaseCats, if (showRecap) _kRecapCat];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [kCardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              const Icon(LucideIcons.sparkles,
                  size: 13, color: AppColors.amber),
              const SizedBox(width: 5),
              Text('偵測到的類別',
                  style: AppText.label(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.dark)),
              const Spacer(),
              GestureDetector(
                onTap: _processing ? null : _detect,
                child: Text('重新偵測',
                    style:
                        AppText.caption(size: 11, color: AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Main category toggle buttons (multi-select)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cats
                .map((c) => _mainCatChip(c.key, c.label, c.icon, c.color))
                .toList(),
          ),

          // Todo sub-categories (single-select)
          if (_selectedMainCats.contains('todo') && _todoCats.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('待辦分類',
                style: AppText.caption(
                    size: 11,
                    weight: FontWeight.w500,
                    color: AppColors.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _todoCats
                  .map((c) =>
                      _subCatChip(c.id, c.label, c.color, isTodo: true))
                  .toList(),
            ),
          ],

          // Note sub-categories (single-select)
          if (_selectedMainCats.contains('note') && _noteCats.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('札記分類',
                style: AppText.caption(
                    size: 11,
                    weight: FontWeight.w500,
                    color: AppColors.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _noteCats
                  .map((c) =>
                      _subCatChip(c.id, c.label, c.color, isTodo: false))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mainCatChip(
      String key, String label, IconData icon, Color color) {
    final selected = _selectedMainCats.contains(key);
    return GestureDetector(
      onTap: _processing
          ? null
          : () => setState(() {
                if (selected) {
                  _selectedMainCats.remove(key);
                } else {
                  _selectedMainCats.add(key);
                }
              }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13, color: selected ? color : AppColors.muted),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppText.body(
                  size: 13,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? color : AppColors.muted),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.check, size: 11, color: color),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subCatChip(String catId, String label, Color color,
      {required bool isTodo}) {
    final current = isTodo ? _todoCatId : _noteCatId;
    final selected = current == catId;
    return GestureDetector(
      onTap: _processing
          ? null
          : () => setState(
              () => isTodo ? _todoCatId = catId : _noteCatId = catId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: AppText.caption(
              size: 12,
              weight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? color : AppColors.muted),
        ),
      ),
    );
  }

  Widget _attachmentChip(PendingAttachment a, VoidCallback? onRemove) {
    Widget leading;
    if (a.type == 'image') {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(a.bytes, width: 22, height: 22, fit: BoxFit.cover),
      );
    } else {
      leading = Icon(
        a.type == 'audio' ? LucideIcons.music : LucideIcons.fileText,
        size: 13,
        color: AppColors.muted,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              a.filename,
              style: AppText.caption(size: 11, color: AppColors.dark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(LucideIcons.x, size: 11, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    VoidCallback? onTap,
    Color? iconColor,
    Color? borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor ?? AppColors.border),
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
        ),
        child: Icon(icon, size: 18, color: iconColor ?? AppColors.muted),
      ),
    );
  }

  Widget _recordingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.rose.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.rose.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: AppColors.rose, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('錄音中…',
              style: AppText.body(size: 13, color: AppColors.rose)),
        ],
      ),
    );
  }
}
