import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/app_errors.dart';
import '../../../core/constants.dart';
import '../../../core/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mr_card.dart';
import '../../../core/widgets/mr_icon_button.dart';
import '../../../shared/storage/storage_repo.dart';
import '../domain/note.dart';
import '../domain/note_category.dart';
import '../domain/note_repo.dart';
import 'note_modal_sheet.dart';

enum NoteMode { date, category }

// ─── Icon / palette constants ─────────────────────────────────────────────────

const kNoteIconMap = {
  'tag': LucideIcons.tag,
  'star': LucideIcons.star,
  'pencil': LucideIcons.pencil,
  'fileText': LucideIcons.fileText,
  'bookOpen': LucideIcons.bookOpen,
  'music': LucideIcons.music,
  'heart': LucideIcons.heart,
};

const kNoteIconKeys = [
  'tag',
  'star',
  'pencil',
  'fileText',
  'bookOpen',
  'music',
  'heart',
];

const kNoteCatPalette = [
  Color(0xFFBFA97A),
  Color(0xFFBF7A8E),
  Color(0xFF7A8EBF),
  Color(0xFF9E9E9E),
  Color(0xFF7BAF8A),
];

// ─── NotesPage ────────────────────────────────────────────────────────────────

class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NoteRepo>();
    return MultiProvider(
      providers: [
        StreamProvider<Set<String>>(
          create: (_) => repo.watchNoteDateKeys(),
          initialData: const <String>{},
          catchError: (_, e) {
            AppErrors.present(e);
            return const <String>{};
          },
        ),
        StreamProvider<List<NoteCategory>>(
          create: (_) => repo.watchNoteCategories(),
          initialData: const <NoteCategory>[],
          catchError: (_, e) {
            AppErrors.present(e);
            return const <NoteCategory>[];
          },
        ),
      ],
      child: const _NotesView(),
    );
  }
}

class _NotesView extends StatefulWidget {
  const _NotesView();

  @override
  State<_NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<_NotesView> {
  NoteMode _mode = NoteMode.date;

  // ── Date mode ──────────────────────────────────────────────────────────────
  int _year = DateTime.now().year;
  int _month = DateTime.now().month - 1; // 0-indexed
  int? _selectedDay;

  // ── Category mode ────────────────────────────────────────────────────────
  String? _openCatId;

  String get _selectedKey {
    final d = _selectedDay;
    if (d == null) return '';
    return '$_year-${fmt2(_month + 1)}-${fmt2(d)}';
  }

  void _selectDay(int day) {
    setState(() => _selectedDay = day);
  }

  void _closeDayPanel() {
    setState(() => _selectedDay = null);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<List<NoteCategory>>();

    if (_openCatId != null) {
      final cat = categories.firstWhere(
        (c) => c.id == _openCatId,
        orElse: () =>
            categories.isNotEmpty ? categories.first : NoteCategory.undefined,
      );
      return _CatDetail(
        category: cat,
        categories: categories,
        onBack: () => setState(() => _openCatId = null),
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
                      if (m == NoteMode.date) {
                        _year = DateTime.now().year;
                        _month = DateTime.now().month - 1; // 0-indexed
                        _selectedDay = DateTime.now().day;
                      }
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
          child: _mode == NoteMode.date
              ? _buildDateMode(context)
              : _buildCategoryMode(context, categories),
        ),
      ],
    );
  }

  // ── Date mode ────────────────────────────────────────────────────────────

