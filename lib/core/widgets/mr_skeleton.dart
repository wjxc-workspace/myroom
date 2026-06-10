import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single shimmering placeholder bar, used to build loading skeletons while an
/// async result (AI enrichment, era insight) is pending (Phasing.md §Phase 3).
///
/// The shimmer is a self-contained looping gradient sweep — no external package.
class MrSkeletonBar extends StatefulWidget {
  const MrSkeletonBar({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.baseColor,
  });

  final double? width;
  final double height;
  final double radius;
  final Color? baseColor;

  @override
  State<MrSkeletonBar> createState() => _MrSkeletonBarState();
}

class _MrSkeletonBarState extends State<MrSkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? AppColors.border;
    final highlight = AppColors.mix(Colors.white, base, 0.6);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// A few stacked [MrSkeletonBar]s approximating a block of text (last line short).
class MrSkeletonLines extends StatelessWidget {
  const MrSkeletonLines({
    super.key,
    this.lines = 3,
    this.spacing = 8,
    this.height = 11,
    this.baseColor,
  });

  final int lines;
  final double spacing;
  final double height;
  final Color? baseColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          MrSkeletonBar(
            width: i == lines - 1 ? 140 : null,
            height: height,
            baseColor: baseColor,
          ),
        ],
      ],
    );
  }
}
