import 'package:flutter/material.dart';
import '../theme.dart';

class MrCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? leftBorderColor;
  final Color? customBorderColor;
  final VoidCallback? onTap;
  final Color? bgColor;

  const MrCard({
    super.key,
    required this.child,
    this.padding,
    this.leftBorderColor,
    this.customBorderColor,
    this.onTap,
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = child;

    if (leftBorderColor != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: leftBorderColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: padding ?? const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: child,
            ),
          ),
        ],
      );
    }

    Widget card = Container(
      decoration: BoxDecoration(
        color: bgColor ?? AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: customBorderColor != null
            ? Border.all(color: customBorderColor!, width: 1.5)
            : null,
        boxShadow: const [kCardShadow],
      ),
      child: leftBorderColor != null
          ? content
          : Padding(
              padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: child,
            ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}
