import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:myroom/models/note_item.dart';
import 'package:myroom/services/database_service.dart';
import 'package:myroom/services/openai_service.dart';
import '../theme.dart';
import '../data/seed_data.dart';
import '../widgets/mr_card.dart';
import '../widgets/mr_icon_button.dart';

enum NoteMode { date, category }

// ─── Icon / palette constants ─────────────────────────────────────────────────

const kNoteIconMap = {
  'tag':      LucideIcons.tag,
  'star':     LucideIcons.star,
  'pencil':   LucideIcons.pencil,
  'fileText': LucideIcons.fileText,
  'bookOpen': LucideIcons.bookOpen,
  'music':    LucideIcons.music,
  'heart':    LucideIcons.heart,
};

const kNoteIconKeys = [
  'tag', 'star', 'pencil', 'fileText', 'bookOpen', 'music', 'heart',
];

const kNoteCatPalette = [
  (Color(0xFFBFA97A), Color(0xFFFFF8ED)),
  (Color(0xFFBF7A8E), Color(0xFFF5EEF0)),
  (Color(0xFF7A8EBF), Color(0xFFEEF0F5)),
  (Color(0xFF9E9E9E), Color(0xFFF5F0E8)),
  (Color(0xFF7BAF8A), Color(0xFFEFF5F1)),
];

// ─── NotePage ─────────────────────────────────────────────────────────────────

class NotePage extends StatefulWidget {
  /// Sparse map of date_key → content used only for calendar dot indicators.
  final Map<String, String> notes;

  /// Called after any note mutation so main.dart can re-fetch _notes.
  final VoidCallback onNotesMutated;

  const NotePage({super.key, required this.notes, required this.onNotesMutated});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  NoteMode _mode = NoteMode.date;

  // ── Date mode ────────────────────────────────────────────────────────────
  int _year  = DateTime.now().year;
  int _month = DateTime.now().month - 1; // 0-indexed
  int _day = DateTime.now().day;
  int? _selectedDay;

  /// Controller for the primary date note editor.
  /// Lifted here so the clear button can call .clear() directly.
  TextEditingController? _noteCtrl;

  /// Mirror of _noteCtrl.text — used to decide whether to run AI on close.
  String _editorContent = '';

  /// All notes (primary + categorized) for the currently selected day.
  List<NoteItem> _dayNotes = [];

  /// Expanded state for categorized note cards in the day panel.
  final Set<int> _dayNoteExpandedIds = {};

  // ── Category mode ────────────────────────────────────────────────────────
  String? _openCatId;
  List<NoteCategory> _categories = [];
  Map<String, List<NoteItem>> _catNotes = {};

  // ── AI state ─────────────────────────────────────────────────────────────
  bool _classifyingNote = false;

  // ─────────────────────────────────────────────────────────────────────────

  String get _noteKey {
    final d = _selectedDay;
    if (d == null) return '';
    return '$_year-${fmt2(_month + 1)}-${fmt2(d)}';
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _selectDay(_day , '$_year-${fmt2(_month + 1)}-${fmt2(_day)}');
  }

  @override
  void dispose() {
    _noteCtrl?.dispose();
    super.dispose();
  }

  // ── Data loaders ─────────────────────────────────────────────────────────

  Future<void> _loadCategories() async {
    final cats = await DatabaseService.instance.getNoteCategories();
    final notesMap = <String, List<NoteItem>>{};
    for (final c in cats) {
      notesMap[c.id] = await DatabaseService.instance.getNotesByCategory(c.id);
    }
    if (mounted) setState(() { _categories = cats; _catNotes = notesMap; });
  }

  Future<void> _loadCatNotes(String catId) async {
    final notes = await DatabaseService.instance.getNotesByCategory(catId);
    if (mounted) setState(() => _catNotes[catId] = notes);
  }

  Future<void> _loadDayNotes(String dateKey) async {
    final notes = await DatabaseService.instance.getNotesByDate(dateKey);
    if (!mounted) return;
    // Sync the primary note's content into the text controller
    final primary = notes.where((n) => n.catId == null).firstOrNull;
    if (_noteCtrl != null && primary != null &&
        _noteCtrl!.text != primary.content) {
      _noteCtrl!.text = primary.content;
    }
    setState(() => _dayNotes = notes);
  }

