import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
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

  bool _classifying = false;
  bool _recording = false;
  String? _summaryLabel;
  List<String> _suggested = [];

  // Keyword preview map (instant, before AI confirms)
  static const _catKW = {
    '行程': ['會議', '約', '早上', '上午', '下午', '晚上', '今天', '明天', '預約', '安排', '點開'],
    '待辦': ['要', '需要', '記得', '買', '完成', '處理', '幫', '提醒', '做', '去'],
    '靈感': ['如果', '想法', '或許', '試', '發現', '感覺', '有趣'],
    '日記': ['上週', '上禮拜', '昨天', '今天', '感受', '可愛', '開心', '煩', '無聊', '覺得', '想到', '看到']
  };

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _textCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (text.length <= 4) {
      setState(() => _suggested = []);
      return;
    }
    final matches = _catKW.entries
        .where((e) => e.value.any((kw) => text.contains(kw)))
        .map((e) => e.key)
        .toList();
    setState(() => _suggested = matches.isEmpty ? [] : matches);
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

    final newAttachments = <_Attachment>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final ext = (file.extension ?? '').toLowerCase();
      final name = file.name;

      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        newAttachments.add(_Attachment(type: _AttachType.image, name: name, bytes: bytes));
      } else if (['mp3', 'm4a', 'wav', 'ogg'].contains(ext)) {
        newAttachments.add(_Attachment(type: _AttachType.audio, name: name, bytes: bytes));
      } else if (['txt', 'md'].contains(ext)) {
        final text = utf8.decode(bytes, allowMalformed: true);
        newAttachments.add(_Attachment(type: _AttachType.textFile, name: name, bytes: bytes, preExtractedText: text));
      } else if (ext == 'pdf') {
        final extracted = await _extractPdfText(bytes, name);
        newAttachments.add(_Attachment(type: _AttachType.textFile, name: name, bytes: bytes, preExtractedText: extracted));
      }
    }

    if (newAttachments.isNotEmpty && mounted) {
      setState(() => _attachments.addAll(newAttachments));
    }
  }

  Future<String> _extractPdfText(Uint8List bytes, String name) async {
    try {
      final doc = await PdfDocument.openData(bytes);
      final buf = StringBuffer();
      for (int i = 1; i <= doc.pages.length; i++) {
        final page = doc.pages[i - 1];
        final text = await page.loadText();
        buf.write(text.fullText);
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
    // Request mic permission on mobile; desktop doesn't need it
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;
    }

    final path = '${Directory.systemTemp.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
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
      setState(() => _attachments.add(
        _Attachment(type: _AttachType.audio, name: 'recording.m4a', bytes: Uint8List.fromList(bytes)),
      ));
    }
  }

  // ── Process & save ───────────────────────────────────────────────────────────

  Future<void> _processAndSave() async {
    final hasText = _textCtrl.text.trim().isNotEmpty;
    final hasAttachments = _attachments.isNotEmpty;
    if (_classifying || (!hasText && !hasAttachments)) return;

    setState(() { _classifying = true; _summaryLabel = null; });

    // 1. Transcribe audio attachments in parallel
    final audioAttachments = _attachments.where((a) => a.type == _AttachType.audio).toList();
    final transcripts = await Future.wait(
      audioAttachments.map((a) => OpenAIService.instance.transcribeAudio(a.bytes, a.name)),
    );

    // 2. Collect file texts
    final fileTexts = _attachments
        .where((a) => a.type == _AttachType.textFile)
        .map((a) => '[檔案：${a.name}]\n${a.preExtractedText ?? ''}')
        .toList();

    // 3. Build combined text
    final parts = [
      _textCtrl.text.trim(),
      ...transcripts.whereType<String>().map((t) => '[音訊] $t'),
      ...fileTexts,
    ].where((s) => s.isNotEmpty).toList();
    final finalText = parts.join('\n\n');

    // 4. Encode image attachments as base64
    final base64Images = _attachments
        .where((a) => a.type == _AttachType.image)
        .map((a) => base64Encode(a.bytes))
        .toList();

    // 5. Call multi-item classification
    final results = await OpenAIService.instance.classifyMultiInput(
      finalText.isNotEmpty ? finalText : null,
      base64Images: base64Images,
    );

    if (!mounted) return;

    // 6. Fire callback for each result
    for (final r in results) {
      widget.onItemClassified(r);
    }

    // 7. Build summary chip
    final summary = _buildSummary(results);
    setState(() { _classifying = false; _summaryLabel = summary; });

    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) _close();
  }

  String _buildSummary(List<ClassificationResult> results) {
    if (results.isEmpty) return '✓ 已儲存';
    final hasError = results.any((r) => r is ClassificationError);
    if (hasError && results.length == 1) return '⚠ 無法分析，已儲存為筆記';

    int todos = 0, events = 0, ideas = 0, notes = 0, recaps = 0;
    for (final r in results) {
      if (r is ClassifiedTodo) todos++;
      if (r is ClassifiedTodoWithTime) events++;
      if (r is ClassifiedIdea) ideas++;
      if (r is ClassifiedNote) notes++;
      if (r is ClassifiedRecap) recaps++;
    }

    final parts = <String>[];
    if (events > 0) parts.add('$events 行程');
    if (todos > 0) parts.add('$todos 待辦');
    if (ideas > 0) parts.add('$ideas 靈感');
    if (notes > 0) parts.add('$notes 筆記');
    if (recaps > 0) parts.add('$recaps 回顧');
    return '✓ 新增 ${parts.join('、')}';
  }

  void _close() {
    _ctrl.reverse().then((_) => widget.onClose());
  }

  // ── UI ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                        Text('新增', style: AppText.display(size: 28, weight: FontWeight.w500, italic: true)),
                        Text('輸入任何想記錄的東西', style: AppText.label(size: 12)),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _close,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(LucideIcons.x, size: 16, color: AppColors.dark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Text area + attachment strip ─────────────────────────────
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 20, offset: Offset(0, 4))],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textCtrl,
                            maxLines: null,
                            expands: true,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: '輸入任何東西...\n\n今天想到、看到、計畫的——都可以放這裡',
                              hintStyle: AppText.body(color: AppColors.muted, height: 1.7),
                              border: InputBorder.none,
                            ),
                            style: AppText.body(size: 15, height: 1.7),
                            onChanged: _onTextChanged,
                          ),
                        ),

                        // Attachment strip
                        if (_attachments.isNotEmpty) ...[
                          const Divider(height: 20),
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _attachments.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) => _AttachChip(
                                attachment: _attachments[i],
                                onRemove: () => setState(() => _attachments.removeAt(i)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Keyword preview badges ───────────────────────────────────
                if (_suggested.isNotEmpty && !_classifying && _summaryLabel == null) ...[
                  const SizedBox(height: 14),
                  Text('預測分類', style: AppText.caption(size: 11, letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: _suggested.map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(14)),
                      child: Text(s, style: AppText.body(size: 13, weight: FontWeight.w500, color: AppColors.dark)),
                    )).toList(),
                  ),
                ],

                // ── Recording indicator ──────────────────────────────────────
                if (_recording) ...[
                  const SizedBox(height: 14),
                  _RecordingBadge(),
                ],

                // ── Result summary chip ──────────────────────────────────────
                if (_summaryLabel != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _summaryLabel!.startsWith('⚠')
                          ? AppColors.amber.withOpacity(0.12)
                          : AppColors.sage.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _summaryLabel!,
                      style: AppText.body(
                        size: 13,
                        color: _summaryLabel!.startsWith('⚠') ? AppColors.amber : AppColors.sage,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Action row ───────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _classifying ? null : _processAndSave,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _classifying ? AppColors.dark.withOpacity(0.5) : AppColors.dark,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: _classifying
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text('儲存並分類',
                                    style: AppText.body(size: 14, weight: FontWeight.w600, color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Upload / file picker button
                    _ActionBtn(
                      icon: LucideIcons.paperclip,
                      onTap: _classifying ? null : _pickFile,
                    ),
                    const SizedBox(width: 10),

                    // Mic / stop button
                    _ActionBtn(
                      icon: _recording ? LucideIcons.squareSlash : LucideIcons.mic,
                      iconColor: _recording ? AppColors.rose : null,
                      borderColor: _recording ? AppColors.rose.withOpacity(0.4) : null,
                      onTap: _classifying ? null : _toggleRecording,
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
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _AttachChip extends StatelessWidget {
  final _Attachment attachment;
  final VoidCallback onRemove;
  const _AttachChip({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final icon = switch (attachment.type) {
      _AttachType.image    => LucideIcons.image,
      _AttachType.audio    => LucideIcons.music,
      _AttachType.textFile => LucideIcons.fileText,
    };
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
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(
              attachment.name,
              style: AppText.caption(size: 11, color: AppColors.dark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(LucideIcons.x, size: 11, color: AppColors.muted),
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
            width: 7, height: 7,
            decoration: const BoxDecoration(color: AppColors.rose, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('錄音中…', style: AppText.body(size: 13, color: AppColors.rose)),
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
  const _ActionBtn({required this.icon, this.onTap, this.iconColor, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor ?? AppColors.border),
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
        ),
        child: Icon(icon, size: 20, color: iconColor ?? AppColors.muted),
      ),
    );
  }
}