  Widget _buildDateMode(BuildContext context) {
    final dateKeys = context.watch<Set<String>>();
    final daysInMonth = DateTime(_year, _month + 2, 0).day;
    final firstDow = DateTime(_year, _month + 1, 1).weekday % 7;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // Month / year navigation
        Row(
          children: [
            Text(
              '$_year年${_month + 1}月',
              style: AppText.body(size: 16, weight: FontWeight.w500),
            ),
            const Spacer(),
            MrIconButton(
              icon: LucideIcons.calendar,
              iconSize: 15,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (picked != null && mounted) {
                  setState(() {
                    _year = picked.year;
                    _month = picked.month - 1; // 0-indexed
                    _selectedDay = picked.day;
                  });
                }
              },
            ),
            const SizedBox(width: 6),
            MrIconButton(
              icon: LucideIcons.chevronLeft,
              iconSize: 15,
              onTap: () => setState(() {
                if (_month == 0) {
                  _year--;
                  _month = 11;
                } else {
                  _month--;
                }
                _selectedDay = null;
              }),
            ),
            const SizedBox(width: 6),
            MrIconButton(
              icon: LucideIcons.chevronRight,
              iconSize: 15,
              onTap: () => setState(() {
                if (_month == 11) {
                  _year++;
                  _month = 0;
                } else {
                  _month++;
                }
                _selectedDay = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Day-of-week header
        Row(
          children: kDow
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: AppText.caption(size: 10, weight: FontWeight.w600),
                    ),
                  ),
                ),
              )
              .toList(),
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
            final hasNote = dateKeys.contains(key);
            final isSelected = _selectedDay == day;
            final cellDate = DateTime(_year, _month + 1, day);
            final isToday = cellDate == today;
            final isPast = cellDate.isBefore(today);

            return GestureDetector(
              onTap: () {
                if (isSelected) {
                  _closeDayPanel();
                } else {
                  _selectDay(day);
                }
              },
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
                        width: 4,
                        height: 4,
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

        // ── Day panel ──────────────────────────────────────────────────────
        if (_selectedDay != null) ...[
          const SizedBox(height: 16),
          _DayPanel(
            dateKey: _selectedKey,
            month: _month + 1,
            day: _selectedDay!,
          ),
        ],
      ],
    );
  }

  // ── Category mode ────────────────────────────────────────────────────────

