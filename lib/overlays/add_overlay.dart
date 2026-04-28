import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../models/note_item.dart' show NoteCategory;
import '../models/todo_item.dart' show TodoCategory;
import '../services/database_service.dart';
import '../theme.dart';
import '../services/openai_service.dart';

// ─── Attachment model ─────────────────────────────────────────────────────────

enum _AttachType { image, audio, textFile }

class _Attachment {
  final _AttachType type;
  final String name;
  final Uint8List bytes;
  final String? preExtractedText;

  const _Attachment({
    required this.type,
    required this.name,
    required this.bytes,
    this.preExtractedText,
  });
}

// ─── Type constants (回顧 excluded from add overlay) ──────────────────────────

const _kTypeOptions = [
  ('行程', 'todo_with_time'),
  ('待辦', 'todo'),
  ('靈感', 'idea'),
  ('筆記', 'note'),
];


// ─── AddOverlay ───────────────────────────────────────────────────────────────

class AddOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<ClassificationResult> onItemClassified;

  const AddOverlay({
    super.key,
    required this.onClose,
    required this.onItemClassified,
  });

  @override
  State<AddOverlay> createState() => _AddOverlayState();
}

class _AddOverlayState extends State<AddOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  final _textCtrl = TextEditingController();
  final _recorder = AudioRecorder();
  final List<_Attachment> _attachments = [];

  bool _loading = false;
  bool _recording = false;
  String? _summaryLabel;

  // ── Dynamic categories (loaded from DB) ──────────────────────────────────────
  List<TodoCategory> _todoCats = [];
  List<NoteCategory> _noteCats = [];

  // ── Editor prediction state ───────────────────────────────────────────────────
  Set<String> _selectedTypes = {};
  String _selectedCat = '';        // TodoCategory for 待辦
  String _selectedEventCat = '';   // TodoCategory for 行程
  String? _selectedNoteCatId;      // NoteCategory id for 筆記; null = AI decides
  bool _userOverrode = false;        // blocks type keyword auto-update
  bool _todoCatUserOverrode = false; // blocks todo/event cat auto-update
  bool _noteCatUserOverrode = false; // blocks note-cat keyword auto-update

  // Keyword → type-key map (回顧 excluded).
  static const _kwMap = {
    'todo_with_time': ['會議', '約', '早上', '上午', '下午', '晚上', '今天', '明天', '預約', '安排'],
    'todo':           ['要', '需要', '記得', '買', '完成', '處理', '幫', '提醒', '做', '去'],
    'idea':           ['如果', '想法', '或許', '試', '發現', '感覺', '有趣'],
    'note':           ['上週', '上禮拜', '昨天', '今天', '感受', '開心', '煩', '無聊', '覺得'],
  };

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final todo = await DatabaseService.instance.getCategories();
    final note = await DatabaseService.instance.getNoteCategories();
    if (!mounted) return;
    setState(() {
      _todoCats = todo;
      _noteCats = note;
      if (_selectedCat.isEmpty && todo.isNotEmpty) {
        _selectedCat = todo.first.name;
        _selectedEventCat = todo.first.name;
      }
    });
  }

  // Predict a TodoCategory name by matching category names against text.
  String _predictTodoCat(String text) {
    if (_todoCats.isEmpty) return '';
    for (final cat in _todoCats) {
      final words = cat.name.split(RegExp(r'[\s、，,]+'));
      if (words.any((w) => w.length > 1 && text.contains(w))) return cat.name;
    }
    return _todoCats.first.name;
  }

  // Predict a NoteCategory id by matching category labels against note text.
  String? _predictNoteCat(String text) {
    if (_noteCats.isEmpty) return null;
    for (final cat in _noteCats) {
      final words = cat.label.split(RegExp(r'[\s、，,]+'));
      if (words.any((w) => w.length > 1 && text.contains(w))) return cat.id;
    }
    return null; // no match → AI decides
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _textCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Keyword auto-prediction ───────────────────────────────────────────────────

  void _onTextChanged(String text) {
    if (text.length <= 4) {
      setState(() {
        _selectedTypes.clear();
        _userOverrode = false;
        _todoCatUserOverrode = false;
        _selectedNoteCatId = null;
        _noteCatUserOverrode = false;
      });
      return;
    }
    setState(() {
      // Type prediction — todo_with_time and todo are mutually exclusive:
      // if time-based is detected, plain todo is suppressed.
      if (!_userOverrode) {
        final predicted = <String>{};
        for (final e in _kwMap.entries) {
          if (e.value.any((kw) => text.contains(kw))) predicted.add(e.key);
        }
        if (predicted.contains('todo_with_time')) predicted.remove('todo');
        _selectedTypes = predicted;
      }
      // TodoCategory prediction for both 待辦 and 行程.
      if (!_todoCatUserOverrode) {
        final cat = _predictTodoCat(text);
        _selectedCat = cat;
        _selectedEventCat = cat;
      }
      // NoteCategory prediction.
      if (!_noteCatUserOverrode) {
        _selectedNoteCatId = _predictNoteCat(text);
      }
    });
  }

  void _toggleType(String key) {
    setState(() {
      _userOverrode = true;
      if (_selectedTypes.contains(key)) {
        _selectedTypes.remove(key);
      } else {
        _selectedTypes.add(key);
        // Enforce mutual exclusivity: items with time → 行程 only; without → 待辦 only.
        if (key == 'todo_with_time') _selectedTypes.remove('todo');
        if (key == 'todo') _selectedTypes.remove('todo_with_time');
      }
    });
  }

  // ── File picker ──────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'gif', 'webp',
        'mp3', 'm4a', 'wav', 'ogg',
        'txt', 'md', 'pdf',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final list = <_Attachment>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final ext = (file.extension ?? '').toLowerCase();
      final name = file.name;
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        list.add(_Attachment(type: _AttachType.image, name: name, bytes: bytes));
      } else if (['mp3', 'm4a', 'wav', 'ogg'].contains(ext)) {
        list.add(_Attachment(type: _AttachType.audio, name: name, bytes: bytes));
      } else if (['txt', 'md'].contains(ext)) {
        list.add(_Attachment(
            type: _AttachType.textFile,
            name: name,
            bytes: bytes,
            preExtractedText: utf8.decode(bytes, allowMalformed: true)));
      } else if (ext == 'pdf') {
        list.add(_Attachment(
            type: _AttachType.textFile,
            name: name,
            bytes: bytes,
            preExtractedText: await _extractPdfText(bytes, name)));
      }
    }
    if (list.isNotEmpty && mounted) setState(() => _attachments.addAll(list));
  }

  Future<String> _extractPdfText(Uint8List bytes, String name) async {
    try {
      final doc = await PdfDocument.openData(bytes);
      final buf = StringBuffer();
      for (int i = 1; i <= doc.pages.length; i++) {
        buf.write((await doc.pages[i - 1].loadText()).fullText);
        buf.write('\n');
      }
      return buf.toString().trim();
    } catch (e) {
      debugPrint('PDF extraction error ($name): $e');
      return '';
    }
  }

  // ── Recording ────────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (Platform.isAndroid || Platform.isIOS) {
      if (!(await Permission.microphone.request()).isGranted) return;
    }
    final path =
        '${Directory.systemTemp.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    await file.delete();
    if (bytes.isNotEmpty && mounted) {
      setState(() => _attachments.add(_Attachment(
          type: _AttachType.audio,
          name: 'recording.m4a',
          bytes: Uint8List.fromList(bytes))));
    }
  }

  // ── Save: always AI, pre-selection injected as hint ───────────────────────────

  Future<void> _save() async {
    final text = _textCtrl.text.trim();
    if (_loading || (text.isEmpty && _attachments.isEmpty)) return;
    setState(() { _loading = true; _summaryLabel = null; });

    final results = await _runAI(text);
    if (!mounted) return;

    for (final r in results) {
      widget.onItemClassified(r);
    }

    setState(() {
      _loading = false;
      _summaryLabel = _buildSummary(results);
    });
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) _close();
  }

  // Run AI. If the user pre-selected types/cat on the editor page, inject them
  // as a hint so the AI respects the preference while still splitting correctly.
  Future<List<ClassificationResult>> _runAI(String text) async {
    // Build hint prefix from editor-page selection.
    String inputText = text;
    if (_selectedTypes.isNotEmpty) {
      final hints = <String>[];
      if (_selectedTypes.contains('todo') && _selectedCat.isNotEmpty) {
        hints.add('待辦($_selectedCat)');
      }
      if (_selectedTypes.contains('todo_with_time') && _selectedEventCat.isNotEmpty) {
        hints.add('行程($_selectedEventCat)');
      }
      if (_selectedTypes.contains('idea')) { hints.add('靈感'); }
      if (_selectedTypes.contains('note'))  { hints.add('筆記'); }
      inputText = '[用戶預選：${hints.join("、")}]\n$text';
    }

    final audioAttachments =
        _attachments.where((a) => a.type == _AttachType.audio).toList();
    final transcripts = await Future.wait(
      audioAttachments.map(
          (a) => OpenAIService.instance.transcribeAudio(a.bytes, a.name)),
    );
    final fileTexts = _attachments
        .where((a) => a.type == _AttachType.textFile)
        .map((a) => '[檔案：${a.name}]\n${a.preExtractedText ?? ''}')
        .toList();
    final parts = [
      inputText,
      ...transcripts.whereType<String>().map((t) => '[音訊] $t'),
      ...fileTexts,
    ].where((s) => s.isNotEmpty).toList();
    final finalText = parts.join('\n\n');

    final base64Images = _attachments
        .where((a) => a.type == _AttachType.image)
        .map((a) => base64Encode(a.bytes))
        .toList();

    final raw = await OpenAIService.instance.classifyMultiInput(
      finalText.isNotEmpty ? finalText : null,
      base64Images: base64Images,
    );

    final today = _todayStr();
    return raw.map((r) {
      if (r is ClassificationError) {
        return ClassifiedNote(
            dateKey: today,
            content: r.rawText ?? r.message,
            preCatId: _selectedNoteCatId);
      }
      if (r is ClassifiedRecap) {
        return ClassifiedNote(
            dateKey: today,
            content: r.title,
            preCatId: _selectedNoteCatId);
      }
      if (r is ClassifiedNote) {
        // Inject user's pre-selected NoteCategory (null = let AI decide).
        return ClassifiedNote(
            dateKey: r.dateKey,
            content: r.content,
            preCatId: _selectedNoteCatId);
      }
      return r;
    }).toList();
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  String _buildSummary(List<ClassificationResult> results) {
    if (results.isEmpty) return '✓ 已儲存';
    int todos = 0, events = 0, ideas = 0, notes = 0;
    for (final r in results) {
      if (r is ClassifiedTodo) todos++;
      if (r is ClassifiedTodoWithTime) events++;
      if (r is ClassifiedIdea) ideas++;
      if (r is ClassifiedNote) notes++;
    }
    final parts = <String>[];
    if (events > 0) parts.add('$events 行程');
    if (todos > 0) parts.add('$todos 待辦');
    if (ideas > 0) parts.add('$ideas 靈感');
    if (notes > 0) parts.add('$notes 筆記');
    return '✓ 新增 ${parts.join('、')}';
  }

  void _close() => _ctrl.reverse().then((_) => widget.onClose());

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showPrediction =
        _textCtrl.text.length > 4 && !_loading && _summaryLabel == null;
    final showTodoCat =
        showPrediction && _selectedTypes.contains('todo') && _todoCats.isNotEmpty;
    final showEventCat =
        showPrediction && _selectedTypes.contains('todo_with_time') && _todoCats.isNotEmpty;
    final showNoteCat =
        showPrediction && _selectedTypes.contains('note') && _noteCats.isNotEmpty;
    final canSave =
        !_loading && (_textCtrl.text.trim().isNotEmpty || _attachments.isNotEmpty);

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Container(
            color: AppColors.bg,
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('新增',
                            style: AppText.display(
                                size: 28,
                                weight: FontWeight.w500,
                                italic: true)),
                        Text('輸入任何想記錄的東西',
                            style: AppText.label(size: 12)),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _close,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(LucideIcons.x,
                            size: 16, color: AppColors.dark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Text input ───────────────────────────────────────────────
                Expanded(child: _buildInputArea()),

                // ── Prediction chips (appears below input when text > 4 chars) ─
                if (showPrediction) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('預測分類',
                          style: AppText.caption(
                              size: 11, letterSpacing: 0.6)),
                      const SizedBox(width: 6),
                      Text('（可調整）',
                          style: AppText.caption(
                              size: 10, color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Type chips — 4 options, no 回顧, multi-select
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _kTypeOptions.map((opt) {
                      final label = opt.$1;
                      final key = opt.$2;
                      final active = _selectedTypes.contains(key);
                      return GestureDetector(
                        onTap: () => _toggleType(key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.dark
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            label,
                            style: AppText.body(
                              size: 13,
                              weight: FontWeight.w500,
                              color: active
                                  ? Colors.white
                                  : AppColors.dark,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  // ── 待辦分類 ─────────────────────────────────────────────
                  if (showTodoCat) ...[
                    const SizedBox(height: 10),
                    Text('待辦分類',
                        style: AppText.caption(size: 10, letterSpacing: 0.5, color: AppColors.muted)),
                    const SizedBox(height: 4),
                    _buildCatChips(
                      cats: _todoCats.map((c) => (c.name, c.name)).toList(),
                      selected: _selectedCat,
                      onSelect: (v) => setState(() { _selectedCat = v; _todoCatUserOverrode = true; }),
                      activeColor: AppColors.amber,
                    ),
                  ],
                  // ── 行程分類 ─────────────────────────────────────────────
                  if (showEventCat) ...[
                    const SizedBox(height: 10),
                    Text('行程分類',
                        style: AppText.caption(size: 10, letterSpacing: 0.5, color: AppColors.muted)),
                    const SizedBox(height: 4),
                    _buildCatChips(
                      cats: _todoCats.map((c) => (c.name, c.name)).toList(),
                      selected: _selectedEventCat,
                      onSelect: (v) => setState(() { _selectedEventCat = v; _todoCatUserOverrode = true; }),
                      activeColor: AppColors.amber,
                    ),
                  ],
                  // ── 筆記分類 ─────────────────────────────────────────────
                  if (showNoteCat) ...[
                    const SizedBox(height: 10),
                    Text('筆記分類',
                        style: AppText.caption(size: 10, letterSpacing: 0.5, color: AppColors.muted)),
                    const SizedBox(height: 4),
                    _buildCatChips(
                      cats: _noteCats.map((c) => (c.id, c.label)).toList(),
                      selected: _selectedNoteCatId,
                      onSelect: (v) => setState(() {
                        _selectedNoteCatId = v;
                        _noteCatUserOverrode = true;
                      }),
                      activeColor: AppColors.blue,
                    ),
                    if (_selectedNoteCatId == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('AI 自動分類',
                            style: AppText.caption(size: 10, color: AppColors.muted)),
                      ),
                  ],
                ],

                // ── Recording indicator ──────────────────────────────────────
                if (_recording) ...[
                  const SizedBox(height: 14),
                  _RecordingBadge(),
                ],

                // ── Summary chip (post-save) ──────────────────────────────────
                if (_summaryLabel != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.sage.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_summaryLabel!,
                        style: AppText.body(
                            size: 13, color: AppColors.sage)),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Action row ───────────────────────────────────────────────
                Row(
                  children: [
                    _ActionBtn(
                        icon: LucideIcons.paperclip,
                        onTap: _loading ? null : _pickFile),
                    const SizedBox(width: 10),
                    _ActionBtn(
                      icon: _recording
                          ? LucideIcons.squareSlash
                          : LucideIcons.mic,
                      iconColor: _recording ? AppColors.rose : null,
                      borderColor: _recording
                          ? AppColors.rose.withOpacity(0.4)
                          : null,
                      onTap: _loading ? null : _toggleRecording,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: canSave ? _save : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: canSave
                                ? AppColors.dark
                                : AppColors.dark.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : Text('儲存',
                                    style: AppText.body(
                                        size: 14,
                                        weight: FontWeight.w600,
                                        color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Generic sub-category chip row.
  // cats: list of (value, label) pairs; selected: current value; null = none selected.
  Widget _buildCatChips({
    required List<(String, String)> cats,
    required String? selected,
    required void Function(String) onSelect,
    required Color activeColor,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: cats.map((cat) {
        final value = cat.$1;
        final label = cat.$2;
        final active = selected == value;
        return GestureDetector(
          onTap: () => onSelect(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: active ? activeColor.withOpacity(0.15) : AppColors.border,
              borderRadius: BorderRadius.circular(10),
              border: active ? Border.all(color: activeColor.withOpacity(0.5)) : null,
            ),
            child: Text(
              label,
              style: AppText.body(
                size: 12,
                color: active ? activeColor : AppColors.dark,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000),
              blurRadius: 20,
              offset: Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              maxLines: null,
              expands: true,
              autofocus: true,
              decoration: InputDecoration(
                hintText:
                    '輸入任何東西...\n\n今天想到、看到、計畫的——都可以放這裡',
                hintStyle:
                    AppText.body(color: AppColors.muted, height: 1.7),
                border: InputBorder.none,
              ),
              style: AppText.body(size: 15, height: 1.7),
              onChanged: _onTextChanged,
            ),
          ),
          if (_attachments.isNotEmpty) ...[
            const Divider(height: 20),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 8),
                itemBuilder: (_, i) => _AttachChip(
                  attachment: _attachments[i],
                  onRemove: () =>
                      setState(() => _attachments.removeAt(i)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _AttachChip extends StatelessWidget {
  final _Attachment attachment;
  final VoidCallback onRemove;
  const _AttachChip(
      {required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final icon = switch (attachment.type) {
      _AttachType.image => LucideIcons.image,
      _AttachType.audio => LucideIcons.music,
      _AttachType.textFile => LucideIcons.fileText,
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(attachment.name,
                style:
                    AppText.caption(size: 11, color: AppColors.dark),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(LucideIcons.x,
                size: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  color: AppColors.rose, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('錄音中…',
              style:
                  AppText.body(size: 13, color: AppColors.rose)),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? borderColor;
  const _ActionBtn(
      {required this.icon,
      this.onTap,
      this.iconColor,
      this.borderColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          border:
              Border.all(color: borderColor ?? AppColors.border),
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
        ),
        child: Icon(icon,
            size: 20, color: iconColor ?? AppColors.muted),
      ),
    );
  }
}
