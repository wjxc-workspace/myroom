import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../data/seed_data.dart';
import '../widgets/mr_card.dart';
import '../widgets/mr_icon_button.dart';

enum NoteMode { date, category }

class NotePage extends StatefulWidget {
  final Map<String, String> notes;
  final void Function(String dateKey, String content) onNoteSaved;

  const NotePage({super.key, required this.notes, required this.onNoteSaved});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  NoteMode _mode = NoteMode.date;
  int _year = 2026;
  int _month = 3;
  int? _selectedDay;
  String? _openCat;

  String get _noteKey {
    final d = _selectedDay;
    if (d == null) return '';
    return '$_year-${fmt2(_month + 1)}-${fmt2(d)}';
  }

  void _saveNote(String text) {
    widget.onNoteSaved(_noteKey, text);
  }

  @override
  Widget build(BuildContext context) {
    if (_openCat != null) {
      return _CatDetail(
        catId: _openCat!,
        onBack: () => setState(() => _openCat = null),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: NoteMode.values.map((m) {
                final active = _mode == m;
                final labels = ['日期', '分類'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _mode = m;
                      _selectedDay = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? AppColors.dark : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          labels[m.index],
                          style: AppText.body(
                            size: 13,
                            weight: active ? FontWeight.w600 : FontWeight.w400,
                            color: active ? Colors.white : AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: _mode == NoteMode.date ? _buildDateMode() : _buildCategoryMode(),
        ),
      ],
    );
  }

  Widget _buildDateMode() {
    final daysInMonth = DateTime(_year, _month + 2, 0).day;
    final firstDow = DateTime(_year, _month + 1, 1).weekday % 7;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // Month nav
        Row(
          children: [
            Text(
              '$_year年${kMonthNames[_month]}',
              style: AppText.display(size: 22, weight: FontWeight.w500),
            ),
            const Spacer(),
            MrIconButton(
              icon: LucideIcons.chevronLeft,
              iconSize: 15,
              onTap: () => setState(() {
                if (_month > 0) _month--;
                _selectedDay = null;
              }),
            ),
            const SizedBox(width: 6),
            MrIconButton(
              icon: LucideIcons.chevronRight,
              iconSize: 15,
              onTap: () => setState(() {
                if (_month < 11) _month++;
                _selectedDay = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Day-of-week header
        Row(
          children: kDow.map((d) => Expanded(
            child: Center(
              child: Text(d, style: AppText.caption(size: 10, weight: FontWeight.w600)),
            ),
          )).toList(),
        ),
        const SizedBox(height: 4),

        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 42,
          ),
          itemCount: ((firstDow + daysInMonth) / 7).ceil() * 7,
          itemBuilder: (_, idx) {
            final day = idx - firstDow + 1;
            if (day < 1 || day > daysInMonth) return const SizedBox();
            final key = '$_year-${fmt2(_month + 1)}-${fmt2(day)}';
            final hasNote = widget.notes.containsKey(key);
            final isSelected = _selectedDay == day;
            final isToday = _year == 2026 && _month == 3 && day == 24;
            final isPast = _year == 2026 && _month == 3 && day < 24;

            return GestureDetector(
              onTap: () => setState(() => _selectedDay = isSelected ? null : day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.dark
                      : isToday
                          ? AppColors.dark.withOpacity(0.08)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: AppText.body(
                        size: 13,
                        weight: FontWeight.w400,
                        color: isSelected
                            ? Colors.white
                            : isPast
                                ? AppColors.muted
                                : AppColors.dark,
                      ),
                    ),
                    if (hasNote)
                      Container(
                        width: 4, height: 4,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: const BoxDecoration(
                          color: AppColors.rose,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        // Note editor
        if (_selectedDay != null) ...[
          const SizedBox(height: 16),
          MrCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${_month + 1}月${_selectedDay}日 $_year',
                      style: AppText.body(size: 13, weight: FontWeight.w500),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _selectedDay = null),
                      child: const Icon(LucideIcons.x, size: 16, color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _NoteEditor(
                  key: ValueKey(_noteKey),
                  initialText: widget.notes[_noteKey] ?? '',
                  onChanged: _saveNote,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryMode() {
    final cats = [
      _CatInfo(id: 'undefined', label: '未分類', icon: LucideIcons.tag, color: AppColors.muted, bg: const Color(0xFFF5F0E8)),
      _CatInfo(id: 'training', label: '練習', icon: LucideIcons.star, color: AppColors.sage, bg: const Color(0xFFEFF5F1)),
      _CatInfo(id: 'diary', label: '日記', icon: LucideIcons.pencil, color: AppColors.rose, bg: const Color(0xFFF5EEF0)),
      _CatInfo(id: 'academic', label: '學術', icon: LucideIcons.fileText, color: AppColors.blue, bg: const Color(0xFFEEF0F5)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        ...cats.map((c) => GestureDetector(
          onTap: () => setState(() => _openCat = c.id),
          child: Container(
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [kCardShadow],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: c.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(c.icon, size: 18, color: c.color),
                ),
                const Spacer(),
                Text(c.label, style: AppText.body(size: 14, weight: FontWeight.w600)),
                Text('${kCatNotes[c.id]?.length ?? 0} 則筆記', style: AppText.caption(size: 11)),
              ],
            ),
          ),
        )),
        GestureDetector(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border, width: 1.5, style: BorderStyle.solid),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.plus, size: 20, color: AppColors.muted.withOpacity(0.6)),
                const SizedBox(height: 4),
                Text('新增分類', style: AppText.label(size: 12, color: AppColors.muted.withOpacity(0.6))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CatInfo {
  final String id, label;
  final IconData icon;
  final Color color, bg;
  const _CatInfo({required this.id, required this.label, required this.icon, required this.color, required this.bg});
}

// ─── Note Editor (owns its TextEditingController) ────────────────────────────

class _NoteEditor extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onChanged;

  const _NoteEditor({super.key, required this.initialText, required this.onChanged});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      maxLines: 6,
      decoration: InputDecoration(
        hintText: '在這裡寫下今天的筆記...',
        hintStyle: AppText.body(color: AppColors.muted),
        border: InputBorder.none,
      ),
      style: AppText.body(size: 14, height: 1.7),
      onChanged: widget.onChanged,
    );
  }
}

// ─── Category Detail ──────────────────────────────────────────────────────────

class _CatDetail extends StatelessWidget {
  final String catId;
  final VoidCallback onBack;

  const _CatDetail({required this.catId, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final notes = kCatNotes[catId] ?? [];
    final cats = {
      'undefined': ('未分類', LucideIcons.tag, AppColors.muted, const Color(0xFFF5F0E8)),
      'training': ('練習', LucideIcons.star, AppColors.sage, const Color(0xFFEFF5F1)),
      'diary': ('日記', LucideIcons.pencil, AppColors.rose, const Color(0xFFF5EEF0)),
      'academic': ('學術', LucideIcons.fileText, AppColors.blue, const Color(0xFFEEF0F5)),
    };
    final (label, icon, color, bg) = cats[catId]!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // Header
        Row(
          children: [
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Icon(LucideIcons.chevronLeft, size: 18, color: color),
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(label, style: AppText.display(size: 24, weight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 16),

        ...notes.map((n) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: MrCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title, style: AppText.body(size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(n.date, style: AppText.caption(size: 11)),
                const SizedBox(height: 6),
                Text(n.preview, style: AppText.label(size: 13, color: AppColors.muted)),
              ],
            ),
          ),
        )),

        const SizedBox(height: 4),
        GestureDetector(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.plus, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Text('新增筆記', style: AppText.label(size: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
