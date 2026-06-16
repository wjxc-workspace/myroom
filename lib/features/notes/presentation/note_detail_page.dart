import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../core/constants.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/storage/storage_repo.dart';
import '../domain/note.dart';
import '../domain/note_category.dart';
import '../domain/note_repo.dart';
import 'note_style.dart';

/// Hero tag shared between a note's source thumbnail and the large image on this
/// detail page. The [surface] keeps it unique across the shell's kept-alive tabs
/// (the notes list and the recap highlights can show the same note at once, and
/// two live heroes with the same tag would clash), while the matching tag is
/// handed to the detail page via [NoteDetailArgs.heroTag].
String noteImageHeroTag(String noteId, {required String surface}) =>
    'note-image-$surface-$noteId';

/// Payload passed through the route's `extra` to the note detail page: the note
/// itself plus the exact Hero tag of the tapped source (null = no shared image).
class NoteDetailArgs {
  final Note note;
  final String? heroTag;
  const NoteDetailArgs({required this.note, this.heroTag});
}

/// Full-screen view of a single written note, opened at `notes/{note_id}` and
/// pushed over the shell so the source image can fly in via [Hero]. The [note]
/// and [heroTag] arrive through the route's `extra` (so the Hero has data
/// instantly); the page then streams the live note from [NoteRepo] and lets the
/// user edit it in place (title / content / category / attachments). A
/// [StorageRepo] and [NoteRepo] are provided by the route so this works outside
/// the user-scoped tier.
class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({
    super.key,
    required this.noteId,
    required this.note,
    this.heroTag,
  });

  final String noteId;
  final Note? note;
  final String? heroTag;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  // Resolved download URLs keyed by storagePath (null until resolved).
  final Map<String, String?> _urls = {};

  // Live note + categories (null repo = view-only, e.g. signed-out edge case).
  NoteRepo? _repo;
  StreamSubscription<Note?>? _noteSub;
  StreamSubscription<List<NoteCategory>>? _catSub;
  Note? _note;
  List<NoteCategory> _categories = const [];

  // ── Edit-mode state (mirrors the note composer sheet) ───────────────────
  bool _editing = false;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();
  String _catId = kUndefinedCategoryId;
  final List<NoteAttachment> _existing = [];
  final List<PendingAttachment> _added = [];
  final _recorder = AudioRecorder();
  String? _recordingPath;
  bool _recording = false;

  bool get _attachmentsEnabled => !kIsWeb;

  List<NoteAttachment> get _images =>
      _note?.attachments.where((a) => a.type == 'image').toList() ?? const [];

  List<NoteAttachment> get _otherAttachments =>
      _note?.attachments.where((a) => a.type != 'image').toList() ?? const [];

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _resolveImages(_note);
    try {
      _repo = context.read<NoteRepo>();
    } catch (_) {
      _repo = null;
    }
    final repo = _repo;
    if (repo != null) {
      _noteSub = repo.watchNote(widget.noteId).listen((n) {
        if (!mounted) return;
        setState(() => _note = n);
        _resolveImages(n);
      });
      _catSub = repo.watchNoteCategories().listen((cats) {
        if (!mounted) return;
        setState(() => _categories = cats);
      });
    }
  }

  @override
  void dispose() {
    _noteSub?.cancel();
    _catSub?.cancel();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _resolveImages(Note? note) {
    if (note == null) return;
    for (final a in note.attachments.where((a) => a.type == 'image')) {
      if (!_urls.containsKey(a.storagePath)) {
        _urls[a.storagePath] = null; // mark pending
        _resolve(a.storagePath);
      }
    }
  }

  Future<void> _resolve(String storagePath) async {
    try {
      final url = await context.read<StorageRepo>().downloadUrl(storagePath);
      if (mounted) setState(() => _urls[storagePath] = url);
    } catch (_) {
      if (mounted) setState(() => _urls[storagePath] = null);
    }
  }

  // ── Edit mode ─────────────────────────────────────────────────────────────

  void _enterEdit() {
    final note = _note;
    if (note == null) return;
    _titleCtrl.text = note.title == '無標題' ? '' : note.title;
    _contentCtrl.text = note.content;
    _catId = note.category.id;
    _existing
      ..clear()
      ..addAll(note.attachments);
    _added.clear();
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    if (_recording) {
      _recorder.stop();
      _recording = false;
      _recordingPath = null;
    }
    setState(() {
      _editing = false;
      _added.clear();
    });
  }

  Future<void> _save() async {
    final repo = _repo;
    final note = _note;
    if (repo == null || note == null) return;
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (content.isEmpty && _added.isEmpty && _existing.isEmpty) return;

    final cat = _categories.firstWhere(
      (c) => c.id == _catId,
      orElse: () => NoteCategory.undefined,
    );
    final removed = note.attachments
        .where(
          (a) => !_existing.any((k) => k.storagePath == a.storagePath),
        )
        .toList();

    final res = await repo.update(
      note.copyWith(
        title: title.isEmpty ? '無標題' : title,
        content: content,
        category: NoteCategoryRef(
          id: cat.id,
          label: cat.label,
          color: cat.color,
          iconName: cat.iconName,
        ),
        attachments: List<NoteAttachment>.from(_existing),
      ),
      added: List<PendingAttachment>.from(_added),
      removed: removed,
    );
    if (!mounted) return;
    // On success the note stream re-emits the updated doc, refreshing the view.
    if (res is Ok) {
      setState(() {
        _editing = false;
        _added.clear();
      });
    }
  }

  // ── Picker / recorder (mirrors the note composer sheet) ─────────────────

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('「${f.name}」超過 10MB，無法加入')),
          );
        }
        continue;
      }
      final ext = (f.extension ?? '').toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        additions.add(PendingAttachment(
          type: 'image', filename: f.name, bytes: bytes, ext: ext,
        ));
      } else if (['mp3', 'm4a', 'wav', 'ogg'].contains(ext)) {
        additions.add(PendingAttachment(
          type: 'audio', filename: f.name, bytes: bytes, ext: ext,
        ));
      } else if (['txt', 'md'].contains(ext)) {
        additions.add(PendingAttachment(
          type: 'file',
          filename: f.name, bytes: bytes, ext: ext,
          extractedText: utf8.decode(bytes, allowMalformed: true),
        ));
      } else if (ext == 'pdf') {
        final text = await _extractPdfText(bytes);
        additions.add(PendingAttachment(
          type: 'file',
          filename: f.name, bytes: bytes, ext: ext,
          extractedText: text,
        ));
      }
    }
    if (additions.isNotEmpty && mounted) {
      setState(() => _added.addAll(additions));
    }
  }

  Future<String> _extractPdfText(Uint8List bytes) async {
    try {
      final doc = await PdfDocument.openData(bytes);
      final buf = StringBuffer();
      for (int i = 1; i <= doc.pages.length; i++) {
        final page = doc.pages[i - 1];
        final text = await page.loadText();
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
    final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('錄音超過 10MB，無法加入')),
        );
      }
      return;
    }
    setState(() => _added.add(PendingAttachment(
          type: 'audio',
          filename: 'recording.m4a',
          bytes: bytes,
          ext: 'm4a',
        )));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  String _formatDate(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length < 3) return dateKey;
    return '${parts[0]}年${int.parse(parts[1])}月${int.parse(parts[2])}日';
  }

  void _openViewer(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    Widget body;
    if (note == null) {
      body = _notFound();
    } else if (_editing) {
      body = _editContent(note);
    } else {
      body = _content(note);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: body),
    );
  }

  Widget _notFound() {
    return Column(
      children: [
        _header(null),
        const Expanded(
          child: Center(
            child: Text('找不到這份札記', style: TextStyle(color: AppColors.muted)),
          ),
        ),
      ],
    );
  }

  // ── Read-only content ─────────────────────────────────────────────────────

  Widget _content(Note note) {
    final cat = note.category;
    final imgWidth = MediaQuery.of(context).size.width * 0.8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(note),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              // Category chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cat.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cat.label,
                  style: AppText.caption(size: 11, color: cat.color),
                ),
              ),
              if (note.title.isNotEmpty && note.title != '無標題') ...[
                const SizedBox(height: 12),
                Text(
                  note.title,
                  style: AppText.display(size: 24, weight: FontWeight.w600),
                ),
              ],
              if (note.content.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  note.content,
                  style: AppText.body(size: 15, height: 1.7),
                ),
              ],
              // Images — first one shares the Hero with the list thumbnail.
              for (var i = 0; i < _images.length; i++) ...[
                const SizedBox(height: 18),
                Center(
                  child: _imageView(
                    _images[i],
                    width: imgWidth,
                    heroTag: i == 0 ? widget.heroTag : null,
                  ),
                ),
              ],
              // Non-image attachments
              if (_otherAttachments.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _otherAttachments.map((a) => _infoChip(a)).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Inline edit content (same field positions as the read-only view) ──────

  Widget _editContent(Note note) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(note),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              // Category (where the read-only chip sits)
              _editLabel('分類'),
              const SizedBox(height: 6),
              _categoryChips(),
              const SizedBox(height: 16),

              // Title
              _editLabel('標題'),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtrl,
                decoration: _fieldDecoration('無標題'),
                style: AppText.body(size: 14),
              ),
              const SizedBox(height: 16),

              // Content
              _editLabel('內容'),
              const SizedBox(height: 6),
              TextField(
                controller: _contentCtrl,
                minLines: 4,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: _fieldDecoration('在這裡寫下這則札記...'),
                style: AppText.body(size: 14, height: 1.6),
              ),

              if (_existing.isNotEmpty) ...[
                const SizedBox(height: 16),
                _editLabel('現有附件'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in _existing)
                      _existingChip(
                          a, () => setState(() => _existing.remove(a))),
                  ],
                ),
              ],

              if (_attachmentsEnabled && _added.isNotEmpty) ...[
                const SizedBox(height: 16),
                _editLabel('新增的附件'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in _added)
                      _newChip(a, () => setState(() => _added.remove(a))),
                  ],
                ),
              ],

              if (_recording) ...[
                const SizedBox(height: 12),
                _recordingBadge(),
              ],

              if (_attachmentsEnabled) ...[
                const SizedBox(height: 18),
                _editLabel('附加'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _actionBtn(
                      icon: LucideIcons.paperclip,
                      onTap: _pickFile,
                    ),
                    const SizedBox(width: 10),
                    _actionBtn(
                      icon: _recording
                          ? LucideIcons.squareSlash
                          : LucideIcons.mic,
                      iconColor: _recording ? AppColors.rose : null,
                      borderColor:
                          _recording ? AppColors.rose.withOpacity(0.4) : null,
                      onTap: _toggleRecording,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Header (back / date, plus pencil ⇄ save·cancel in edit mode) ──────────

  Widget _header(Note? note) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: _editing ? _cancelEdit : () => context.pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _editing ? LucideIcons.x : LucideIcons.chevronLeft,
                size: 18,
                color: AppColors.dark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (note != null)
            Text(
              _formatDate(note.dateKey),
              style: AppText.body(size: 15, weight: FontWeight.w600),
            ),
          const Spacer(),
          if (note != null && _repo != null)
            GestureDetector(
              onTap: _editing ? _save : _enterEdit,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _editing ? AppColors.dark : AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _editing ? LucideIcons.check : LucideIcons.pencil,
                  size: 18,
                  color: _editing ? Colors.white : AppColors.dark,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Category chooser (live stream + inline creation) ──────────────────────

  Widget _categoryChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in _categories)
          _subCatChip(
            label: c.label,
            selected: _catId == c.id,
            onTap: () => setState(() => _catId = c.id),
          ),
        if (_repo != null) _addCatChip(),
      ],
    );
  }

  Widget _subCatChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.dark.withOpacity(0.85) : AppColors.border,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: AppText.caption(
            size: 12,
            color: selected ? Colors.white : AppColors.dark,
          ),
        ),
      ),
    );
  }

  Widget _addCatChip() {
    return GestureDetector(
      onTap: _showAddCategoryDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.plus, size: 12, color: AppColors.muted),
            const SizedBox(width: 4),
            Text('新增分類',
                style: AppText.caption(size: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  void _showAddCategoryDialog() {
    final repo = _repo;
    if (repo == null) return;
    final categories = _categories;
    final labelCtrl = TextEditingController();
    String selectedIcon =
        kNoteIconKeys[categories.length % kNoteIconKeys.length];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: AppColors.bg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('新增分類',
              style: AppText.body(size: 16, weight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: labelCtrl,
                autofocus: true,
                decoration: _dialogFieldDecoration('分類名稱'),
                style: AppText.body(size: 14),
              ),
              const SizedBox(height: 14),
              Text('選擇圖示',
                  style: AppText.caption(size: 11, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: kNoteIconKeys.map((key) {
                  final isSelected = key == selectedIcon;
                  return GestureDetector(
                    onTap: () => setDialog(() => selectedIcon = key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.dark : AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(kNoteIconMap[key]!,
                          size: 16,
                          color: isSelected ? Colors.white : AppColors.muted),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('取消',
                  style: AppText.body(size: 14, color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () async {
                final label = labelCtrl.text.trim();
                if (label.isEmpty) return;
                Navigator.pop(ctx);
                final idx = categories.length;
                final color = kNoteCatPalette[idx % kNoteCatPalette.length];
                final res = await repo.addNoteCategory(
                  NoteCategory(
                    id: '',
                    label: label,
                    iconName: selectedIcon,
                    color: color,
                    sortOrder: idx,
                  ),
                );
                if (!mounted) return;
                if (res case Ok(value: final id)) {
                  setState(() => _catId = id);
                }
              },
              child: Text('新增',
                  style: AppText.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.dark)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Small shared widgets ──────────────────────────────────────────────────

  Widget _editLabel(String text) => Text(
        text,
        style: AppText.label(
            size: 12, weight: FontWeight.w500, color: AppColors.dark),
      );

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(color: AppColors.muted),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      );

  InputDecoration _dialogFieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(color: AppColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dark),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      );

  Widget _existingChip(NoteAttachment a, VoidCallback onRemove) {
    Widget leading;
    if (a.type == 'image') {
      // Show the saved image as a small thumbnail, matching newly-added ones.
      final url = _urls[a.storagePath];
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: url == null
            ? _thumbPlaceholder()
            : Image.network(
                url,
                width: 22,
                height: 22,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _thumbPlaceholder(),
              ),
      );
    } else {
      leading = Icon(_iconFor(a.type), size: 13, color: AppColors.muted);
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
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(LucideIcons.x, size: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
        width: 22,
        height: 22,
        color: Colors.white,
        child: const Icon(LucideIcons.image, size: 12, color: AppColors.muted),
      );

  Widget _newChip(PendingAttachment a, VoidCallback onRemove) {
    Widget leading;
    if (a.type == 'image') {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(a.bytes, width: 22, height: 22, fit: BoxFit.cover),
      );
    } else {
      leading = Icon(_iconFor(a.type), size: 13, color: AppColors.muted);
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
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(LucideIcons.x, size: 11, color: AppColors.muted),
          ),
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
        width: 48,
        height: 48,
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
          Text('錄音中…', style: AppText.body(size: 13, color: AppColors.rose)),
        ],
      ),
    );
  }

  IconData _iconFor(String t) => switch (t) {
        'image' => LucideIcons.image,
        'audio' => LucideIcons.music,
        _ => LucideIcons.fileText,
      };

  Widget _imageView(NoteAttachment att,
      {required double width, String? heroTag}) {
    final url = _urls[att.storagePath];
    Widget image;
    if (url == null) {
      // URL still resolving (or failed) — show the "image loading" placeholder.
      image = _imageLoadingBox(width);
    } else {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          url,
          width: width,
          fit: BoxFit.fitWidth,
          // Keep the placeholder up while the bytes download from Storage, so a
          // slow connection never leaves a blank gap where the image will be.
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _imageLoadingBox(width),
          errorBuilder: (_, __, ___) => Container(
            width: width,
            height: width * 0.66,
            color: AppColors.border,
            child: const Icon(LucideIcons.imageOff,
                size: 28, color: AppColors.muted),
          ),
        ),
      );
      image = GestureDetector(onTap: () => _openViewer(url), child: image);
    }
    if (heroTag != null) {
      return Hero(tag: heroTag, child: image);
    }
    return image;
  }

  /// Neutral "an image is loading" placeholder sized to the big image slot.
  Widget _imageLoadingBox(double width) => Container(
        width: width,
        height: width * 0.66,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.image, size: 28, color: AppColors.muted),
            SizedBox(height: 10),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.muted),
            ),
          ],
        ),
      );

  Widget _infoChip(NoteAttachment att) {
    final icon =
        att.type == 'audio' ? LucideIcons.music : LucideIcons.fileText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              att.filename,
              style: AppText.caption(size: 11, color: AppColors.dark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
