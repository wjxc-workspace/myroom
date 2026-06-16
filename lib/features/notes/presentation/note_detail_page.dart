import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/storage/storage_repo.dart';
import '../domain/note.dart';

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
/// and [heroTag] arrive through the route's `extra`; a [StorageRepo] is provided
/// by the route so attachment URLs resolve here without the user-scoped tier.
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

  List<NoteAttachment> get _images =>
      widget.note?.attachments.where((a) => a.type == 'image').toList() ??
      const [];

  List<NoteAttachment> get _otherAttachments =>
      widget.note?.attachments.where((a) => a.type != 'image').toList() ??
      const [];

  @override
  void initState() {
    super.initState();
    for (final img in _images) {
      _resolve(img.storagePath);
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
    final note = widget.note;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: note == null ? _notFound() : _content(note),
      ),
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
                  children: _otherAttachments
                      .map((a) => _infoChip(a))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(Note? note) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.chevronLeft,
                  size: 18, color: AppColors.dark),
            ),
          ),
          const SizedBox(width: 12),
          if (note != null)
            Text(
              _formatDate(note.dateKey),
              style: AppText.body(size: 15, weight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _imageView(NoteAttachment att,
      {required double width, String? heroTag}) {
    final url = _urls[att.storagePath];
    Widget image;
    if (url == null) {
      // Loading or failed — neutral placeholder at the target width.
      image = Container(
        width: width,
        height: width * 0.66,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(LucideIcons.image, size: 28, color: AppColors.muted),
      );
    } else {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          url,
          width: width,
          fit: BoxFit.fitWidth,
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
