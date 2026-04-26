import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../services/database_service.dart';
import '../widgets/mr_icon_button.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final _introCtrl = TextEditingController();
  final _instCtrl  = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await DatabaseService.instance.getUserProfile();
    if (!mounted) return;
    setState(() {
      _introCtrl.text = profile.selfIntro;
      _instCtrl.text  = profile.aiInstructions;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await DatabaseService.instance.saveUserProfile(
      _introCtrl.text.trim(),
      _instCtrl.text.trim(),
    );
  }

  void _saveAndPop() {
    _save().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _instCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _saveAndPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top bar ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                child: Row(
                  children: [
                    MrIconButton(
                      icon: LucideIcons.arrowLeft,
                      iconSize: 17,
                      onTap: _saveAndPop,
                    ),
                    const Spacer(),
                    Text(
                      'myroom',
                      style: AppText.display(size: 23, weight: FontWeight.w400, italic: true),
                    ),
                    const Spacer(),
                    const SizedBox(width: 36),
                  ],
                ),
              ),

              if (!_loaded)
                const Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark),
                    ),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Avatar ────────────────────────────────────────
                        Center(
                          child: Container(
                            width: 72, height: 72,
                            decoration: const BoxDecoration(
                              color: AppColors.dark,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.user, size: 30, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text('設定', style: AppText.display(size: 26, weight: FontWeight.w500)),
                        ),
                        const SizedBox(height: 28),

                        // ── Self intro ────────────────────────────────────
                        _SectionLabel(label: '關於我', icon: LucideIcons.user),
                        const SizedBox(height: 8),
                        _FieldCard(
                          controller: _introCtrl,
                          hint: '介紹自己，讓 AI 更了解你...\n例如：我是大學生，主修資工，喜歡閱讀和健身。',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI 聊天時會將此資訊納入背景，提供更個人化的回覆。',
                          style: AppText.caption(size: 11),
                        ),
                        const SizedBox(height: 24),

                        // ── AI instructions ───────────────────────────────
                        _SectionLabel(label: 'AI 回覆指示', icon: LucideIcons.sparkles),
                        const SizedBox(height: 8),
                        _FieldCard(
                          controller: _instCtrl,
                          hint: '告訴 AI 你希望的回覆風格...\n例如：請用輕鬆語氣、每次附上具體行動建議。',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '非必填。留白則使用預設的簡潔友善語氣。',
                          style: AppText.caption(size: 11),
                        ),
                        const SizedBox(height: 36),

                        // ── Save button ───────────────────────────────────
                        GestureDetector(
                          onTap: _saveAndPop,
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.dark,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                '儲存',
                                style: AppText.body(
                                  size: 15,
                                  weight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Text(label, style: AppText.body(size: 13, weight: FontWeight.w600, color: AppColors.muted)),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _FieldCard({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [kCardShadow],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: controller,
        maxLines: 5,
        minLines: 3,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.body(size: 13, color: AppColors.muted, height: 1.6),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: AppText.body(size: 14, height: 1.6),
      ),
    );
  }
}
