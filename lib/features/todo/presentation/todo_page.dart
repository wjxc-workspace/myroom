import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/app_errors.dart';
import '../../../core/constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mr_card.dart';
import '../domain/todo.dart';
import '../domain/todo_category.dart';
import '../domain/todo_repo.dart';

/// Todo tab. Renders INSIDE the app shell (no Scaffold / top bar / title here).
class TodoPage extends StatelessWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TodoRepo>();
    return MultiProvider(
      providers: [
        StreamProvider<List<Todo>>(
          create: (_) => repo.watchTodos(),
          initialData: const [],
          catchError: (_, e) {
            AppErrors.present(e);
            return const <Todo>[];
          },
        ),
        StreamProvider<List<TodoCategory>>(
          create: (_) => repo.watchTodoCategories(),
          initialData: const [],
          catchError: (_, e) {
            AppErrors.present(e);
            return const <TodoCategory>[];
          },
        ),
      ],
      child: const _TodoView(),
    );
  }
}

class _TodoView extends StatefulWidget {
  const _TodoView();

  @override
  State<_TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends State<_TodoView> {
  // null = "全部" (all); otherwise a category id.
  String? _activeCatId;
  bool _showAdd = false;
  bool _showDone = true;

  // Items completed during this view session stay in place (no jump to bottom)
  // until the next rebuild that drops them — mirrors the demo's behavior.
  final Set<String> _justDone = {};

  final _newTextCtrl = TextEditingController();
  final _addFocus = FocusNode();
  // null = "無分類" sentinel; otherwise a custom category id.
  String? _newCatId;

  @override
  void dispose() {
    _newTextCtrl.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  // ── Ordering / filtering ───────────────────────────────────────────────────

  /// Display order: incomplete first, completed last; within each group by
  /// sortOrder. Items just completed this session keep their position.
  List<Todo> _ordered(List<Todo> todos) {
    final items = List<Todo>.from(todos);
    items.sort((a, b) {
      final aDone = a.isCompleted && !_justDone.contains(a.id);
      final bDone = b.isCompleted && !_justDone.contains(b.id);
      if (aDone != bDone) return aDone ? 1 : -1;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return items;
  }

  List<Todo> _filtered(List<Todo> todos) {
    var items = _ordered(todos);
    if (_activeCatId != null) {
      items = items.where((t) => t.category.id == _activeCatId).toList();
    }
    if (!_showDone) {
      items = items.where((t) => !t.isCompleted).toList();
    }
    return items;
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  void _toggle(Todo t) {
    if (!t.isCompleted) {
      _justDone.add(t.id);
    } else {
      _justDone.remove(t.id);
    }
    context.read<TodoRepo>().update(t.copyWith(isCompleted: !t.isCompleted));
  }

  void _addTodo(List<Todo> todos, List<TodoCategory> cats) {
    final text = _newTextCtrl.text.trim();
    if (text.isEmpty) return;

    final TodoCategoryRef catRef;
    if (_newCatId == null || _newCatId == kUndefinedCategoryId) {
      catRef = TodoCategoryRef.undefined;
    } else {
      final picked = cats.where((c) => c.id == _newCatId).firstOrNull;
      catRef = picked == null
          ? TodoCategoryRef.undefined
          : TodoCategoryRef(
              id: picked.id,
              label: picked.label,
              color: picked.color,
            );
    }

    final maxOrder = todos.isEmpty
        ? -1
        : todos.map((t) => t.sortOrder).reduce(max);

    context.read<TodoRepo>().add(
      Todo(
        id: '',
        title: text,
        isCompleted: false,
        sortOrder: maxOrder + 1,
        category: catRef,
      ),
    );

    _newTextCtrl.clear();
    setState(() {
      _showAdd = false;
      _newCatId = null;
    });
  }

  void _onReorder(
    List<Todo> all,
    List<Todo> visible,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<Todo>.from(visible);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    // Splice the reordered visible items back into the full ordered list so
    // reorder() always writes a dense 0..N-1 sortOrder across EVERY todo, not
    // just the filtered subset (Repositories.md §5). Reordering only the visible
    // ids would collide their sortOrder with the hidden todos and scramble the
    // global "全部" order. Hidden todos keep their slots; the visible slots take
    // the new order.
    final full = _ordered(all);
    final visibleIds = visible.map((t) => t.id).toSet();
    var v = 0;
    final orderedIds = [
      for (final t in full)
        visibleIds.contains(t.id) ? reordered[v++].id : t.id,
    ];
    context.read<TodoRepo>().reorder(orderedIds);
  }

  // ── Sheets ─────────────────────────────────────────────────────────────────

  void _showEditSheet(Todo t, List<TodoCategory> cats) {
    final repo = context.read<TodoRepo>();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTodoSheet(
        todo: t,
        categories: cats,
        onSave: (updated) => repo.update(updated),
        onDelete: (id) => repo.delete(id),
      ),
    );
  }

  void _showAddCategorySheet(List<TodoCategory> cats) {
    final repo = context.read<TodoRepo>();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _AddCategorySheet(
        existingCategories: cats,
        onAdd: (name, color) {
          repo.addTodoCategory(
            TodoCategory(
              id: '',
              label: name,
              color: color,
              sortOrder: cats.isEmpty
                  ? 0
                  : cats.map((c) => c.sortOrder).reduce(max) + 1,
            ),
          );
          Navigator.pop(sheetCtx);
        },
        onDelete: (id) => repo.deleteTodoCategory(id),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final todos = context.watch<List<Todo>>();
    final cats = context.watch<List<TodoCategory>>();

    final done = todos.where((t) => t.isCompleted).length;
    final total = todos.length;
    final pct = total > 0 ? done / total : 0.0;
    final items = _filtered(todos);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
                    Text(
                      '今日完成度',
                      style: AppText.body(size: 13, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 3),
                    Text('$done / $total 項任務', style: AppText.caption()),
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
                    horizontal: 12,
                    vertical: 7,
                  ),
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
                _filterChip(label: '全部', catId: null),
                ...cats.map((c) => _filterChip(label: c.label, catId: c.id)),
                GestureDetector(
                  onTap: () => _showAddCategorySheet(cats),
                  child: Container(
                    margin: const EdgeInsets.only(right: 7),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      LucideIcons.plus,
                      size: 14,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Add button at the TOP ──────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _showAdd
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
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
                    const Icon(LucideIcons.plus, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      '新增待辦',
                      style: AppText.label(size: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            secondChild: _buildAddForm(todos, cats),
          ),
          const SizedBox(height: 10),

          // ── Todo list (drag-to-reorder) ─────────────────────────────
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (o, n) => _onReorder(todos, items, o, n),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final t = items[i];
              return _buildTodoItem(t, i, t.isCompleted, cats);
            },
          ),
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required String? catId}) {
    final active = _activeCatId == catId;
    return GestureDetector(
      onTap: () => setState(() => _activeCatId = catId),
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
          label,
          style: AppText.body(
            size: 13,
            weight: FontWeight.w500,
            color: active ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }

  Widget _buildAddForm(List<Todo> todos, List<TodoCategory> cats) {
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
            onSubmitted: (_) => _addTodo(todos, cats),
          ),
          const SizedBox(height: 10),
          Text('類別', style: AppText.caption(size: 11, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              // "無分類" sentinel option (default).
              _CatChip(
                label: '無分類',
                color: AppColors.muted,
                selected:
                    _newCatId == null || _newCatId == kUndefinedCategoryId,
                onTap: () => setState(() => _newCatId = null),
              ),
              ...cats.map(
                (c) => _CatChip(
                  label: c.label,
                  color: c.color,
                  selected: _newCatId == c.id,
                  onTap: () => setState(() => _newCatId = c.id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _addTodo(todos, cats),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '新增',
                        style: AppText.body(
                          size: 13,
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() {
                  _showAdd = false;
                  _newTextCtrl.clear();
                  _newCatId = null;
                }),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.x,
                    size: 16,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodoItem(
    Todo t,
    int index,
    bool isDone,
    List<TodoCategory> cats,
  ) {
    final color = t.category.color;
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('刪除待辦'),
          content: Text('確定要刪除「${t.title}」嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('刪除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
      onDismissed: (_) => context.read<TodoRepo>().delete(t.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          color: AppColors.rose,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.white, size: 20),
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
                onTap: () => _toggle(t),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 23,
                    height: 23,
                    decoration: BoxDecoration(
                      color: isDone ? color : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isDone
                          ? null
                          : Border.all(color: color, width: 2),
                    ),
                    child: isDone
                        ? const Icon(
                            LucideIcons.check,
                            size: 13,
                            color: Colors.white,
                          )
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
                    onTap: () => _showEditSheet(t, cats),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.title,
                              style:
                                  AppText.body(
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
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              t.category.label,
                              style: AppText.caption(size: 10, color: color),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            LucideIcons.gripVertical,
                            size: 14,
                            color: AppColors.muted,
                          ),
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

  const _CatChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

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
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppText.caption(
                size: 12,
                color: selected ? Colors.white : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Edit Todo Sheet ───────────────────────────────────────────────────────────

class _EditTodoSheet extends StatefulWidget {
  final Todo todo;
  final List<TodoCategory> categories;
  final ValueChanged<Todo> onSave;
  final ValueChanged<String> onDelete;

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
  // null = "無分類" sentinel; otherwise a category id.
  late String? _catId;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.todo.title);
    _catId = widget.todo.category.id == kUndefinedCategoryId
        ? null
        : widget.todo.category.id;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  TodoCategoryRef _refFor(String? catId) {
    if (catId == null || catId == kUndefinedCategoryId) {
      return TodoCategoryRef.undefined;
    }
    final found = widget.categories.where((c) => c.id == catId).firstOrNull;
    if (found == null) return TodoCategoryRef.undefined;
    return TodoCategoryRef(
      id: found.id,
      label: found.label,
      color: found.color,
    );
  }

  void _save() {
    if (_ctrl.text.trim().isEmpty) return;
    widget.onSave(
      widget.todo.copyWith(title: _ctrl.text.trim(), category: _refFor(_catId)),
    );
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '編輯待辦',
              style: AppText.body(size: 16, weight: FontWeight.w600),
            ),
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
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
              style: AppText.body(size: 14),
            ),
            const SizedBox(height: 14),
            Text(
              '類別',
              style: AppText.caption(size: 11, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                _CatChip(
                  label: '無分類',
                  color: AppColors.muted,
                  selected: _catId == null,
                  onTap: () => setState(() => _catId = null),
                ),
                ...widget.categories.map(
                  (c) => _CatChip(
                    label: c.label,
                    color: c.color,
                    selected: _catId == c.id,
                    onTap: () => setState(() => _catId = c.id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                        child: Text(
                          '儲存',
                          style: AppText.body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
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
                        content: Text('確定要刪除「${widget.todo.title}」嗎？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              '刪除',
                              style: TextStyle(color: Colors.red),
                            ),
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
                      border: Border.all(
                        color: AppColors.rose.withOpacity(0.6),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      LucideIcons.trash2,
                      size: 16,
                      color: AppColors.rose,
                    ),
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
  final ValueChanged<String> onDelete;

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
    // The "無分類" sentinel is never deletable.
    final deletable = _cats.where((c) => c.id != kUndefinedCategoryId).toList();
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
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '自訂類別',
              style: AppText.body(size: 16, weight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Existing categories (sentinel excluded — not deletable)
            if (deletable.isNotEmpty) ...[
              Text(
                '已建立',
                style: AppText.caption(size: 11, weight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: deletable
                    .map(
                      (c) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: c.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: c.color.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: c.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              c.label,
                              style: AppText.caption(
                                size: 13,
                                color: AppColors.dark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(
                                  () => _cats.removeWhere(
                                    (cat) => cat.id == c.id,
                                  ),
                                );
                                widget.onDelete(c.id);
                              },
                              child: const Icon(
                                LucideIcons.x,
                                size: 13,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 12),
            ],

            // New category form
            Text(
              '新增類別',
              style: AppText.caption(size: 11, weight: FontWeight.w600),
            ),
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
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              style: AppText.body(size: 14),
            ),
            const SizedBox(height: 12),
            Text(
              '選擇顏色',
              style: AppText.caption(size: 11, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _palette
                  .map(
                    (c) => GestureDetector(
                      onTap: () => setState(() => _selectedColor = c),
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
                    ),
                  )
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
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      '新增',
                      style: AppText.body(
                        size: 14,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
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
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _anim = Tween<double>(
      begin: 0,
      end: widget.progress,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_ProgressRing old) {
    super.didUpdateWidget(old);
    _anim = Tween<double>(
      begin: _anim.value,
      end: widget.progress,
    ).animate(CurvedAnimation(parent: _ctrl..reset(), curve: Curves.easeOut));
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
                  color: AppColors.dark,
                ),
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
        ..strokeWidth = sw,
    );

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
