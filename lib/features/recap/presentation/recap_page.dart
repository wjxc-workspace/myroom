import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_errors.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mr_add_row.dart';
import '../../../core/widgets/mr_card.dart';
import '../../../core/widgets/mr_skeleton.dart';
import '../../../shared/ai/domain/ai_service.dart';
import '../../../shared/storage/storage_repo.dart';
import '../domain/achievement.dart';
import '../domain/achievement_repo.dart';
import '../domain/recap.dart';
import '../domain/recap_repo.dart';

/// Opens a server-rendered export (SVG) by resolving a fresh download URL.
Future<void> _openExport(BuildContext context, String storagePath) async {
  final url = await context.read<StorageRepo>().downloadUrl(storagePath);
  final uri = Uri.tryParse(url);
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Builds the dataSummary for `generateEraInsight` from existing text (or a
/// gentle fallback when the user hasn't written anything yet).
String _eraSummary(String label, String basis) =>
    basis.trim().isEmpty ? '（使用者尚未填寫$label的內容，請給予溫暖、具體的鼓勵）' : basis.trim();

/// Recap tab — renders body content only (the app shell supplies the top bar,
/// page title and bottom nav). Streams both `achievements` and `recaps`.
class RecapPage extends StatelessWidget {
  const RecapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        StreamProvider<List<Achievement>>(
          create: (c) => c.read<AchievementRepo>().watchAchievements(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <Achievement>[];
          },
        ),
        StreamProvider<List<Recap>>(
          create: (c) => c.read<RecapRepo>().watchRecaps(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <Recap>[];
          },
        ),
      ],
      child: const _RecapBody(),
    );
  }
}

class _RecapBody extends StatelessWidget {
  const _RecapBody();

  @override
  Widget build(BuildContext context) {
    final achievements = context.watch<List<Achievement>>();
    final recaps = context.watch<List<Recap>>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        // ── Achievements (era summaries) ────────────────────────────────
        const _SectionHeader(
          icon: LucideIcons.compass,
          title: '階段回顧',
          subtitle: '過去、現在與未來的軌跡',
        ),
        const SizedBox(height: 12),
        if (achievements.isEmpty)
          const _EmptyHint(
            icon: LucideIcons.compass,
            text: '還沒有任何階段回顧。\n新增一張卡片，記下你的過去、現在與未來。',
          )
        else
          ...achievements.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _AchievementCard(achievement: a),
              )),
        const SizedBox(height: 6),
        MrAddRow(
          label: '新增階段回顧',
          onTap: () => _addAchievement(context),
        ),

        const SizedBox(height: 30),

        // ── Recaps (titled reviews) ─────────────────────────────────────
        const _SectionHeader(
          icon: LucideIcons.bookOpen,
          title: '回顧紀錄',
          subtitle: '為一段時光寫下標題與回顧',
        ),
        const SizedBox(height: 12),
        if (recaps.isEmpty)
          const _EmptyHint(
            icon: LucideIcons.bookOpen,
            text: '還沒有任何回顧紀錄。\n為一段珍貴的時光寫下第一篇吧。',
          )
        else
          ...recaps.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RecapCard(recap: r),
              )),
        const SizedBox(height: 6),
        MrAddRow(
          label: '新增回顧',
          onTap: () => _addRecap(context),
        ),
      ],
    );
  }

  Future<void> _addAchievement(BuildContext context) async {
    await context.read<AchievementRepo>().add(
          Achievement(id: '', createdAt: DateTime.now()),
        );
    // Stream re-emits with the new doc.
  }

  Future<void> _addRecap(BuildContext context) async {
    final result = await _showRecapForm(context);
    if (result == null) return;
    if (!context.mounted) return;
    await context.read<RecapRepo>().add(
          Recap(
            id: '',
            title: result.title,
            content: result.content,
            createdAt: DateTime.now(),
          ),
        );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.muted),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: AppText.display(size: 20, weight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle, style: AppText.caption(size: 11)),
          ],
        ),
      ],
    );
  }
}