  // ── Note actions ──────────────────────────────────────────────────────────

  Future<void> _saveNote(String text) async {
    if (_noteKey.isEmpty) return;
    _editorContent = text;
    await DatabaseService.instance.upsertNote(_noteKey, text);
    widget.onNotesMutated();
  }

  void _selectDay(int day, String key) {
    _noteCtrl?.dispose();
    final initialText = '';
    _noteCtrl = TextEditingController(text: initialText);
    _editorContent = initialText;
    _dayNoteExpandedIds.clear();
    setState(() {
      _selectedDay = day;
      _dayNotes = [];
    });
    _loadDayNotes(key);
  }

  void _closeDayPanel() {
    final key = _noteKey;
    final content = _editorContent;
    _noteCtrl?.dispose();
    _noteCtrl = null;
    _dayNoteExpandedIds.clear();
    setState(() {
      _selectedDay = null;
      _editorContent = '';
      _dayNotes = [];
    });
    if (content.isNotEmpty && !_classifyingNote && key.isNotEmpty) {
      _classifyNote(key, content);
    }
  }

  Future<void> _classifyNote(String dateKey, String content) async {
    if (_categories.isEmpty) return;
    setState(() => _classifyingNote = true);
    try {
      final note = await DatabaseService.instance.getNotePrimary(dateKey);
      if (note == null || !mounted) return;
      final catId = await OpenAIService.instance.classifyNoteToCategory(
        content, _categories,
      );
      if (catId != null && mounted) {
        await DatabaseService.instance.updateNoteCat(note.id, catId);
        await _loadCatNotes(catId);
        widget.onNotesMutated();
      }
    } finally {
      if (mounted) setState(() => _classifyingNote = false);
    }
  }

