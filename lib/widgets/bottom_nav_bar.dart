import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';

class BottomNavBar extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.activeIndex,
    required this.onTap,
  });

  static const _tabs = [
    (icon: LucideIcons.calendar, label: '行事曆'),
    (icon: LucideIcons.squareCheck, label: '待辦'),
    (icon: LucideIcons.lightbulb, label: '靈感'),
    (icon: LucideIcons.fileText, label: '筆記'),
    (icon: LucideIcons.award, label: '回顧'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x38000000),
            blurRadius: 32,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_tabs.length, (i) {
          final tab = _tabs[i];
          final active = i == activeIndex;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: active ? AppColors.bg : Colors.transparent,
                borderRadius: BorderRadius.circular(26),
              ),
              constraints: const BoxConstraints(minWidth: 60),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.icon,
                    size: 18,
                    color: active ? AppColors.dark : Colors.white.withOpacity(0.38),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tab.label,
                    style: AppText.caption(
                      size: 10,
                      weight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? AppColors.dark : Colors.white.withOpacity(0.38),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