  Widget _buildCategoryMode(
    BuildContext context,
    List<NoteCategory> categories,
  ) {
    return GridView.count(
      physics: const AlwaysScrollableScrollPhysics(),
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        ...categories.map((c) {
          final icon = kNoteIconMap[c.iconName] ?? LucideIcons.tag;
          return GestureDetector(
            onTap: () => setState(() => _openCatId = c.id),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.tint(c.color, 0.08),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [kCardShadow],
              ),
              padding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 18, color: c.color),
                      ),
                      const Spacer(),
                      Text(
                        c.label,
                        style: AppText.body(size: 14, weight: FontWeight.w600),
                      ),
                      _CatCount(catId: c.id),
                    ],
                  ),
                  // Delete button — top-right of card (sentinel is not deletable)
                  if (c.id != kUndefinedCategoryId)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _confirmDeleteCategory(c),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            LucideIcons.trash2,
                            size: 13,
                            color: AppColors.muted.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),

        // Add category card
        GestureDetector(
          onTap: () => _showAddCategoryDialog(categories),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.plus,
                  size: 20,
                  color: AppColors.muted.withOpacity(0.6),
                ),
                const SizedBox(height: 4),
                Text(
                  '新增分類',
                  style: AppText.label(
                    size: 12,
                    color: AppColors.muted.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Category dialogs ─────────────────────────────────────────────────────

  void _showAddCategoryDialog(List<NoteCategory> categories) {
    final labelCtrl = TextEditingController();
    String selectedIcon =
        kNoteIconKeys[categories.length % kNoteIconKeys.length];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: AppColors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            '新增分類',
            style: AppText.body(size: 16, weight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: labelCtrl,
                autofocus: true,
                decoration: _fieldDecoration('分類名稱'),
                style: AppText.body(size: 14),
              ),
              const SizedBox(height: 14),
              Text(
                '選擇圖示',
                style: AppText.caption(size: 11, weight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: kNoteIconKeys.map((key) {
                  final isSelected = key == selectedIcon;
                  return GestureDetector(
                    onTap: () => setDialog(() => selectedIcon = key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.dark : AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        kNoteIconMap[key]!,
                        size: 16,
                        color: isSelected ? Colors.white : AppColors.muted,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                '取消',
                style: AppText.body(size: 14, color: AppColors.muted),
              ),
            ),
            TextButton(
              onPressed: () async {
                final label = labelCtrl.text.trim();
                if (label.isEmpty) return;
                Navigator.pop(ctx);
                final idx = categories.length;
                final color = kNoteCatPalette[idx % kNoteCatPalette.length];
                await context.read<NoteRepo>().addNoteCategory(
                  NoteCategory(
                    id: '',
                    label: label,
                    iconName: selectedIcon,
                    color: color,
                    sortOrder: idx,
                  ),
                );
              },
              child: Text(
                '新增',
                style: AppText.body(
                  size: 14,
                  weight: FontWeight.w600,
                  color: AppColors.dark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCategory(NoteCategory cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '刪除分類',
          style: AppText.body(size: 16, weight: FontWeight.w600),
        ),
        content: Text(
          '確定刪除「${cat.label}」？\n\n此分類下的札記會移回「無分類」。',
          style: AppText.body(size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '取消',
              style: AppText.body(size: 14, color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '刪除',
              style: AppText.body(
                size: 14,
                weight: FontWeight.w600,
                color: AppColors.rose,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<NoteRepo>().deleteNoteCategory(cat.id);
    }
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: AppText.body(color: AppColors.muted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.dark),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  );
}

// ─── Day panel (date mode) ──────────────────────────────────────────────────

class _DayPanel extends StatelessWidget {
  final String dateKey;
  final int month;
  final int day;

  const _DayPanel({
    required this.dateKey,
    required this.month,
    required this.day,
  });

  Future<void> _openAddNoteSheet(BuildContext context) async {
    final repo = context.read<NoteRepo>();
    final categories = context.read<List<NoteCategory>>();
    final result = await showNoteModalSheet(
      context,
      dateKey: dateKey,
      categories: categories,
    );
    if (result == null) return;
    final cat = categories.firstWhere(
      (c) => c.id == result.catId,
      orElse: () => NoteCategory.undefined,
    );
    await repo.add(
      Note(
        id: '',
        dateKey: dateKey,
        title: result.title.isEmpty ? '無標題' : result.title,
        content: result.content,
        category: NoteCategoryRef(
          id: cat.id,
          label: cat.label,
          color: cat.color,
          iconName: cat.iconName,
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      attachments: result.added,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NoteRepo>();
    return Column(
      children: [
        // Single dark "新增筆記" button — opens the modal sheet.
        GestureDetector(
          onTap: () => _openAddNoteSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.plus, size: 15, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  '新增 $month月$day日 的札記',
                  style: AppText.body(
                    size: 14,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Notes for this day.
        StreamProvider<List<Note>>(
          key: ValueKey('day-$dateKey'),
          create: (_) => repo.watchNotes(dateKey: dateKey),
          initialData: const <Note>[],
          catchError: (_, e) {
            AppErrors.present(e);
            return const <Note>[];
          },
          child: const _DayNotesList(),
        ),
      ],
    );
  }
}

class _DayNotesList extends StatelessWidget {
  const _DayNotesList();

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<List<Note>>();
    if (notes.isEmpty) return const SizedBox.shrink();
    return Column(
      children: notes
          .map(
            (n) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _NoteCard(note: n, showDate: false),
            ),
          )
          .toList(),
    );
  }
}

// ─── Category Detail ──────────────────────────────────────────────────────────

class _CatDetail extends StatelessWidget {
  final NoteCategory category;
  final List<NoteCategory> categories;
  final VoidCallback onBack;

  const _CatDetail({
    required this.category,
    required this.categories,
    required this.onBack,
  });

  Future<void> _openAddSheet(BuildContext context) async {
    final repo = context.read<NoteRepo>();
    final result = await showNoteModalSheet(
      context,
      dateKey: todayKey(),
      categories: categories,
      initialCatId: category.id,
    );
    if (result == null) return;
    final cat = categories.firstWhere(
      (c) => c.id == result.catId,
      orElse: () => NoteCategory.undefined,
    );
    await repo.add(
      Note(
        id: '',
        dateKey: todayKey(),
        title: result.title.isEmpty ? '無標題' : result.title,
        content: result.content,
        category: NoteCategoryRef(
          id: cat.id,
          label: cat.label,
          color: cat.color,
          iconName: cat.iconName,
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      attachments: result.added,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NoteRepo>();
    final icon = kNoteIconMap[category.iconName] ?? LucideIcons.tag;

    return StreamProvider<List<Note>>(
      key: ValueKey('cat-${category.id}'),
      create: (_) => repo.watchNotesByCategory(category.id),
      initialData: const <Note>[],
      catchError: (_, e) {
        AppErrors.present(e);
        return const <Note>[];
      },
      child: Builder(
        builder: (context) {
          final notes = context.watch<List<Note>>();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            children: [
              // Header
              Row(
                children: [
                  GestureDetector(
                    onTap: onBack,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.tint(category.color, 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        LucideIcons.chevronLeft,
                        size: 18,
                        color: category.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(icon, size: 20, color: category.color),
                  const SizedBox(width: 8),
                  Text(
                    category.label,
                    style: AppText.display(size: 24, weight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              ...notes.map(
                (note) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _NoteCard(note: note, showDate: true),
                ),
              ),

              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _openAddSheet(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.dark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.plus,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '新增札記',
                        style: AppText.body(
                          size: 14,
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Per-category note count ────────────────────────────────────────────────

class _CatCount extends StatelessWidget {
  final String catId;
  const _CatCount({required this.catId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Note>>(
      stream: context.read<NoteRepo>().watchNotesByCategory(catId),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        return Text('$count 則札記', style: AppText.caption(size: 11));
      },
    );
  }
}

// ─── Note card (shared between date + category modes) ────────────────────────

class _NoteCard extends StatefulWidget {
  final Note note;
  final bool showDate;
  const _NoteCard({required this.note, required this.showDate});

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _expanded = false;

  String _formatDate(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length < 3) return dateKey;
    return '${int.parse(parts[1])}月${int.parse(parts[2])}日';
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '刪除札記',
          style: AppText.body(size: 16, weight: FontWeight.w600),
        ),
        content: Text('確定刪除這份札記？', style: AppText.body(size: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '取消',
              style: AppText.body(size: 14, color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '刪除',
              style: AppText.body(
                size: 14,
                weight: FontWeight.w600,
                color: AppColors.rose,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<NoteRepo>().delete(widget.note.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final cat = note.category;

    return MrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showDate)
                Expanded(
                  child: Text(
                    _formatDate(note.dateKey),
                    style: AppText.body(size: 14, weight: FontWeight.w600),
                  ),
                )
              else
                // Category chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cat.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    cat.label,
                    style: AppText.caption(size: 10, color: cat.color),
                  ),
                ),
              if (!widget.showDate) const Spacer(),
              _IconAction(
                icon: _expanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
              _IconAction(icon: LucideIcons.trash2, onTap: _confirmDelete),
            ],
          ),
          if (note.title.isNotEmpty && note.title != '無標題') ...[
            const SizedBox(height: 6),
            Text(
              note.title,
              style: AppText.body(size: 14, weight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              note.content,
              maxLines: _expanded ? null : 2,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: AppText.label(size: 13, color: AppColors.muted),
            ),
          ),
          if (note.attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _AttachmentRow(attachments: note.attachments),
          ],
        ],
      ),
    );
  }
}

// ─── Small reusable widgets ──────────────────────────────────────────────────

class _IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Icon(icon, size: 14, color: AppColors.muted),
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final List<NoteAttachment> attachments;
  const _AttachmentRow({required this.attachments});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((a) {
        switch (a.type) {
          case 'image':
            return _ImageThumb(att: a);
          case 'audio':
            return _AttachInfoChip(icon: LucideIcons.music, label: a.filename);
          default:
            return _AttachInfoChip(
              icon: LucideIcons.fileText,
              label: a.filename,
            );
        }
      }).toList(),
    );
  }
}

class _ImageThumb extends StatefulWidget {
  final NoteAttachment att;
  const _ImageThumb({required this.att});

  @override
  State<_ImageThumb> createState() => _ImageThumbState();
}

class _ImageThumbState extends State<_ImageThumb> {
  String? _url;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final url = await context.read<StorageRepo>().downloadUrl(
        widget.att.storagePath,
      );
      if (mounted) setState(() => _url = url);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _showViewer() {
    final url = _url;
    if (url == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_failed) {
      content = Container(
        width: 56,
        height: 56,
        color: AppColors.border,
        child: const Icon(
          LucideIcons.imageOff,
          size: 18,
          color: AppColors.muted,
        ),
      );
    } else if (_url == null) {
      content = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(10),
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          _url!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 56,
            height: 56,
            color: AppColors.border,
            child: const Icon(
              LucideIcons.imageOff,
              size: 18,
              color: AppColors.muted,
            ),
          ),
        ),
      );
    }
    return GestureDetector(onTap: _showViewer, child: content);
  }
}

class _AttachInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AttachInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              style: AppText.caption(size: 11, color: AppColors.dark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