// ─── Empty hint ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.mix(AppColors.surface, AppColors.card, 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: AppColors.mix(AppColors.muted, Colors.white, 0.6)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.caption(size: 12, color: AppColors.muted)
                .copyWith(height: 1.7),
          ),
        ],
      ),
    );
  }
}

// ─── Achievement card (three editable era blocks) ─────────────────────────────

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;
  const _AchievementCard({required this.achievement});

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await _showConfirm(context, '刪除這張階段回顧？', '此動作無法復原。');
    if (ok != true || !context.mounted) return;
    await context.read<AchievementRepo>().delete(achievement.id);
  }

  @override
  Widget build(BuildContext context) {
    return MrCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.milestone, size: 14, color: AppColors.dark),
              const SizedBox(width: 7),
              Text('階段回顧',
                  style: AppText.body(
                      size: 14, weight: FontWeight.w600, color: AppColors.dark)),
              const Spacer(),
              GestureDetector(
                onTap: () => _confirmDelete(context),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(LucideIcons.trash2, size: 15, color: AppColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _EraBlock(
            label: '過去',
            sublabel: '成就回顧',
            accent: AppColors.amber,
            value: achievement.pastContent,
            hint: '回顧已經走過的路、完成的事…',
            achievementId: achievement.id,
            eraKey: 'past',
            exportPath: achievement.pastExportStoragePath,
            onSave: (text) => context.read<AchievementRepo>().update(
                  achievement.copyWith(pastContent: text),
                ),
          ),
          const SizedBox(height: 12),
          _EraBlock(
            label: '現在',
            sublabel: '此刻目標',
            accent: AppColors.sage,
            value: achievement.currentContent,
            hint: '此刻正在進行、想達成的事…',
            achievementId: achievement.id,
            eraKey: 'current',
            exportPath: achievement.currentExportStoragePath,
            onSave: (text) => context.read<AchievementRepo>().update(
                  achievement.copyWith(currentContent: text),
                ),
          ),
          const SizedBox(height: 12),
          _EraBlock(
            label: '未來',
            sublabel: '長遠願景',
            accent: AppColors.blue,
            value: achievement.futureContent,
            hint: '想前往的方向、長遠的願景…',
            achievementId: achievement.id,
            eraKey: 'future',
            exportPath: achievement.futureExportStoragePath,
            onSave: (text) => context.read<AchievementRepo>().update(
                  achievement.copyWith(futureContent: text),
                ),
          ),
        ],
      ),
    );
  }
}

/// One editable era text block. Tap to edit inline; saving fires [onSave].
/// AI generate (`generateEraInsight`) and export (`exportAchievement`) run via
/// the header buttons.
class _EraBlock extends StatefulWidget {
  final String label;
  final String sublabel;
  final Color accent;
  final String value;
  final String hint;
  final String achievementId;
  final String eraKey; // past | current | future
  final String? exportPath;
  final ValueChanged<String> onSave;

  const _EraBlock({
    required this.label,
    required this.sublabel,
    required this.accent,
    required this.value,
    required this.hint,
    required this.achievementId,
    required this.eraKey,
    required this.exportPath,
    required this.onSave,
  });

  @override
  State<_EraBlock> createState() => _EraBlockState();
}

