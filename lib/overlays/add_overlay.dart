import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../services/openai_service.dart';

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
  List<String> _suggested = []; // instant keyword preview
  bool _classifying = false;
  String? _resultLabel; // e.g. "✓ 已新增到待辦"

  // Keyword preview map (instant, before AI confirms)
  static const _catKW = {
    '行程': ['會議', '約', '時間', '下午', '上午', '今天', '明天', '預約', '安排', '點開'],
    '待辦': ['要', '需要', '記得', '買', '完成', '處理', '幫', '提醒'],
    '靈感': ['如果', '想法', '或許', '可以試試', '發現', '感覺', '有趣'],
    '日記': ['今天', '感受', '心情', '覺得', '想到'],
    '學術': ['研究', '論文', '資料', '閱讀', '學習', '書'],
  };

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _fade =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
            .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _textCtrl.dispose();
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

  Future<void> _onSave() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _classifying) return;

    setState(() {
      _classifying = true;
      _resultLabel = null;
    });

    final result = await OpenAIService.instance.classifyInput(text);

    if (!mounted) return;

    // Determine label for feedback
    String label;
    if (result is ClassificationError) {
      label = '⚠ 無法分析，已儲存為筆記';
    } else if (result is ClassifiedTodo) {
      label = '✓ 已新增到待辦';
    } else if (result is ClassifiedTodoWithTime) {
      label = '✓ 已新增到待辦與行事曆';
    } else if (result is ClassifiedIdea) {
      label = '✓ 已新增到靈感';
    } else if (result is ClassifiedNote) {
      label = '✓ 已儲存到筆記';
    } else if (result is ClassifiedRecap) {
      label = '✓ 已新增到回顧';
    } else {
      label = '✓ 已儲存';
    }

    setState(() {
      _classifying = false;
      _resultLabel = label;
    });

    // Notify parent to persist + refresh
    widget.onItemClassified(result);

    // Brief pause to show the result chip, then close
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) _close();
  }

  void _close() {
    _ctrl.reverse().then((_) => widget.onClose());
  }

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
                // Header
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

                // Text area
                Expanded(
                  child: Container(
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
                ),

                // AI suggested preview (instant keyword badges)
                if (_suggested.isNotEmpty && !_classifying && _resultLabel == null) ...[
                  const SizedBox(height: 14),
                  Text('預測分類',
                      style: AppText.caption(size: 11, letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: _suggested
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(s,
                                  style: AppText.body(
                                      size: 13,
                                      weight: FontWeight.w500,
                                      color: AppColors.dark)),
                            ))
                        .toList(),
                  ),
                ],

                // Result label after classification
                if (_resultLabel != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _resultLabel!.startsWith('⚠')
                          ? AppColors.amber.withOpacity(0.12)
                          : AppColors.sage.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_resultLabel!,
                            style: AppText.body(
                                size: 13,
                                color: _resultLabel!.startsWith('⚠')
                                    ? AppColors.amber
                                    : AppColors.sage)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _classifying ? null : _onSave,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _classifying
                                ? AppColors.dark.withOpacity(0.5)
                                : AppColors.dark,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: _classifying
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text('儲存並分類',
                                    style: AppText.body(
                                        size: 14,
                                        weight: FontWeight.w600,
                                        color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _actionBtn(LucideIcons.upload),
                    const SizedBox(width: 10),
                    _actionBtn(LucideIcons.mic),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
      ),
      child: Icon(icon, size: 20, color: AppColors.muted),
    );
  }
}
