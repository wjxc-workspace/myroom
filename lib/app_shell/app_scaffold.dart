import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/date_format.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/bottom_nav_bar.dart';
import '../core/widgets/mr_icon_button.dart';
import '../features/auth/presentation/tutorial_overlay.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/domain/settings_repo.dart';
import '../router/routes.dart';

/// The StatefulShellRoute builder — owns the bottom-nav index (via the
/// [StatefulNavigationShell]) and renders the shared chrome (top bar + page
/// title) around the active tab. Also runs the one-time tz patch + first-run
/// tutorial gate.
class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  static const _pageTitles = ['行事曆', '待辦', '靈感', '札記', '時光軸'];

  bool _tzChecked = false;
  bool _tutorialDismissed = false;
  bool _navBarVisible = true;

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  /// Patch `settings/app.tz` to the device timezone once, after the first real
  /// settings snapshot arrives (Auth.md §3).
  Future<void> _maybePatchTimezone(AppSettings settings) async {
    if (_tzChecked) return;
    _tzChecked = true;
    try {
      final deviceTz = await FlutterTimezone.getLocalTimezone();
      if (deviceTz.isNotEmpty && deviceTz != settings.tz && mounted) {
        await context.read<SettingsRepo>().updateSettings(tz: deviceTz);
      }
    } catch (_) {
      // Device tz unavailable (e.g. unsupported platform) — keep the default.
    }
  }

  void _dismissTutorial() {
    setState(() => _tutorialDismissed = true);
    context.read<SettingsRepo>().updateSettings(tutorialSeen: true);
  }

  /// Flies the bottom nav bar out when the active tab is scrolled down and
  /// back in when it is scrolled up. Only the main vertical scroll counts;
  /// horizontal scrollers (the calendar pager, filter chips) are ignored.
  bool _handleNavBarScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.direction == ScrollDirection.reverse && _navBarVisible) {
      setState(() => _navBarVisible = false);
    } else if (notification.direction == ScrollDirection.forward &&
        !_navBarVisible) {
      setState(() => _navBarVisible = true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings?>();

    if (settings != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybePatchTimezone(settings);
      });
    }

    final showTutorial =
        settings != null && !settings.tutorialSeen && !_tutorialDismissed;

    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(context),
                _buildPageTitle(now),
                Expanded(
                  // A vertical scroll in the active tab flies the bottom nav
                  // bar out (scroll down) / back in (scroll up). The scroll
                  // notifications bubble up from the pages nested in the shell.
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: _handleNavBarScroll,
                    child: widget.navigationShell,
                  ),
                ),
              ],
            ),
            if (!showTutorial)
              Positioned(
                bottom: 22,
                left: 20,
                right: 20,
                // When hidden, slide the bar fully past the bottom edge; 2.5×
                // its height clears the safe-area inset on any device.
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  offset: _navBarVisible ? Offset.zero : const Offset(0, 2.5),
                  child: BottomNavBar(
                    activeIndex: widget.navigationShell.currentIndex,
                    onTap: _goBranch,
                  ),
                ),
              ),
            if (showTutorial) TutorialOverlay(onDone: _dismissTutorial),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push(Routes.add),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.plus,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 5),
                  Text('隨手記',
                      style: AppText.body(
                          size: 13,
                          weight: FontWeight.w600,
                          color: Colors.white)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text('myroom',
              style: AppText.display(size: 23, weight: FontWeight.w400, italic: true)),
          const Spacer(),
          Row(
            children: [
              MrIconButton(
                icon: LucideIcons.search,
                iconSize: 17,
                onTap: () => context.push(Routes.chat),
              ),
              const SizedBox(width: 7),
              MrIconButton(
                icon: LucideIcons.settings,
                iconSize: 16,
                onTap: () => context.push(Routes.settings),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageTitle(DateTime now) {
    final idx = widget.navigationShell.currentIndex;
    // Recap tab (idx 4) renders its own title row with the sub-page switcher.
    if (idx == 4) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_pageTitles[idx], style: AppText.display()),
          const SizedBox(height: 3),
          Text(
            '${now.year}年${now.month}月${now.day}日，星期${kDow[now.weekday % 7]}',
            style: AppText.caption(),
          ),
        ],
      ),
    );
  }
}