class _EraBlockState extends State<_EraBlock> {
  bool _editing = false;
  bool _generating = false;
  bool _exporting = false;
  bool get _busy => _generating || _exporting;
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _EraBlock old) {
    super.didUpdateWidget(old);
    // Keep the controller in sync with stream updates while not editing.
    if (!_editing && old.value != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _startEdit() {
    _ctrl.text = widget.value;
    setState(() => _editing = true);
  }

  void _commit() {
    final text = _ctrl.text.trim();
    setState(() => _editing = false);
    if (text != widget.value) widget.onSave(text);
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _generating = true);
    final res = await context.read<AiService>().generateEraInsight(
          eraLabel: widget.label,
          dataSummary: _eraSummary(widget.label, widget.value),
        );
    if (!mounted) return;
    setState(() => _generating = false);
    if (res is Ok<String> && res.value.trim().isNotEmpty) {
      _ctrl.text = res.value;
      widget.onSave(res.value); // persists; stream refreshes value
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _exporting = true);
    final res = await context.read<AiService>().exportAchievement(
          achievementId: widget.achievementId,
          era: widget.eraKey,
        );
    if (!mounted) return;
    setState(() => _exporting = false);
    if (res is Ok<String>) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('匯出完成',
              style: AppText.body(size: 13, color: Colors.white)),
          backgroundColor: AppColors.dark,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.accent;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.mix(c, Colors.white, 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.18)),
      ),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(widget.label,
                  style: AppText.caption(
                      size: 12, weight: FontWeight.w700, color: c)),
              const SizedBox(width: 6),
              Text(widget.sublabel,
                  style: AppText.caption(size: 10, color: AppColors.muted)),
              const Spacer(),
              if (_busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c),
                )
              else ...[
                _HeaderBtn(
                  icon: LucideIcons.sparkles,
                  color: c,
                  onTap: _generate,
                ),
                _HeaderBtn(
                  icon: LucideIcons.download,
                  color: c,
                  onTap: _export,
                ),
                if (widget.exportPath != null)
                  _HeaderBtn(
                    icon: LucideIcons.externalLink,
                    color: c,
                    onTap: () => _openExport(context, widget.exportPath!),
                  ),
              ],
              GestureDetector(
                onTap: _editing ? _commit : _startEdit,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    _editing ? LucideIcons.check : LucideIcons.pencil,
                    size: 13,
                    color: c,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_generating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: MrSkeletonLines(lines: 3, height: 11),
            )
          else if (_editing)
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: null,
              minLines: 2,
              style: AppText.body(size: 13, height: 1.7),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle:
                    AppText.body(size: 13, color: AppColors.muted, height: 1.7),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _commit(),
            )
          else
            GestureDetector(
              onTap: _startEdit,
              behavior: HitTestBehavior.opaque,
              child: Text(
                widget.value.isEmpty ? widget.hint : widget.value,
                style: widget.value.isEmpty
                    ? AppText.body(size: 13, color: AppColors.muted, height: 1.7)
                    : AppText.body(size: 13, color: AppColors.dark, height: 1.7),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Header action button (era block + recap card) ───────────────────────────

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _HeaderBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 13, color: color.withOpacity(0.85)),
      ),
    );
  }
}

// ─── Recap card ───────────────────────────────────────────────────────────────

class _RecapCard extends StatefulWidget {
  final Recap recap;
  const _RecapCard({required this.recap});

  @override
  State<_RecapCard> createState() => _RecapCardState();
}

class _RecapCardState extends State<_RecapCard> {
  bool _generating = false;
  bool _exporting = false;
  bool get _busy => _generating || _exporting;

  Recap get recap => widget.recap;

  Future<void> _edit() async {
    final result = await _showRecapForm(
      context,
      initialTitle: recap.title,
      initialContent: recap.content,
    );
    if (result == null || !mounted) return;
    await context.read<RecapRepo>().update(
          Recap(
            id: recap.id,
            title: result.title,
            content: result.content,
            exportStoragePath: recap.exportStoragePath,
            createdAt: recap.createdAt,
          ),
        );
  }

  Future<void> _confirmDelete() async {
    final ok = await _showConfirm(context, '刪除這篇回顧？', '此動作無法復原。');
    if (ok != true || !mounted) return;
    await context.read<RecapRepo>().delete(recap.id);
  }

