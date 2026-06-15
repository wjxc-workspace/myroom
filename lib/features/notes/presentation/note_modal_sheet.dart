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
import 'package:record/record.dart';

import '../../../core/constants.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/note.dart';
import '../domain/note_category.dart';
import '../domain/note_repo.dart';
import 'note_style.dart';

/// The result returned by the note composer sheet, for both create and edit.
class NoteSheetResult {
  /// Title; empty -> persisted as 無標題 by the page.
  final String title;
  final String content;

  /// Selected category id (defaults to the 無分類 sentinel).
  final String catId;

  /// Freshly picked / recorded attachments to upload.
  final List<PendingAttachment> added;

  /// Existing attachments the user kept (edit mode); the page diffs these
  /// against the original to compute removals. Empty for a brand-new note.
  final List<NoteAttachment> keptAttachments;

  const NoteSheetResult({
    required this.title,
    required this.content,
    required this.catId,
    required this.added,
    this.keptAttachments = const [],
  });
}

/// Opens the shared bottom sheet used to compose or edit a note.
///
/// Pass [note] to open in edit mode (prefilled, with removable existing
/// attachments). Pass [repo] to enable inline category creation (a `新增分類`
/// chip); when null the category chips are read-only from [categories].
Future<NoteSheetResult?> showNoteModalSheet(
  BuildContext context, {
  required String dateKey,
  required List<NoteCategory> categories,
  String? initialCatId,
  Note? note,
  NoteRepo? repo,
}) {
  return showModalBottomSheet<NoteSheetResult>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NoteSheet(
      dateKey: dateKey,
      categories: categories,
      initialCatId: initialCatId,
      note: note,
      repo: repo,
    ),
  );
}

class _NoteSheet extends StatefulWidget {
  final String dateKey;
  final List<NoteCategory> categories;
  final String? initialCatId;
  final Note? note;
  final NoteRepo? repo;

  const _NoteSheet({
    required this.dateKey,
    required this.categories,
    required this.initialCatId,
    this.note,
    this.repo,
  });

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late String _catId;
  final List<PendingAttachment> _added = [];
  final List<NoteAttachment> _existing = [];
  final _recorder = AudioRecorder();
  String? _recordingPath;
  bool _recording = false;

  bool get _attachmentsEnabled => !kIsWeb;
  bool get _isEdit => widget.note != null;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleCtrl = TextEditingController(
      text: (note != null && note.title != '無標題') ? note.title : '',
    );
    _contentCtrl = TextEditingController(text: note?.content ?? '');
    _catId = note?.category.id ?? widget.initialCatId ?? kUndefinedCategoryId;
    if (note != null) _existing.addAll(note.attachments);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Picker / recorder ──────────────────────────────────────────────────

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

  // ── Save ────────────────────────────────────────────────────────────────

  void _save() {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (content.isEmpty && _added.isEmpty && _existing.isEmpty) return;
    Navigator.pop(
      context,
      NoteSheetResult(
        title: title,
        content: content,
        catId: _catId,
        added: _added,
        keptAttachments: _existing,
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isEdit ? '編輯札記' : '新增札記',
                style: AppText.body(
                    size: 16, weight: FontWeight.w600, color: AppColors.dark),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(widget.dateKey),
                style: AppText.caption(size: 11, color: AppColors.muted),
              ),
              const SizedBox(height: 14),

              Text('標題',
                  style: AppText.label(
                      size: 12, weight: FontWeight.w500, color: AppColors.dark)),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  hintText: '無標題',
                  hintStyle: AppText.body(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                ),
                style: AppText.body(size: 14),
              ),

              _buildCategorySection(),

              const SizedBox(height: 14),

              Text('內容',
                  style: AppText.label(
                      size: 12, weight: FontWeight.w500, color: AppColors.dark)),
              const SizedBox(height: 6),
              TextField(
                controller: _contentCtrl,
                maxLines: 5,
                minLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '在這裡寫下這則札記...',
                  hintStyle: AppText.body(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                ),
                style: AppText.body(size: 14, height: 1.6),
              ),

              if (_existing.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('現有附件',
                    style: AppText.label(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.dark)),
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
                    for (final a in _added)
                      _newChip(a, () => setState(() => _added.remove(a))),
                  ],
                ),
              ],

              if (_recording) ...[
                const SizedBox(height: 12),
                _recordingBadge(),
              ],

              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _save,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.dark,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            _isEdit ? '更新札記' : '儲存札記',
                            style: AppText.body(
                                size: 15,
                                weight: FontWeight.w600,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_attachmentsEnabled) ...[
                    const SizedBox(width: 8),
                    _actionBtn(
                      icon: LucideIcons.paperclip,
                      onTap: _pickFile,
                    ),
                    const SizedBox(width: 8),
                    _actionBtn(
                      icon: _recording
                          ? LucideIcons.squareSlash
                          : LucideIcons.mic,
                      iconColor: _recording ? AppColors.rose : null,
                      borderColor:
                          _recording ? AppColors.rose.withOpacity(0.4) : null,
                      onTap: _toggleRecording,
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
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

  // ── Category section (live + inline creation when a repo is supplied) ─────

  Widget _buildCategorySection() {
    final repo = widget.repo;
    if (repo == null) {
      if (widget.categories.isEmpty) return const SizedBox.shrink();
      return _categoryBlock(widget.categories, allowAdd: false);
    }
    return StreamBuilder<List<NoteCategory>>(
      stream: repo.watchNoteCategories(),
      initialData: widget.categories,
      builder: (context, snap) =>
          _categoryBlock(snap.data ?? const <NoteCategory>[], allowAdd: true),
    );
  }

  Widget _categoryBlock(List<NoteCategory> categories,
      {required bool allowAdd}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text('分類',
            style: AppText.label(
                size: 12, weight: FontWeight.w500, color: AppColors.dark)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in categories)
              _subCatChip(
                label: c.label,
                selected: _catId == c.id,
                onTap: () => setState(() => _catId = c.id),
              ),
            if (allowAdd) _addCatChip(categories),
          ],
        ),
      ],
    );
  }

  Widget _addCatChip(List<NoteCategory> categories) {
    return GestureDetector(
      onTap: () => _showAddCategoryDialog(categories),
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

  void _showAddCategoryDialog(List<NoteCategory> categories) {
    final repo = widget.repo;
    if (repo == null) return;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(a.type), size: 13, color: AppColors.muted),
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

  String _formatDate(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length < 3) return dateKey;
    return '${int.parse(parts[1])}月${int.parse(parts[2])}日';
  }
}
