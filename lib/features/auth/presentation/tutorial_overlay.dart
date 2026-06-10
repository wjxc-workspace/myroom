import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';

/// Ported verbatim from the demo's `lib/overlays/tutorial_overlay.dart`.
/// Shown on first run when `settings/app.tutorialSeen` is false.
class TutorialOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const TutorialOverlay({super.key, required this.onDone});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _page = 0;
  late final AnimationController _fadeCtrl;
  late Animation<double> _fade;

  static const _pages = [
    _TutorialPage(
      title: 'Welcome to myroom',
      description:
          'Your personal space to capture everything that matters — tasks, ideas, notes, and more.',
      illustration: _IllustrationWelcome(),
    ),
    _TutorialPage(
      title: 'Add Anything You Want',
      description:
          "Press the '+' button to enter the 'add anything you want mode' — type freely and let the app figure out what it is.",
      illustration: _IllustrationAdd(),
    ),
    _TutorialPage(
      title: 'Explore Your Room',
      description:
          'Swipe between tabs to visit your Calendar, Todos, Ideas, Notes, and Recap pages.',
      illustration: _IllustrationNavBar(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _goTo(int idx) {
    _fadeCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _page = idx);
      _fadeCtrl.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFirst = _page == 0;
    final isLast = _page == _pages.length - 1;
    final page = _pages[_page];

    return Material(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x28000000),
                    blurRadius: 32,
                    offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 20 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _page ? AppColors.dark : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _fade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: page.illustration,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _fade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      page.title,
                      textAlign: TextAlign.center,
                      style: AppText.display(size: 24, weight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeTransition(
                  opacity: _fade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      page.description,
                      textAlign: TextAlign.center,
                      style: AppText.body(
                          size: 14, color: AppColors.muted, height: 1.55),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  child: Row(
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: isFirst ? 0 : 1,
                        child: _NavButton(
                          label: 'Previous',
                          icon: LucideIcons.chevronLeft,
                          onTap: isFirst ? null : () => _goTo(_page - 1),
                          filled: false,
                        ),
                      ),
                      const Spacer(),
                      _NavButton(
                        label: isLast ? 'Get Started' : 'Next',
                        icon: isLast ? LucideIcons.check : LucideIcons.chevronRight,
                        iconOnRight: true,
                        onTap: isLast ? widget.onDone : () => _goTo(_page + 1),
                        filled: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorialPage {
  final String title;
  final String description;
  final Widget illustration;
  const _TutorialPage(
      {required this.title,
      required this.description,
      required this.illustration});
}

class _NavButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool iconOnRight;
  final VoidCallback? onTap;
  final bool filled;

  const _NavButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconOnRight = false,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!iconOnRight) ...[Icon(icon, size: 15), const SizedBox(width: 5)],
        Text(label,
            style: AppText.body(
              size: 13,
              weight: FontWeight.w500,
              color: filled ? Colors.white : AppColors.dark,
            )),
        if (iconOnRight) ...[
          const SizedBox(width: 5),
          Icon(icon, size: 15, color: filled ? Colors.white : AppColors.dark)
        ],
      ],
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? AppColors.dark : Colors.transparent,
          border: filled ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );
  }
}

// ── Illustrations ────────────────────────────────────────────────────────────

class _IllustrationWelcome extends StatelessWidget {
  const _IllustrationWelcome();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      color: const Color(0xFFF0EBE0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(LucideIcons.house, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 14),
            Text('myroom',
                style: AppText.display(
                    size: 26, italic: true, weight: FontWeight.w400)),
            const SizedBox(height: 4),
            Text('your personal space', style: AppText.caption(size: 11)),
          ],
        ),
      ),
    );
  }
}

class _IllustrationAdd extends StatelessWidget {
  const _IllustrationAdd();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      color: const Color(0xFFF0EBE0),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 56,
              color: AppColors.bg,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.dark.withOpacity(0.45),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child:
                        const Icon(LucideIcons.plus, color: Colors.white, size: 18),
                  ),
                  const Spacer(),
                  Text('myroom',
                      style: AppText.display(
                          size: 18, italic: true, weight: FontWeight.w400)),
                  const Spacer(),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(LucideIcons.search, size: 14, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 62,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.cornerLeftUp, size: 20, color: AppColors.amber),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Tap here!",
                    style: AppText.body(
                        size: 12, color: Colors.white, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 72,
            left: 80,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                3,
                (i) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  height: 8,
                  width: double.infinity - i * 30,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IllustrationNavBar extends StatelessWidget {
  const _IllustrationNavBar();

  static const _tabs = [
    (LucideIcons.calendar, 'Cal'),
    (LucideIcons.squareCheck, 'Todo'),
    (LucideIcons.lightbulb, 'Ideas'),
    (LucideIcons.fileText, 'Notes'),
    (LucideIcons.award, 'Recap'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      color: const Color(0xFFF0EBE0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.pointer, size: 28, color: AppColors.muted),
                  const SizedBox(height: 8),
                  Text('Click to navigate',
                      style: AppText.body(size: 13, color: AppColors.muted)),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabs.length, (i) {
                final (icon, label) = _tabs[i];
                final active = i == 0;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: active
                      ? BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        )
                      : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 14,
                          color: active ? Colors.white : Colors.white38),
                      const SizedBox(height: 2),
                      Text(label,
                          style: AppText.caption(
                              size: 9,
                              color: active ? Colors.white : Colors.white38)),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
