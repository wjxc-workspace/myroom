import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_repo.dart';

class MonthlyPage extends StatefulWidget {
  const MonthlyPage({super.key});

  @override
  State<MonthlyPage> createState() => _MonthlyPageState();
}

class _MonthlyPageState extends State<MonthlyPage> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  String get _monthPrefix => '${_month.year}-${fmt2(_month.month)}';

  bool get _canGoNext {
    final now = DateTime.now();
    return _month.year < now.year ||
        (_month.year == now.year && _month.month < now.month);
  }

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));

  void _nextMonth() {
    if (!_canGoNext) return;
    setState(() => _month = DateTime(_month.year, _month.month + 1));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Note>>(
      stream: context.read<NoteRepo>().watchNotes(),
      builder: (context, snap) {
        final allNotes = snap.data ?? [];
        final monthNotes = allNotes
            .where((n) => n.dateKey.startsWith(_monthPrefix))
            .toList();

        final Map<String, List<Note>> grouped = {};
        for (final n in monthNotes) {
          grouped.putIfAbsent(n.dateKey, () => []).add(n);
        }
        final sortedDays = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          children: [
            Text(
              '看看你這一個月的生活紀實...',
              style: AppText.body(size: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            _buildMonthNav(monthNotes.length),
            const SizedBox(height: 24),
            if (!snap.hasData)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (sortedDays.isEmpty)
              _buildEmpty()
            else
              ...sortedDays.map(
                (dk) => _DaySection(dateKey: dk, notes: grouped[dk]!),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMonthNav(int count) {
    return Row(
      children: [
        _NavArrow(icon: LucideIcons.chevronLeft, onTap: _prevMonth),
        Expanded(
          child: Column(
            children: [
              Text(
                '${_month.year}年${_month.month}月',
                style: AppText.body(size: 16, weight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                '$count 則記錄',
                style: AppText.caption(size: 11, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        _NavArrow(
          icon: LucideIcons.chevronRight,
          onTap: _canGoNext ? _nextMonth : null,
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Center(
        child: Column(
          children: [
            const Icon(LucideIcons.bookOpen, size: 38, color: AppColors.border),
            const SizedBox(height: 14),
            Text(
              '這個月還沒有任何記錄',
              style: AppText.body(size: 14, color: AppColors.muted),
            ),
            const SizedBox(height: 5),
            Text(
              '用「+ 隨手記」記下你的生活吧',
              style: AppText.caption(size: 12, color: AppColors.border),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NavArrow({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppColors.dark.withOpacity(0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? AppColors.dark : AppColors.border,
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  final String dateKey;
  final List<Note> notes;

  const _DaySection({required this.dateKey, required this.notes});

  String _formatDay() {
    final parts = dateKey.split('-');
    if (parts.length < 3) return dateKey;
    final year = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    final dt = DateTime(year, month, day);
    final dow = kDow[dt.weekday % 7];
    return '${month}月${day}日 · 星期$dow';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            _formatDay(),
            style: AppText.caption(
              size: 11,
              weight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        ...notes.map((n) => _NoteCard(note: n)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;

  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final hasTitle = note.title.isNotEmpty && note.title != '無標題';
    final hasContent = note.content.isNotEmpty;
    final hasCat = note.category.id != kUndefinedCategoryId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTitle || hasCat)
            Row(
              children: [
                if (hasTitle)
                  Expanded(
                    child: Text(
                      note.title,
                      style:
                          AppText.body(size: 13, weight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (!hasTitle) const Spacer(),
                if (hasCat) ...[
                  const SizedBox(width: 8),
                  _CategoryBadge(category: note.category),
                ],
              ],
            ),
          if ((hasTitle || hasCat) && hasContent) const SizedBox(height: 5),
          if (hasContent)
            Text(
              note.content,
              style: AppText.body(
                size: 13,
                color: hasTitle ? AppColors.muted : AppColors.dark,
                height: 1.55,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          if (!hasTitle && !hasContent && !hasCat)
            Text(
              '（空白記錄）',
              style: AppText.body(size: 13, color: AppColors.border),
            ),
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final NoteCategoryRef category;

  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: category.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        category.label,
        style: AppText.caption(
          size: 10,
          weight: FontWeight.w600,
          color: category.color,
        ),
      ),
    );
  }
}
