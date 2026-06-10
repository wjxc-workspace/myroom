import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mr_icon_button.dart';
import '../../../shared/auth/domain/app_user.dart';
import '../../../shared/auth/domain/auth_repo.dart';
import '../domain/app_settings.dart';
import '../domain/settings_repo.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _introCtrl = TextEditingController();
  final _instCtrl = TextEditingController();
  bool _hydrated = false;
  bool _autoEnrich = true;

  @override
  void dispose() {
    _introCtrl.dispose();
    _instCtrl.dispose();
    super.dispose();
  }

  /// Fill the form from the first real settings snapshot.
  void _hydrate(AppSettings s) {
    if (_hydrated) return;
    _hydrated = true;
    _introCtrl.text = s.selfIntro;
    _instCtrl.text = s.rules;
    _autoEnrich = s.autoEnrich;
  }

  Future<void> _save() async {
    await context.read<SettingsRepo>().updateSettings(
          selfIntro: _introCtrl.text.trim(),
          rules: _instCtrl.text.trim(),
          autoEnrich: _autoEnrich,
        );
  }

  Future<void> _saveAndPop() async {
    await _save();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _logout() async {
    await context.read<AuthRepo>().signOut();
    // authState → null triggers the redirect to /login.
  }

  Future<void> _confirmDelete() async {
    final user = context.read<AppUser>();
    final auth = context.read<AuthRepo>();
    final isPassword = user.email.isNotEmpty;
    final pwCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('刪除帳號', style: AppText.display(size: 22)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此動作無法復原，所有資料將被永久刪除。',
                style: AppText.body(size: 13, color: AppColors.muted)),
            if (isPassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: pwCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '輸入密碼以確認',
                  hintStyle: AppText.body(size: 13, color: AppColors.muted),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: AppText.body(size: 14),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: AppText.body(size: 14, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('刪除',
                style: AppText.body(
                    size: 14, weight: FontWeight.w700, color: AppColors.rose)),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      pwCtrl.dispose();
      return;
    }
    await auth.deleteAccount(password: isPassword ? pwCtrl.text : null);
    pwCtrl.dispose();
    // On success, authState → null and the redirect lands on /login.
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings?>();
    if (settings != null) _hydrate(settings);
    final email = context.watch<AppUser>().email;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    Text('myroom',
                        style: AppText.display(
                            size: 23, weight: FontWeight.w400, italic: true)),
                    const Spacer(),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
              if (!_hydrated)
                const Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.dark),
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
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              color: AppColors.dark,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.user,
                                size: 30, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text('設定',
                              style: AppText.display(
                                  size: 26, weight: FontWeight.w500)),
                        ),
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Center(child: Text(email, style: AppText.caption(size: 11))),
                        ],
                        const SizedBox(height: 28),
                        const _SectionLabel(label: '關於我', icon: LucideIcons.user),
                        const SizedBox(height: 8),
                        _FieldCard(
                          controller: _introCtrl,
                          hint:
                              '介紹自己，讓 AI 更了解你...\n例如：我是大學生，主修資工，喜歡閱讀和健身。',
                        ),
                        const SizedBox(height: 8),
                        Text('AI 聊天時會將此資訊納入背景，提供更個人化的回覆。',
                            style: AppText.caption(size: 11)),
                        const SizedBox(height: 24),
                        const _SectionLabel(
                            label: 'AI 回覆指示', icon: LucideIcons.sparkles),
                        const SizedBox(height: 8),
                        _FieldCard(
                          controller: _instCtrl,
                          hint:
                              '告訴 AI 你希望的回覆風格...\n例如：請用輕鬆語氣、每次附上具體行動建議。',
                        ),
                        const SizedBox(height: 8),
                        Text('非必填。留白則使用預設的簡潔友善語氣。',
                            style: AppText.caption(size: 11)),
                        const SizedBox(height: 24),
                        const _SectionLabel(label: 'AI 功能', icon: LucideIcons.bot),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                            boxShadow: const [kCardShadow],
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('自動分析靈感',
                                        style: AppText.body(
                                            size: 14, weight: FontWeight.w500)),
                                    const SizedBox(height: 2),
                                    Text('在靈感頁面，AI 將自動補充想法的細節與延伸。',
                                        style: AppText.caption(size: 11)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _autoEnrich,
                                onChanged: (v) => setState(() => _autoEnrich = v),
                                activeColor: AppColors.dark,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                        GestureDetector(
                          onTap: _saveAndPop,
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.dark,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text('儲存',
                                  style: AppText.body(
                                      size: 15,
                                      weight: FontWeight.w600,
                                      color: Colors.white)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Divider(color: AppColors.border),
                        const SizedBox(height: 12),
                        _DangerRow(
                          icon: LucideIcons.logOut,
                          label: '登出',
                          color: AppColors.dark,
                          onTap: _logout,
                        ),
                        const SizedBox(height: 8),
                        _DangerRow(
                          icon: LucideIcons.trash2,
                          label: '刪除帳號',
                          color: AppColors.rose,
                          onTap: _confirmDelete,
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
        Text(label,
            style: AppText.body(
                size: 13, weight: FontWeight.w600, color: AppColors.muted)),
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

class _DangerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DangerRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(label,
                style: AppText.body(size: 14, weight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }
}
