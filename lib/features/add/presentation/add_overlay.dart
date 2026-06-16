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
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mr_icon_button.dart';
import '../../notes/domain/note.dart';
import 'smart_add_controller.dart';

/// Smart Add overlay (AI_proxy.md §5, Storage.md §4). Collects free text +
/// attachments and hands them to [SmartAddController] on submit, then closes
/// immediately — transcription + classification run in the background and the
/// result surfaces as the shell's Smart Add bar.
class AddOverlay extends StatefulWidget {
  const AddOverlay({super.key, this.onClose});

  /// When the overlay is embedded as a page in the swipe strip, [onClose] slides
  /// the strip back to the calendar; when pushed as a route it is null and the
  /// overlay pops instead.
  final VoidCallback? onClose;

  @override
  State<AddOverlay> createState() => _AddOverlayState();
}

class _AddOverlayState extends State<AddOverlay> {
  final _textCtrl = TextEditingController();
  final List<PendingAttachment> _attachments = [];
  final _recorder = AudioRecorder();
  String? _recordingPath;
  bool _recording = false;

  // Mirrors the note editor: attachment capture is native-only (Phase 1).
  bool get _attachmentsEnabled => !kIsWeb;

  @override
  void dispose() {
    _textCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Attachment picking / recording (parity with the note editor) ──────────

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

  // ── Smart Add submission ──────────────────────────────────────────────────

  void _submit() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    FocusScope.of(context).unfocus();

    // Hand the submission to the background controller (transcription +
    // classification run off-screen); the result surfaces as the shell's Smart
    // Add bar. Attachments are copied so resetting the form here can't mutate
    // the in-flight job.
    unawaited(context.read<SmartAddController>().start(SmartAddInput(
          text: text,
          attachments: List<PendingAttachment>.from(_attachments),
        )));
    _close();
  }

  // Closes the overlay: embedded in the swipe strip it resets the draft and
  // slides back to the calendar via [AddOverlay.onClose]; as a pushed route it
  // pops instead.
  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      _resetForm();
      onClose();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _resetForm() {
    if (!mounted) return;
    setState(() {
      _textCtrl.clear();
      _attachments.clear();
      _recording = false;
      _recordingPath = null;
    });
  }

  void _toast(String msg) {
    // Routed through the global messenger so it works across async gaps.
    scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: AppText.body(size: 13, color: Colors.white)),
        backgroundColor: AppColors.dark,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Row(
                children: [
                  MrIconButton(
                    icon: LucideIcons.x,
                    iconSize: 17,
                    onTap: _close,
                  ),
                  const Spacer(),
                  Text('新增',
                      style: AppText.display(size: 23, weight: FontWeight.w400)),
                  const Spacer(),
                  const SizedBox(width: 36),
                ],
              ),
            ),
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
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [kCardShadow],
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: TextField(
                        controller: _textCtrl,
                        maxLines: 8,
                        minLines: 5,
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
                                () => setState(() => _attachments.remove(a))),
                        ],
                      ),
                    ],
                    if (_recording) ...[
                      const SizedBox(height: 12),
                      _recordingBadge(),
                    ],
                  ],
                ),
              ),
            ),
            // Action bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _submit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: AppColors.dark,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.sparkles,
                                  size: 16, color: AppColors.amber),
                              const SizedBox(width: 8),
                              Text('智慧新增',
                                  style: AppText.body(
                                      size: 15,
                                      weight: FontWeight.w600,
                                      color: Colors.white)),
                            ],
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
                      icon: _recording ? LucideIcons.squareSlash : LucideIcons.mic,
                      iconColor: _recording ? AppColors.rose : null,
                      borderColor:
                          _recording ? AppColors.rose.withOpacity(0.4) : null,
                      onTap: _toggleRecording,
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
          Text('錄音中…', style: AppText.body(size: 13, color: AppColors.rose)),
        ],
      ),
    );
  }
}
