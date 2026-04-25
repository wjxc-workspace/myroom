import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../models/idea.dart';
import '../data/seed_data.dart';
import '../widgets/mr_card.dart';

enum IdeaSub { input, explore }

class IdeaPage extends StatefulWidget {
  final List<Idea> ideas;
  final ValueChanged<String> onIdeaAdded;

  const IdeaPage({super.key, required this.ideas, required this.onIdeaAdded});

  @override
  State<IdeaPage> createState() => _IdeaPageState();
}

class _IdeaPageState extends State<IdeaPage> {
  IdeaSub _sub = IdeaSub.input;
  final _draftCtrl = TextEditingController();

  @override
  void dispose() {
    _draftCtrl.dispose();
    super.dispose();
  }

  void _addIdea() {
    if (_draftCtrl.text.isEmpty) return;
    widget.onIdeaAdded(_draftCtrl.text);
    _draftCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sub-tab toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: IdeaSub.values.map((s) {
                final active = _sub == s;
                final labels = ['✦  記錄靈感', '⊹  探索資源'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _sub = s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? AppColors.dark : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          labels[s.index],
                          style: AppText.body(
                            size: 13,
                            weight: active ? FontWeight.w600 : FontWeight.w400,
                            color: active ? Colors.white : AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        Expanded(
          child: _sub == IdeaSub.input ? _buildInput() : _buildExplore(),
        ),
      ],
    );
  }

  Widget _buildInput() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // Idea cards
        ...widget.ideas.asMap().entries.map((entry) {
          final i = entry.key;
          final idea = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MrCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: AppText.body(size: 13, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(idea.text, style: AppText.body(size: 14, height: 1.55)),
                  ),
                ],
              ),
            ),
          );
        }),

        if (widget.ideas.isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(
            child: Icon(LucideIcons.chevronDown, size: 22, color: AppColors.dark.withOpacity(0.3)),
          ),
          const SizedBox(height: 10),

          // AI extraction box
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.sparkles, size: 14, color: AppColors.amber),
                    const SizedBox(width: 6),
                    Text(
                      'AI 核心洞察萃取',
                      style: AppText.caption(
                        size: 11,
                        weight: FontWeight.w600,
                        color: AppColors.amber,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                RichText(
                  text: TextSpan(
                    style: AppText.body(
                      size: 14,
                      color: Colors.white.withOpacity(0.88),
                      height: 1.7,
                    ).copyWith(fontStyle: FontStyle.italic),
                    children: [
                      const TextSpan(text: '「這些想法都指向'),
                      TextSpan(
                        text: '人性化介面',
                        style: TextStyle(
                          color: AppColors.amber,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.normal,
                        ),
                      ),
                      const TextSpan(text: '與'),
                      TextSpan(
                        text: '自動化輔助',
                        style: TextStyle(
                          color: AppColors.sage,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.normal,
                        ),
                      ),
                      const TextSpan(text: '的交叉點——你在探索如何讓科技更貼近人的思維節奏。」'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Input form
        MrCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextField(
                controller: _draftCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: '記下你的靈感...',
                  hintStyle: AppText.body(color: AppColors.muted),
                  border: InputBorder.none,
                ),
                style: AppText.body(size: 14, height: 1.55),
                onSubmitted: (_) => _addIdea(),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _addIdea,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.dark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('新增', style: AppText.body(size: 13, weight: FontWeight.w500, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExplore() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        Text('跨界推薦資源', style: AppText.display(size: 22, weight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('根據你的靈感主題，AI 為你找到的相關資源', style: AppText.label(size: 12)),
        const SizedBox(height: 16),
        ...kResources.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: MrCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: r.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.fileText, size: 22, color: r.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(r.title, style: AppText.body(size: 14, weight: FontWeight.w600))),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: r.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(r.type, style: AppText.caption(size: 10, color: r.color)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(r.desc, style: AppText.label(size: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )),
        const SizedBox(height: 4),
        Center(
          child: GestureDetector(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.refreshCw, size: 13, color: AppColors.muted),
                const SizedBox(width: 5),
                Text('重新推薦', style: AppText.label(size: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
