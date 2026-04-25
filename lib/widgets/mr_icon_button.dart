import 'package:flutter/material.dart';
import '../theme.dart';

class MrIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? bg;
  final Color? iconColor;
  final double borderRadius;
  final bool showBorder;
  final double iconSize;

  const MrIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 36,
    this.bg,
    this.iconColor,
    this.borderRadius = 12,
    this.showBorder = true,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg ?? Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          border: showBorder
              ? Border.all(color: AppColors.border, width: 1)
              : null,
        ),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor ?? AppColors.dark,
          ),
        ),
      ),
    );
  }
}
