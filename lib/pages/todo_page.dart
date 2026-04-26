import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../models/todo_item.dart';
import '../widgets/mr_card.dart';
import '../widgets/mr_add_row.dart';

// Priority metadata
const _kPriorityLabels = {1: '最高', 2: '高', 3: '中', 4: '低'};
const _kPriorityColors = {
  1: AppColors.rose,
  2: AppColors.amber,
  3: AppColors.blue,
  4: AppColors.muted,
};

// Built-in categories (always available)
const _kBuiltinCats = ['工作', '學習', '個人', '健康'];
const _kBuiltinColors = {
  '工作': AppColors.blue,
  '學習': AppColors.sage,
  '個人': AppColors.rose,
  '健康': AppColors.amber,
};

enum _SortMode { priority, time }

class TodoPage extends StatefulWidget {
  final List<TodoItem> todos;
  final List<TodoCategory> categories;
  final ValueChanged<TodoItem> onTodoAdded;
  final ValueChanged<TodoItem> onTodoToggled;
  final void Function(String name, Color color) onCategoryAdded;
  final ValueChanged<int> onCategoryDeleted;

  const TodoPage({
    super.key,
    required this.todos,
    required this.categories,
    required this.onTodoAdded,
    required this.onTodoToggled,
    required this.onCategoryAdded,
    required this.onCategoryDeleted,
  });

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  String _activeCat = '全部';
  bool _showAdd = false;
  bool _showDone = true;
  _SortMode _sortMode = _SortMode.priority;

  final _newTextCtrl = TextEditingController();
  final _addFocus = FocusNode();
  String _newCat = '工作';
  int _newPriority = 3;

