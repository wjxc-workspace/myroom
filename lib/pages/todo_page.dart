import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../models/todo_item.dart';
import '../widgets/mr_card.dart';

class TodoPage extends StatefulWidget {
  final List<TodoItem> todos;
  final List<TodoCategory> categories;
  final bool isActive;
  final ValueChanged<TodoItem> onTodoAdded;
  final ValueChanged<TodoItem> onTodoToggled;
  final ValueChanged<int> onTodoDeleted;
  final ValueChanged<TodoItem> onTodoEdited;
  final ValueChanged<List<int>> onTodosReordered;
  final void Function(String name, Color color) onCategoryAdded;
  final ValueChanged<int> onCategoryDeleted;

  const TodoPage({
    super.key,
    required this.todos,
    required this.categories,
    required this.isActive,
    required this.onTodoAdded,
    required this.onTodoToggled,
    required this.onTodoDeleted,
    required this.onTodoEdited,
    required this.onTodosReordered,
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

  // Stable display order: IDs in the order they should be shown.
  // Done items start at the bottom; newly-completed items stay in place
  // (with strikethrough) until next initState.
  late List<int> _displayIds;
  final Set<int> _justDone = {}; // marked done this session → stay in place

  final _newTextCtrl = TextEditingController();
  final _addFocus = FocusNode();
  late String _newCat;

  @override
  void initState() {
    super.initState();
    _initDisplayOrder();
    _newCat =
        widget.categories.isNotEmpty ? widget.categories.first.name : '';
  }

  @override
  void didUpdateWidget(TodoPage old) {
    super.didUpdateWidget(old);
    _syncDisplayOrder(old.todos);
    // When tab becomes active again, move done items to bottom.
    if (!old.isActive && widget.isActive) {
      _resetDoneOrder();
    }
    // Keep _newCat valid
    if (widget.categories.isNotEmpty &&
        !widget.categories.any((c) => c.name == _newCat)) {
      _newCat = widget.categories.first.name;
    }
  }

  // Move all done items to the bottom; clear the in-session tracking set.
  void _resetDoneOrder() {
    final todoMap = {for (final t in widget.todos) t.id: t};
    final active = _displayIds
        .where((id) => todoMap[id] != null && !todoMap[id]!.done)
        .toList();
    final done = _displayIds
        .where((id) => todoMap[id] != null && todoMap[id]!.done)
        .toList();
    _displayIds = [...active, ...done];
    _justDone.clear();
  }

  @override
  void dispose() {
    _newTextCtrl.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  // Build display order fresh: active items sorted by priority, then done.
  void _initDisplayOrder() {
    final active = widget.todos.where((t) => !t.done).toList()
      ..sort((a, b) => a.priority != b.priority
          ? a.priority.compareTo(b.priority)
          : a.createdAt.compareTo(b.createdAt));
    final done = widget.todos.where((t) => t.done).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _displayIds = [
      ...active.map((t) => t.id),
      ...done.map((t) => t.id),
    ];
  }

  // Keep _displayIds in sync when widget.todos changes (add/delete).
  void _syncDisplayOrder(List<TodoItem> oldTodos) {
    final currentMap = {for (var t in widget.todos) t.id: t};
    final oldIds = {for (var t in oldTodos) t.id};

    // Remove deleted IDs
    _displayIds.removeWhere((id) => !currentMap.containsKey(id));
    _justDone.removeWhere((id) => !currentMap.containsKey(id));

    // Append newly added IDs before the first "genuinely done" item.
    final existingIds = _displayIds.toSet();
    for (final t in widget.todos) {
      if (!oldIds.contains(t.id) && !existingIds.contains(t.id)) {
        final insertPos = _displayIds.indexWhere((id) {
          final todo = currentMap[id];
          return todo != null && todo.done && !_justDone.contains(id);
        });
        if (insertPos == -1) {
          _displayIds.add(t.id);
        } else {
          _displayIds.insert(insertPos, t.id);
        }
        existingIds.add(t.id);
      }
    }
  }

  List<String> get _allCatNames =>
      ['全部', ...widget.categories.map((c) => c.name)];

  Color _colorForCat(String cat) {
    final found = widget.categories.where((c) => c.name == cat).firstOrNull;
    return found?.color ?? AppColors.muted;
  }

  // Ordered, filtered list of todos for the current view.
  List<TodoItem> get _sorted {
    final todoMap = {for (var t in widget.todos) t.id: t};
    var items = _displayIds
        .where((id) => todoMap.containsKey(id))
        .map((id) => todoMap[id]!)
        .where((t) => _activeCat == '全部' || t.cat == _activeCat)
        .toList();
    if (!_showDone) items = items.where((t) => !t.done).toList();
    return items;
  }

  // Toggle: newly-done items stay in place (added to _justDone).
  void _toggleTodo(int id) {
    final todo = widget.todos.firstWhere((t) => t.id == id);
    if (!todo.done) {
      setState(() => _justDone.add(id));
    } else {
      setState(() => _justDone.remove(id));
    }
    widget.onTodoToggled(todo.copyWith(done: !todo.done));
  }

  void _addTodo() {
    if (_newTextCtrl.text.trim().isEmpty) return;
    final cat =
        _newCat.isNotEmpty ? _newCat : (widget.categories.isNotEmpty ? widget.categories.first.name : '其他');
    widget.onTodoAdded(TodoItem(
      id: 0,
      text: _newTextCtrl.text.trim(),
      done: false,
      cat: cat,
      color: _colorForCat(cat),
      priority: widget.todos.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _newTextCtrl.clear();
    setState(() => _showAdd = false);
  }

  // Drag-to-reorder: update _displayIds and persist.
  void _onReorder(int oldIndex, int newIndex) {
    final items = _sorted; // snapshot before setState
    if (newIndex > oldIndex) newIndex -= 1;

    final reorderedItems = List<TodoItem>.from(items);
    final moved = reorderedItems.removeAt(oldIndex);
    reorderedItems.insert(newIndex, moved);

    final sortedOldIds = items.map((t) => t.id).toSet();
    final newSortedIds = reorderedItems.map((t) => t.id).toList();

    setState(() {
      int idx = 0;
      _displayIds = _displayIds.map((id) {
        if (sortedOldIds.contains(id)) return newSortedIds[idx++];
        return id;
      }).toList();
    });

    widget.onTodosReordered(List<int>.from(_displayIds));
  }

  void _showEditSheet(TodoItem t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTodoSheet(
        todo: t,
        categories: widget.categories,
        onSave: (updated) => widget.onTodoEdited(updated),
        onDelete: (id) => widget.onTodoDeleted(id),
      ),
    );
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
        onDelete: (id) => widget.onCategoryDeleted(id),
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
                    Text('今日完成度',
                        style: AppText.body(
                            size: 13, weight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text('$done / $total 項任務',
                        style: AppText.caption()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Show-done toggle
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showDone = !_showDone),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _showDone ? AppColors.dark : AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [kCardShadow],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showDone ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 13,
                        color: _showDone ? Colors.white : AppColors.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _showDone ? '顯示已完成' : '隱藏已完成',
                        style: AppText.caption(
                          size: 12,
                          weight: FontWeight.w500,
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? AppColors.dark : AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: active
                            ? const [kBtnShadow]
                            : const [kCardShadow],
                      ),
                      child: Text(
                        cat,
                        style: AppText.body(
                          size: 13,
                          weight: FontWeight.w500,
                          color:
                              active ? Colors.white : AppColors.muted,
                        ),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: _showAddCategorySheet,
                  child: Container(
                    margin: const EdgeInsets.only(right: 7),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(LucideIcons.plus,
                        size: 14, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Add button at the TOP ──────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState:
                _showAdd ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: GestureDetector(
              onTap: () {
                setState(() => _showAdd = true);
                Future.microtask(() => _addFocus.requestFocus());
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.dark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.plus,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('新增待辦',
                        style: AppText.label(
                            size: 13, color: Colors.white)),
                  ],
                ),
              ),
            ),
            secondChild: _buildAddForm(),
          ),
          const SizedBox(height: 10),

          // ── Todo list (drag-to-reorder) ─────────────────────────────
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: _onReorder,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final t = items[i];
              final isDone = t.done;
              return _buildTodoItem(t, i, isDone);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAddForm() {
    return MrCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _newTextCtrl,
            focusNode: _addFocus,
            maxLines: 2,
            scrollPadding: const EdgeInsets.only(bottom: 120.0),
            decoration: InputDecoration(
              hintText: '新增任務...',
              hintStyle: AppText.body(color: AppColors.muted),
              border: InputBorder.none,
            ),
            style: AppText.body(size: 14),
            onSubmitted: (_) => _addTodo(),
          ),
          const SizedBox(height: 10),
          Text('類別',
              style: AppText.caption(
                  size: 11, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: widget.categories
                .map((c) => _CatChip(
                      label: c.name,
                      color: c.color,
                      selected: _newCat == c.name,
                      onTap: () => setState(() => _newCat = c.name),
                    ))
                .toList(),
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
                      child: Text('新增',
                          style: AppText.body(
                              size: 13,
                              weight: FontWeight.w600,
                              color: Colors.white)),
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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.x,
                      size: 16, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodoItem(TodoItem t, int index, bool isDone) {
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('刪除待辦'),
          content: Text('確定要刪除「${t.text}」嗎？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('刪除',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
      onDismissed: (_) => widget.onTodoDeleted(t.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          color: AppColors.rose,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(LucideIcons.trash2,
            color: Colors.white, size: 20),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [kCardShadow],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Checkbox (only tap to toggle) ──────────────────────
              GestureDetector(
                onTap: () => _toggleTodo(t.id),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 23,
                    height: 23,
                    decoration: BoxDecoration(
                      color: isDone ? t.color : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isDone
                          ? null
                          : Border.all(color: t.color, width: 2),
                    ),
                    child: isDone
                        ? const Icon(LucideIcons.check,
                            size: 13, color: Colors.white)
                        : null,
                  ),
                ),
              ),
              // ── Content area (long-press = drag, tap = edit) ───────
              Expanded(
                child: ReorderableDelayedDragStartListener(
                  index: index,
                  enabled: !isDone,
                  child: GestureDetector(
                    onTap: () => _showEditSheet(t),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.text,
                              style: AppText.body(
                                size: 14,
                                weight: FontWeight.w500,
                                color: isDone
                                    ? AppColors.dark.withOpacity(0.4)
                                    : AppColors.dark,
                              ).copyWith(
                                decoration: isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: AppColors.muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: t.color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              t.cat,
                              style: AppText.caption(
                                  size: 10, color: t.color),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(LucideIcons.gripVertical,
                              size: 14,
                              color: AppColors.muted),
                          const SizedBox(width: 10),
                        ],
                      ),
                    ),
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

// ─── Category Chip ─────────────────────────────────────────────────────────────

class _CatChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CatChip(
      {required this.label,
      required this.color,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.dark : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppText.caption(
                  size: 12,
                  color: selected ? Colors.white : AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Edit Todo Sheet ───────────────────────────────────────────────────────────

class _EditTodoSheet extends StatefulWidget {
  final TodoItem todo;
  final List<TodoCategory> categories;
  final ValueChanged<TodoItem> onSave;
  final ValueChanged<int> onDelete;

  const _EditTodoSheet({
    required this.todo,
    required this.categories,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_EditTodoSheet> createState() => _EditTodoSheetState();
}

class _EditTodoSheetState extends State<_EditTodoSheet> {
  late final TextEditingController _ctrl;
  late String _cat;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.todo.text);
    _cat = widget.todo.cat;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _colorForCat(String cat) {
    final found =
        widget.categories.where((c) => c.name == cat).firstOrNull;
    return found?.color ?? widget.todo.color;
  }

  void _save() {
    if (_ctrl.text.trim().isEmpty) return;
    widget.onSave(widget.todo.copyWith(
      text: _ctrl.text.trim(),
      cat: _cat,
      color: _colorForCat(_cat),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 20),
            Text('編輯待辦',
                style:
                    AppText.body(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '任務內容',
                hintStyle: AppText.body(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
              ),
              style: AppText.body(size: 14),
            ),
            const SizedBox(height: 14),
            if (widget.categories.isNotEmpty) ...[
              Text('類別',
                  style: AppText.caption(
                      size: 11, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: widget.categories
                    .map((c) => _CatChip(
                          label: c.name,
                          color: c.color,
                          selected: _cat == c.name,
                          onTap: () => setState(() => _cat = c.name),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: AppColors.dark,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text('儲存',
                            style: AppText.body(
                                size: 14,
                                weight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () async {
                    final nav = Navigator.of(context);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('刪除待辦'),
                        content: Text('確定要刪除「${widget.todo.text}」嗎？'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('刪除',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      widget.onDelete(widget.todo.id);
                      nav.pop();
                    }
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.rose.withOpacity(0.6)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(LucideIcons.trash2,
                        size: 16, color: AppColors.rose),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Category Sheet ────────────────────────────────────────────────────────

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
  // Local list — updated immediately when a category is deleted.
  late List<TodoCategory> _cats;

  static const _palette = [
    AppColors.sage,
    AppColors.amber,
    AppColors.blue,
    AppColors.rose,
    AppColors.dark,
    Color(0xFF9B7EDE),
    Color(0xFF4CAF50),
    Color(0xFFFF7043),
    Color(0xFF26C6DA),
    Color(0xFFEC407A),
  ];

  @override
  void initState() {
    super.initState();
    _cats = List.of(widget.existingCategories);
  }

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
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 20),
            Text('自訂類別',
                style:
                    AppText.body(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 16),

            // Existing categories
            if (_cats.isNotEmpty) ...[
              Text('已建立',
                  style: AppText.caption(
                      size: 11, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _cats
                    .map((c) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: c.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: c.color.withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: c.color,
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(c.name,
                                  style: AppText.caption(
                                      size: 13,
                                      color: AppColors.dark)),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  // Update sheet immediately, then propagate to DB.
                                  setState(() => _cats
                                      .removeWhere((cat) => cat.id == c.id));
                                  widget.onDelete(c.id);
                                },
                                child: const Icon(LucideIcons.x,
                                    size: 13, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 12),
            ],

            // New category form
            Text('新增類別',
                style: AppText.caption(
                    size: 11, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: '類別名稱',
                hintStyle: AppText.body(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
              style: AppText.body(size: 14),
            ),
            const SizedBox(height: 12),
            Text('選擇顏色',
                style: AppText.caption(
                    size: 11, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _palette
                  .map((c) => GestureDetector(
                        onTap: () =>
                            setState(() => _selectedColor = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedColor == c
                                  ? AppColors.dark
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
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
                  decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(14)),
                  child: Center(
                    child: Text('新增',
                        style: AppText.body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress Ring ─────────────────────────────────────────────────────────────

class _ProgressRing extends StatefulWidget {
  final double progress;
  const _ProgressRing({required this.progress});

  @override
  State<_ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<_ProgressRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _anim = Tween<double>(begin: 0, end: widget.progress).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_ProgressRing old) {
    super.didUpdateWidget(old);
    _anim = Tween<double>(begin: _anim.value, end: widget.progress)
        .animate(
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
        width: 52,
        height: 52,
        child: Stack(
          children: [
            CustomPaint(
              size: const Size(52, 52),
              painter: _RingPainter(progress: _anim.value),
            ),
            Center(
              child: Text(
                '${(_anim.value * 100).round()}%',
                style: AppText.caption(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.dark),
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

    canvas.drawCircle(
        center,
        radius,
        Paint()
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
