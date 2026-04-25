import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../data/seed_data.dart';
import '../models/recap_item.dart';

class RecapPage extends StatefulWidget {
  final ValueChanged<int> onNavTo;

  const RecapPage({super.key, required this.onNavTo});

  @override
  State<RecapPage> createState() => _RecapPageState();
}

class _RecapPageState extends State<RecapPage> {
  late int _focusedIdx;
  late ScrollController _leftCtrl;
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _focusedIdx = SeedData.timelineData.indexWhere((i) => i.id == 'n1');
    if (_focusedIdx < 0) _focusedIdx = 4;
    _leftCtrl = ScrollController();
    _leftCtrl.addListener(_onScroll);

    for (int i = 0; i < SeedData.timelineData.length; i++) {
      _itemKeys[i] = GlobalKey();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToItem(_focusedIdx, animate: false));
  }

  @override
  void dispose() {
    _leftCtrl.removeListener(_onScroll);
    _leftCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_leftCtrl.hasClients) return;
    final viewCenter = _leftCtrl.offset + _leftCtrl.position.viewportDimension / 2;
    int best = _focusedIdx;
    double bestDist = double.infinity;

    for (int i = 0; i < SeedData.timelineData.length; i++) {
      final key = _itemKeys[i];
      if (key == null) continue;
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final scrollableState = Scrollable.of(ctx);
      final scrollBox = scrollableState.context.findRenderObject() as RenderBox?;
      if (scrollBox == null) continue;
      final localPos = box.localToGlobal(Offset.zero, ancestor: scrollBox);
      final itemCenter = _leftCtrl.offset + localPos.dy + box.size.height / 2;
      final dist = (itemCenter - viewCenter).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    if (best != _focusedIdx) setState(() => _focusedIdx = best);
  }

  void _focusItem(int idx) {
    setState(() => _focusedIdx = idx);
    _scrollToItem(idx);
  }

  void _scrollToItem(int idx, {bool animate = true}) {
    final key = _itemKeys[idx];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = SeedData.timelineData;
    final focused = data[_focusedIdx];
    final eraColor = kEraColor[focused.era]!;

    return Row(
      children: [
        // Left timeline panel
        SizedBox(
          width: 130,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: _buildTimeline(data),
          ),
        ),

        // Right card panel
        Expanded(
          child: Column(
            children: [
              // Navigation counter
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _focusedIdx > 0 ? () => _focusItem(_focusedIdx - 1) : null,
                      child: Opacity(
                        opacity: _focusedIdx > 0 ? 1.0 : 0.3,
                        child: const Icon(LucideIcons.chevronUp, size: 18, color: AppColors.dark),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_focusedIdx + 1} / ${data.length}',
                      style: AppText.caption(size: 11, color: AppColors.muted),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _focusedIdx < data.length - 1 ? () => _focusItem(_focusedIdx + 1) : null,
                      child: Opacity(
                        opacity: _focusedIdx < data.length - 1 ? 1.0 : 0.3,
                        child: const Icon(LucideIcons.chevronDown, size: 18, color: AppColors.dark),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),

              // Big card with AnimatedSwitcher
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.05),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                          child: child,
                        ),
                      );
                    },
                    child: _BigCard(
                      key: ValueKey(_focusedIdx),
                      item: focused,
                      eraColor: eraColor,
                      onLinkClick: focused.noteLink != null
                          ? () => widget.onNavTo(focused.noteLink == 'note' ? 3 : 3)
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(List<RecapItem> data) {
    return ListView.builder(
      controller: _leftCtrl,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 120),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final item = data[i];
        final c = kEraColor[item.era]!;
        final active = i == _focusedIdx;
        final showEraHeader = i == 0 || data[i - 1].era != item.era;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showEraHeader)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 16, bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      kEraLabel[item.era]!.toUpperCase(),
                      style: AppText.caption(
                        size: 10,
                        weight: FontWeight.w700,
                        color: c,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),

            GestureDetector(
              key: _itemKeys[i],
              onTap: () => _focusItem(i),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dot + line
                  Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        width: active ? 13 : 7,
                        height: active ? 13 : 7,
                        decoration: BoxDecoration(
                          color: c.withOpacity(active ? 1 : 0.35),
                          shape: BoxShape.circle,
                          boxShadow: active
                              ? [BoxShadow(color: c.withOpacity(0.28), blurRadius: 0, spreadRadius: 3)]
                              : null,
                        ),
                      ),
                      Container(width: 1, height: 40, color: c.withOpacity(0.15)),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Label
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: active ? AppColors.mix(c, Colors.white, 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: AppText.caption(
                              size: 12,
                              weight: active ? FontWeight.w600 : FontWeight.w400,
                              color: AppColors.dark,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (active) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.displayDate,
                              style: AppText.caption(size: 10, color: c),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Big Card ─────────────────────────────────────────────────────────────────

class _BigCard extends StatelessWidget {
  final RecapItem item;
  final Color eraColor;
  final VoidCallback? onLinkClick;

  const _BigCard({super.key, required this.item, required this.eraColor, this.onLinkClick});

  @override
  Widget build(BuildContext context) {
    final c = eraColor;
    final eraBg = AppColors.mix(c, Colors.white, 0.15);
    final cardBorder = AppColors.mix(c, AppColors.border, 0.3);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder, width: 1.5),
        boxShadow: const [kCardShadow],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Era badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: eraBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(
                  kEraLabel[item.era]!.toUpperCase(),
                  style: AppText.caption(size: 10, weight: FontWeight.w700, color: c, letterSpacing: 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Title
          Text(item.title, style: AppText.display(size: 22, weight: FontWeight.w500)),
          const SizedBox(height: 6),

          // Date
          Text(
            item.displayDate,
            style: AppText.label(size: 12, weight: FontWeight.w600, color: c),
          ),
          const SizedBox(height: 14),

          // Photo placeholder
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: double.infinity,
              height: 120,
              child: Stack(
                children: [
                  CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: _DiagonalPainter(baseColor: AppColors.mix(c, const Color(0xFFF0ECE4), 0.1)),
                  ),
                  Center(
                    child: Icon(LucideIcons.image, size: 32, color: c.withOpacity(0.4)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Description
          Text(
            item.desc,
            style: AppText.label(size: 13, color: AppColors.muted).copyWith(height: 1.7),
          ),

          // Link button
          if (onLinkClick != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onLinkClick,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.mix(c, Colors.white, 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.link, size: 13, color: c),
                    const SizedBox(width: 6),
                    Text(
                      '跳轉到相關${item.noteLink == 'diary' ? '日記' : '筆記'}',
                      style: AppText.body(size: 13, color: c),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagonalPainter extends CustomPainter {
  final Color baseColor;
  const _DiagonalPainter({required this.baseColor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = baseColor);
    final paint = Paint()..color = Colors.white.withOpacity(0.07);
    final stripe = 16.0;
    for (double x = -size.height; x < size.width + size.height; x += stripe) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + stripe / 2, 0)
        ..lineTo(x + stripe / 2 + size.height, size.height)
        ..lineTo(x + size.height, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_DiagonalPainter old) => old.baseColor != baseColor;
}