  @override
  void dispose() {
    _newTextCtrl.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  // All category names (builtin + custom)
  List<String> get _allCatNames {
    final custom = widget.categories.map((c) => c.name).toList();
    return ['全部', ..._kBuiltinCats, ...custom];
  }

  Color _colorForCat(String cat) {
    if (_kBuiltinColors.containsKey(cat)) return _kBuiltinColors[cat]!;
    final found = widget.categories.where((c) => c.name == cat).firstOrNull;
    return found?.color ?? AppColors.muted;
  }

  List<TodoItem> get _sorted {
    final filtered = (_activeCat == '全部'
        ? widget.todos
        : widget.todos.where((t) => t.cat == _activeCat).toList());

    final active = filtered.where((t) => !t.done).toList();
    final done = filtered.where((t) => t.done).toList();

    if (_sortMode == _SortMode.priority) {
      active.sort((a, b) => a.priority != b.priority
          ? a.priority.compareTo(b.priority)
          : a.createdAt.compareTo(b.createdAt));
      done.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else {
      active.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      done.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    return _showDone ? [...active, ...done] : active;
  }

  void _toggleTodo(int id) {
    final todo = widget.todos.firstWhere((t) => t.id == id);
    widget.onTodoToggled(todo.copyWith(done: !todo.done));
  }

  void _addTodo() {
    if (_newTextCtrl.text.trim().isEmpty) return;
    widget.onTodoAdded(TodoItem(
      id: 0,
      text: _newTextCtrl.text.trim(),
      done: false,
      cat: _newCat,
      color: _colorForCat(_newCat),
      priority: _newPriority,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _newTextCtrl.clear();
    setState(() => _showAdd = false);
  }

  void _showAddCategorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCategorySheet(
        existingCategories: widget.categories,
        onAdd: (name, color) {
          widget.onCategoryAdded(name, color);
          Navigator.pop(context);
        },
        onDelete: (id) {
          widget.onCategoryDeleted(id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.todos.where((t) => t.done).length;
    final total = widget.todos.length;
    final pct = total > 0 ? done / total : 0.0;
    final items = _sorted;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress card
          MrCard(
            child: Row(
              children: [
                _ProgressRing(progress: pct),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('今日完成度', style: AppText.body(size: 13, weight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text('$done / $total 項任務', style: AppText.caption()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Controls row: sort mode + show-done toggle
          Row(
            children: [
              // Sort mode toggle
              GestureDetector(
                onTap: () => setState(() => _sortMode =
                    _sortMode == _SortMode.priority ? _SortMode.time : _SortMode.priority),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [kCardShadow],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _sortMode == _SortMode.priority ? LucideIcons.arrowUpDown : LucideIcons.clock,
                        size: 13, color: AppColors.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _sortMode == _SortMode.priority ? '優先順序' : '建立時間',
                        style: AppText.caption(size: 12, weight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Show done toggle
              GestureDetector(
                onTap: () => setState(() => _showDone = !_showDone),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _showDone ? AppColors.dark : AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [kCardShadow],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showDone ? LucideIcons.eyeOff : LucideIcons.eye,
                        size: 13, color: _showDone ? Colors.white : AppColors.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '已完成',
                        style: AppText.caption(
                          size: 12, weight: FontWeight.w500,
                          color: _showDone ? Colors.white : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Category filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._allCatNames.map((cat) {
                  final active = _activeCat == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _activeCat = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 7),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? AppColors.dark : AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: active ? const [kBtnShadow] : const [kCardShadow],
                      ),
                      child: Text(
                        cat,
                        style: AppText.body(
                          size: 13,
                          weight: FontWeight.w500,
                          color: active ? Colors.white : AppColors.muted,
                        ),
                      ),
                    ),
                  );
                }),
                // "+" to manage custom categories
                GestureDetector(
                  onTap: _showAddCategorySheet,
                  child: Container(
                    margin: const EdgeInsets.only(right: 7),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(LucideIcons.plus, size: 14, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Todo list
          ...items.map((t) {
            final isDone = t.done;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: MrCard(
                onTap: () => _toggleTodo(t.id),
                child: Row(
                  children: [
                    // Priority indicator (only for active items)
                    if (!isDone)
                      Container(
                        width: 4,
                        height: 40,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: _kPriorityColors[t.priority] ?? AppColors.muted,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    // Checkbox
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 23, height: 23,
                      decoration: BoxDecoration(
                        color: isDone ? t.color : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isDone ? null : Border.all(color: t.color, width: 2),
                      ),
                      child: isDone
                          ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.text,
                            style: AppText.body(
                              size: 14,
                              weight: FontWeight.w500,
                              color: isDone ? AppColors.dark.withOpacity(0.4) : AppColors.dark,
                            ).copyWith(
                              decoration: isDone ? TextDecoration.lineThrough : null,
                              decorationColor: AppColors.muted,
                            ),
                          ),
                          if (!isDone) ...[
                            const SizedBox(height: 3),
                            Text(
                              '優先級：${_kPriorityLabels[t.priority] ?? '中'}',
                              style: AppText.caption(
                                size: 10,
                                color: _kPriorityColors[t.priority] ?? AppColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        t.cat,
                        style: AppText.caption(size: 10, color: t.color),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Add form / add row
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _showAdd ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: MrAddRow(
              label: '新增待辦',
              onTap: () {
                setState(() => _showAdd = true);
                Future.microtask(() => _addFocus.requestFocus());
              },
            ),
            secondChild: MrCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _newTextCtrl,
                    focusNode: _addFocus,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: '新增任務...',
                      hintStyle: AppText.body(color: AppColors.muted),
                      border: InputBorder.none,
                    ),
                    style: AppText.body(size: 14),
                    onSubmitted: (_) => _addTodo(),
                  ),
                  const SizedBox(height: 10),

                  // Category picker
                  Text('類別', style: AppText.caption(size: 11, weight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 7, runSpacing: 6,
                    children: [
                      ..._kBuiltinCats.map((name) => _CatChip(
                        label: name,
                        color: _kBuiltinColors[name]!,
                        selected: _newCat == name,
                        onTap: () => setState(() => _newCat = name),
                      )),
                      ...widget.categories.map((c) => _CatChip(
                        label: c.name,
                        color: c.color,
                        selected: _newCat == c.name,
                        onTap: () => setState(() => _newCat = c.name),
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Priority picker
                  Text('優先級', style: AppText.caption(size: 11, weight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [1, 2, 3, 4].map((p) {
                      final selected = _newPriority == p;
                      return GestureDetector(
                        onTap: () => setState(() => _newPriority = p),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? (_kPriorityColors[p] ?? AppColors.muted)
                                : AppColors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? Colors.transparent
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            _kPriorityLabels[p]!,
                            style: AppText.caption(
                              size: 12,
                              color: selected ? Colors.white : AppColors.muted,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _addTodo,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.dark,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text('新增', style: AppText.body(size: 13, weight: FontWeight.w600, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() {
                          _showAdd = false;
                          _newTextCtrl.clear();
                        }),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(LucideIcons.x, size: 16, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Category Chip ────────────────────────────────────────────────────────────

class _CatChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CatChip({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.dark : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppText.caption(size: 12, color: selected ? Colors.white : AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Category Sheet ───────────────────────────────────────────────────────

class _AddCategorySheet extends StatefulWidget {
  final List<TodoCategory> existingCategories;
  final void Function(String name, Color color) onAdd;
  final ValueChanged<int> onDelete;

  const _AddCategorySheet({
    required this.existingCategories,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<_AddCategorySheet> {
  final _nameCtrl = TextEditingController();
  Color _selectedColor = AppColors.sage;

  static const _palette = [
    AppColors.sage, AppColors.amber, AppColors.blue, AppColors.rose, AppColors.dark,
    Color(0xFF9B7EDE), Color(0xFF4CAF50), Color(0xFFFF7043), Color(0xFF26C6DA), Color(0xFFEC407A),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 20),
            Text('自訂類別', style: AppText.body(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 16),

            // Existing custom categories
            if (widget.existingCategories.isNotEmpty) ...[
              Text('已建立', style: AppText.caption(size: 11, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: widget.existingCategories.map((c) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.color.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(c.name, style: AppText.caption(size: 13, color: AppColors.dark)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => widget.onDelete(c.id),
                        child: const Icon(LucideIcons.x, size: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 12),
            ],

            // New category form
            Text('新增類別', style: AppText.caption(size: 11, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: '類別名稱',
                hintStyle: AppText.body(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              style: AppText.body(size: 14),
            ),
            const SizedBox(height: 12),
            Text('選擇顏色', style: AppText.caption(size: 11, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: _palette.map((c) => GestureDetector(
                onTap: () => setState(() => _selectedColor = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedColor == c ? AppColors.dark : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  final name = _nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  widget.onAdd(name, _selectedColor);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text('新增', style: AppText.body(size: 14, weight: FontWeight.w600, color: Colors.white))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress Ring ────────────────────────────────────────────────────────────

class _ProgressRing extends StatefulWidget {
  final double progress;
  const _ProgressRing({required this.progress});

  @override
  State<_ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<_ProgressRing> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _anim = Tween<double>(begin: 0, end: widget.progress).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_ProgressRing old) {
    super.didUpdateWidget(old);
    _anim = Tween<double>(begin: _anim.value, end: widget.progress).animate(
      CurvedAnimation(parent: _ctrl..reset(), curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => SizedBox(
        width: 52, height: 52,
        child: Stack(
          children: [
            CustomPaint(
              size: const Size(52, 52),
              painter: _RingPainter(progress: _anim.value),
            ),
            Center(
              child: Text(
                '${(_anim.value * 100).round()}%',
                style: AppText.caption(size: 12, weight: FontWeight.w600, color: AppColors.dark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 20.0;
    const sw = 4.0;

    canvas.drawCircle(center, radius, Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw);

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = AppColors.sage
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