  Future<void> _generate() async {
    if (_busy) return;
    final label = recap.title.trim().isEmpty ? 'recap' : recap.title.trim();
    setState(() => _generating = true);
    final res = await context.read<AiService>().generateEraInsight(
          eraLabel: label,
          dataSummary: _eraSummary('這篇回顧', recap.content),
        );
    if (!mounted) return;
    setState(() => _generating = false);
    if (res is Ok<String> && res.value.trim().isNotEmpty) {
      await context.read<RecapRepo>().update(
            Recap(
              id: recap.id,
              title: recap.title,
              content: res.value,
              exportStoragePath: recap.exportStoragePath,
              createdAt: recap.createdAt,
            ),
          );
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _exporting = true);
    final res = await context.read<AiService>().exportRecap(recap.id);
    if (!mounted) return;
    setState(() => _exporting = false);
    if (res is Ok<String>) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('匯出完成',
              style: AppText.body(size: 13, color: Colors.white)),
          backgroundColor: AppColors.dark,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MrCard(
      leftBorderColor: AppColors.rose,
      onTap: _edit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  recap.title.isEmpty ? '無標題' : recap.title,
                  style: AppText.body(
                      size: 15, weight: FontWeight.w600, color: AppColors.dark),
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(left: 8, top: 1),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.muted),
                  ),
                )
              else ...[
                _HeaderBtn(
                  icon: LucideIcons.sparkles,
                  color: AppColors.rose,
                  onTap: _generate,
                ),
                _HeaderBtn(
                  icon: LucideIcons.download,
                  color: AppColors.muted,
                  onTap: _export,
                ),
                if (recap.exportStoragePath != null)
                  _HeaderBtn(
                    icon: LucideIcons.externalLink,
                    color: AppColors.muted,
                    onTap: () => _openExport(context, recap.exportStoragePath!),
                  ),
                _HeaderBtn(
                  icon: LucideIcons.trash2,
                  color: AppColors.muted,
                  onTap: _confirmDelete,
                ),
              ],
            ],
          ),
          if (_generating) ...[
            const SizedBox(height: 9),
            const MrSkeletonLines(lines: 2, height: 11),
          ] else if (recap.content.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              recap.content,
              style: AppText.body(size: 13, color: AppColors.muted, height: 1.65),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Recap create/edit form ───────────────────────────────────────────────────

class _RecapFormResult {
  final String title;
  final String content;
  const _RecapFormResult(this.title, this.content);
}

Future<_RecapFormResult?> _showRecapForm(
  BuildContext context, {
  String initialTitle = '',
  String initialContent = '',
}) {
  final titleCtrl = TextEditingController(text: initialTitle);
  final contentCtrl = TextEditingController(text: initialContent);

  return showModalBottomSheet<_RecapFormResult>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              initialTitle.isEmpty && initialContent.isEmpty ? '新增回顧' : '編輯回顧',
              style: AppText.display(size: 22, weight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            _SheetField(
              controller: titleCtrl,
              hint: '標題，例如：充滿喜悅的六月',
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            _SheetField(
              controller: contentCtrl,
              hint: '寫下這段時光的回顧…',
              maxLines: 6,
              minLines: 4,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  Navigator.of(ctx).pop();
                  return;
                }
                Navigator.of(ctx).pop(
                  _RecapFormResult(title, contentCtrl.text.trim()),
                );
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.dark,
                  borderRadius: BorderRadius.circular(14),
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
          ],
        ),
      );
    },
  ).whenComplete(() {
    titleCtrl.dispose();
    contentCtrl.dispose();
  });
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? minLines;
  const _SheetField({
    required this.controller,
    required this.hint,
    required this.maxLines,
    this.minLines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: minLines,
        style: AppText.body(size: 14, height: 1.6),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.body(size: 14, color: AppColors.muted, height: 1.6),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

// ─── Confirm dialog ───────────────────────────────────────────────────────────

Future<bool?> _showConfirm(BuildContext context, String title, String body) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: AppText.display(size: 20)),
      content: Text(body, style: AppText.body(size: 13, color: AppColors.muted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child:
              Text('取消', style: AppText.body(size: 14, color: AppColors.muted)),
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
}