  /// After a new category is created, silently re-checks all 未分類 notes
  /// (cat_id = 'undefined') and moves any that fit the new category.
  Future<void> _reclassifyUndefinedNotes(String newCatId) async {
    final undefinedNotes =
        await DatabaseService.instance.getNotesByCategory('undefined');
    if (undefinedNotes.isEmpty || !mounted) return;

    final catIdx = _categories.indexWhere((c) => c.id == newCatId);
    if (catIdx == -1) return;

    final matchIds = await OpenAIService.instance.findNotesMatchingCategory(
      _categories[catIdx],
      undefinedNotes,
    );
    if (matchIds.isEmpty || !mounted) return;

    await Future.wait(
      matchIds.map((id) => DatabaseService.instance.updateNoteCat(id, newCatId)),
    );
    await Future.wait([
      _loadCatNotes(newCatId),
      _loadCatNotes('undefined'),
    ]);
    widget.onNotesMutated();
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showAddNoteToDayDialog(String dateKey) {
    if (_categories.isEmpty) return;
    final contentCtrl = TextEditingController();
    String selectedCatId = _categories.first.id;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: AppColors.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('新增筆記', style: AppText.body(size: 16, weight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: contentCtrl,
                maxLines: 4,
                decoration: _fieldDecoration('內容'),
                style: AppText.body(size: 14, height: 1.6),
              ),
              const SizedBox(height: 12),
              Text('分類', style: AppText.caption(size: 11, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: _categories.map((c) {
                  final isSelected = c.id == selectedCatId;
                  return GestureDetector(
                    onTap: () => setDialog(() => selectedCatId = c.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.dark : AppColors.border,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        c.label,
                        style: AppText.caption(
                          size: 12,
                          color: isSelected ? Colors.white : AppColors.muted,
                        ),
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
              child: Text('取消', style: AppText.body(size: 14, color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () async {
                final content = contentCtrl.text.trim();
                if (content.isEmpty) return;
                Navigator.pop(ctx);
                await DatabaseService.instance.insertCatNote(
                  dateKey,
                  content,
                  selectedCatId,
                );
                await Future.wait([
                  _loadDayNotes(dateKey),
                  _loadCatNotes(selectedCatId),
                ]);
                widget.onNotesMutated();
              },
              child: Text(
                '儲存',
                style: AppText.body(size: 14, weight: FontWeight.w600, color: AppColors.dark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCategoryDialog() {
    final labelCtrl = TextEditingController();
    String selectedIcon = kNoteIconKeys[_categories.length % kNoteIconKeys.length];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: AppColors.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('新增分類', style: AppText.body(size: 16, weight: FontWeight.w600)),
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
              Text('選擇圖示', style: AppText.caption(size: 11, weight: FontWeight.w600)),
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
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.dark : AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        kNoteIconMap[key]!, size: 16,
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
              child: Text('取消', style: AppText.body(size: 14, color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () async {
                final label = labelCtrl.text.trim();
                if (label.isEmpty) return;
                Navigator.pop(ctx);
                final idx = _categories.length;
                final palette = kNoteCatPalette[idx % kNoteCatPalette.length];
                final id = '${label.toLowerCase().replaceAll(' ', '_')}_'
                    '${DateTime.now().millisecondsSinceEpoch}';
                await DatabaseService.instance.insertNoteCategory(NoteCategory(
                  id: id, label: label, iconName: selectedIcon,
                  color: palette.$1, bg: palette.$2, sortOrder: idx,
                ));
                await _loadCategories();
                // Background: move 未分類 notes that fit the new category.
                _reclassifyUndefinedNotes(id);
              },
              child: Text(
                '新增',
                style: AppText.body(size: 14, weight: FontWeight.w600, color: AppColors.dark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCategory(NoteCategory cat) async {
    final noteCount = _catNotes[cat.id]?.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('刪除分類', style: AppText.body(size: 16, weight: FontWeight.w600)),
        content: Text(
          '確定刪除「${cat.label}」？'
          '${noteCount > 0 ? '\n\n此分類下的 $noteCount 則筆記也會一併刪除。' : ''}',
          style: AppText.body(size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: AppText.body(size: 14, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '刪除',
              style: AppText.body(size: 14, weight: FontWeight.w600, color: AppColors.rose),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await DatabaseService.instance.deleteNoteCategory(cat.id);
      await _loadCategories();
      widget.onNotesMutated();
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

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_openCatId != null) {
      final cat = _categories.firstWhere(
        (c) => c.id == _openCatId,
        orElse: () => _categories.first,
      );
      return _CatDetail(
        category: cat,
        notes: _catNotes[_openCatId] ?? [],
        onBack: () => setState(() => _openCatId = null),
        onNoteAdded: (content) async {
          await DatabaseService.instance.insertCatNote(
            todayKey(), content, _openCatId!,
          );
          await _loadCatNotes(_openCatId!);
          widget.onNotesMutated();
        },
        onNoteDeleted: (id) async {
          await DatabaseService.instance.deleteNote(id);
          await _loadCatNotes(_openCatId!);
          widget.onNotesMutated();
        },
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
                        _year  = DateTime.now().year;
                        _month = DateTime.now().month - 1; // 0-indexed
                        _day = DateTime.now().day;
                        _selectDay(_day , '$_year-${fmt2(_month + 1)}-${fmt2(_day)}');
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
              ? _buildDateMode()
              : _buildCategoryMode(),
        ),
      ],
    );
  }

  // ── Date mode ────────────────────────────────────────────────────────────

  Widget _buildDateMode() {
    final daysInMonth = DateTime(_year, _month + 2, 0).day;
    final firstDow    = DateTime(_year, _month + 1, 1).weekday % 7;
    final now         = DateTime.now();
    final today       = DateTime(now.year, now.month, now.day);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // Month / year navigation
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _year = DateTime.now().year;
                _month = DateTime.now().month - 1; // 0-indexed
                _day = DateTime.now().day;
                _selectDay(_day , '$_year-${fmt2(_month + 1)}-${fmt2(_day)}');
              }),
              child: Text(
                '$_year年${kMonthNames[_month]}',
                style: AppText.display(size: 22, weight: FontWeight.w500),
              ),
            ),
            const Spacer(),
            if (_classifyingNote) ...[
              const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppColors.muted,
                ),
              ),
              const SizedBox(width: 8),
            ],
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
                    _day = picked.day;
                    _selectDay(_day , '$_year-${fmt2(_month + 1)}-${fmt2(_day)}');
                  });
                }
              }
            ),
            const SizedBox(width: 6),
            MrIconButton(
              icon: LucideIcons.chevronLeft,
              iconSize: 15,
              onTap: () => setState(() {
                if (_month == 0) { _year--; _month = 11; } else { _month--; }
                _selectedDay = null;
              }),
            ),
            const SizedBox(width: 6),
            MrIconButton(
              icon: LucideIcons.chevronRight,
              iconSize: 15,
              onTap: () => setState(() {
                if (_month == 11) { _year++; _month = 0; } else { _month++; }
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
            final hasNote = widget.notes.containsKey(key) ||
                _catNotes.values.any((list) => list.any((n) => n.dateKey == key));
            final isSelected = _selectedDay == day;
            final cellDate  = DateTime(_year, _month + 1, day);
            final isToday   = cellDate == today;
            final isPast    = cellDate.isBefore(today);

            return GestureDetector(
              onTap: () {
                if (isSelected) {
                  _closeDayPanel();
                } else {
                  _selectDay(day, key);
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
                            : isPast ? AppColors.muted : AppColors.dark,
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

        // ── Day panel ──────────────────────────────────────────────────────
        if (_selectedDay != null) ...[
          const SizedBox(height: 16),

          // Primary date note editor
          MrCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${_month + 1}月$_selectedDay日 $_year',
                      style: AppText.body(size: 13, weight: FontWeight.w500),
                    ),
                    const Spacer(),
                    // Clear button — clears both controller and DB
                    if (_editorContent.isNotEmpty)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          _noteCtrl?.clear(); // fix: clears the visible text field
                          setState(() => _editorContent = '');
                          await DatabaseService.instance.upsertNote(_noteKey, '');
                          widget.onNotesMutated();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Icon(
                            LucideIcons.eraser, size: 15, color: AppColors.muted,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: _closeDayPanel,
                      child: const Icon(
                        LucideIcons.save, size: 16, color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_noteCtrl != null)
                  _NoteEditor(
                    controller: _noteCtrl!,
                    onChanged: _saveNote,
                  ),
              ],
            ),
          ),

          // Categorized notes for this day
          ..._dayNotes
              .where((n) => n.catId != null)
              .map((note) => _buildDayNoteCard(note)),

          const SizedBox(height: 8),

          // Add more note button
          GestureDetector(
            onTap: () => _showAddNoteToDayDialog(_noteKey),
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
      ],
    );
  }

  Widget _buildDayNoteCard(NoteItem note) {
    final isExpanded = _dayNoteExpandedIds.contains(note.id);
    final cat = _categories.firstWhere(
      (c) => c.id == note.catId,
      orElse: () => NoteCategory(
        id: '', label: '未分類', iconName: 'tag',
        color: AppColors.muted, bg: AppColors.border, sortOrder: 0,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cat.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    cat.label,
                    style: AppText.caption(size: 10, color: cat.color),
                  ),
                ),
                const Spacer(),
                // Expand chevron
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    if (isExpanded) {
                      _dayNoteExpandedIds.remove(note.id);
                    } else {
                      _dayNoteExpandedIds.add(note.id);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 4),
                    child: Icon(
                      isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 14, color: AppColors.muted,
                    ),
                  ),
                ),
                // Delete button
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await DatabaseService.instance.deleteNote(note.id);
                    await Future.wait([
                      _loadDayNotes(_noteKey),
                      if (note.catId != null) _loadCatNotes(note.catId!),
                    ]);
                    widget.onNotesMutated();
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(LucideIcons.trash2, size: 14, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() {
                if (isExpanded) {
                  _dayNoteExpandedIds.remove(note.id);
                } else {
                  _dayNoteExpandedIds.add(note.id);
                }
              }),
              child: Text(
                note.content,
                maxLines: isExpanded ? null : 2,
                overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: AppText.label(size: 13, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Category mode ────────────────────────────────────────────────────────

  Widget _buildCategoryMode() {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        ..._categories.map((c) {
          final icon  = kNoteIconMap[c.iconName] ?? LucideIcons.tag;
          final count = _catNotes[c.id]?.length ?? 0;
          return GestureDetector(
            onTap: () => setState(() => _openCatId = c.id),
            child: Container(
              decoration: BoxDecoration(
                color: c.bg,
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
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: c.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 18, color: c.color),
                      ),
                      const Spacer(),
                      Text(c.label, style: AppText.body(size: 14, weight: FontWeight.w600)),
                      Text('$count 則筆記', style: AppText.caption(size: 11)),
                    ],
                  ),
                  // Delete button — top-right of card
                  Positioned(
                    top: 0, right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _confirmDeleteCategory(c),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          LucideIcons.trash2, size: 13,
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
          onTap: _showAddCategoryDialog,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.plus, size: 20, color: AppColors.muted.withOpacity(0.6)),
                const SizedBox(height: 4),
                Text(
                  '新增分類',
                  style: AppText.label(size: 12, color: AppColors.muted.withOpacity(0.6)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Note Editor (StatelessWidget — controller owned by parent) ───────────────

class _NoteEditor extends StatelessWidget {
  final TextEditingController controller;
  final Future<void> Function(String) onChanged;

  const _NoteEditor({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 6,
      decoration: InputDecoration(
        hintText: '在這裡寫下今天的筆記...',
        hintStyle: AppText.body(color: AppColors.muted),
        border: InputBorder.none,
      ),
      style: AppText.body(size: 14, height: 1.7),
      onChanged: onChanged,
    );
  }
}

// ─── Category Detail ──────────────────────────────────────────────────────────

class _CatDetail extends StatefulWidget {
  final NoteCategory category;
  final List<NoteItem> notes;
  final VoidCallback onBack;
  final Future<void> Function(String content) onNoteAdded;
  final Future<void> Function(int id) onNoteDeleted;

  const _CatDetail({
    required this.category,
    required this.notes,
    required this.onBack,
    required this.onNoteAdded,
    required this.onNoteDeleted,
  });

  @override
  State<_CatDetail> createState() => _CatDetailState();
}

class _CatDetailState extends State<_CatDetail> {
  final Set<int> _expandedIds = {};

  String _formatDate(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length < 3) return dateKey;
    return '${int.parse(parts[1])}月${int.parse(parts[2])}日';
  }

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

  void _showAddNoteDialog() {
    final contentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('新增筆記', style: AppText.body(size: 16, weight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              decoration: _fieldDecoration('內容'),
              style: AppText.body(size: 14, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: AppText.body(size: 14, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () async {
              final content = contentCtrl.text.trim();
              if (content.isEmpty) return;
              Navigator.pop(ctx);
              await widget.onNoteAdded(
                content,
              );
            },
            child: Text(
              '儲存',
              style: AppText.body(size: 14, weight: FontWeight.w600, color: AppColors.dark),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat  = widget.category;
    final icon = kNoteIconMap[cat.iconName] ?? LucideIcons.tag;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // Header
        Row(
          children: [
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: cat.bg, borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.chevronLeft, size: 18, color: cat.color),
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 20, color: cat.color),
            const SizedBox(width: 8),
            Text(cat.label, style: AppText.display(size: 24, weight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 16),

        ...widget.notes.map((note) {
          final isExpanded   = _expandedIds.contains(note.id);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MrCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            if (isExpanded) {
                              _expandedIds.remove(note.id);
                            } else {
                              _expandedIds.add(note.id);
                            }
                          }),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_formatDate(note.dateKey),
                                  style: AppText.body(size: 14, weight: FontWeight.w600)),
                              const SizedBox(height: 2),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          if (isExpanded) {
                            _expandedIds.remove(note.id);
                          } else {
                            _expandedIds.add(note.id);
                          }
                        }),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, right: 4),
                          child: Icon(
                            isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                            size: 14, color: AppColors.muted,
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onNoteDeleted(note.id),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(LucideIcons.trash2, size: 14, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => setState(() {
                      if (isExpanded) {
                        _expandedIds.remove(note.id);
                      } else {
                        _expandedIds.add(note.id);
                      }
                    }),
                    child: Text(
                      note.content,
                      maxLines: isExpanded ? null : 2,
                      overflow: isExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: AppText.label(size: 13, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 4),
        GestureDetector(
          onTap: _showAddNoteDialog,
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
