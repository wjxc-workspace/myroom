import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../models/todo_item.dart';
import '../widgets/mr_card.dart';
import '../widgets/mr_add_row.dart';

class TodoPage extends StatefulWidget {
  final List<TodoItem> todos;
  final ValueChanged<TodoItem> onTodoAdded;
  final ValueChanged<TodoItem> onTodoToggled;

  const TodoPage({
    super.key,
    required this.todos,
    required this.onTodoAdded,
    required this.onTodoToggled,
  });

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  String _activeCat = '全部';
  bool _showAdd = false;
  final _newTextCtrl = TextEditingController();
  String _newCat = '工作';
  final _addFocus = FocusNode();

  static const _cats = ['全部', '工作', '學習', '個人', '健康'];
  static const _catColors = {
    '工作': AppColors.blue,
    '學習': AppColors.sage,
    '個人': AppColors.rose,
    '健康': AppColors.amber,
  };

  @override
  void dispose() {
    _newTextCtrl.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _toggleTodo(int id) {
    final todo = widget.todos.firstWhere((t) => t.id == id);
    widget.onTodoToggled(todo.copyWith(done: !todo.done));
  }

  void _addTodo() {
    if (_newTextCtrl.text.isEmpty) return;
    widget.onTodoAdded(TodoItem(
      id: 0,
      text: _newTextCtrl.text,
      done: false,
      cat: _newCat,
      color: _catColors[_newCat]!,
    ));
    _newTextCtrl.clear();
    setState(() => _showAdd = false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _activeCat == '全部'
        ? widget.todos
        : widget.todos.where((t) => t.cat == _activeCat).toList();
    final done = widget.todos.where((t) => t.done).length;
    final total = widget.todos.length;
    final pct = total > 0 ? done / total : 0.0;

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

          // Category filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _cats.map((cat) {
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
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Todo list
          ...filtered.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: MrCard(
              onTap: () => _toggleTodo(t.id),
              child: Row(
                children: [
                  // Checkbox
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 23,
                    height: 23,
                    decoration: BoxDecoration(
                      color: t.done ? t.color : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: t.done ? null : Border.all(color: t.color, width: 2),
                    ),
                    child: t.done
                        ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.text,
                      style: AppText.body(
                        size: 14,
                        weight: FontWeight.w500,
                        color: t.done ? AppColors.dark.withOpacity(0.5) : AppColors.dark,
                      ).copyWith(
                        decoration: t.done ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.muted,
                      ),
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
          )),

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
                  Wrap(
                    spacing: 7,
                    children: _catColors.entries.map((e) {
                      final active = _newCat == e.key;
                      return GestureDetector(
                        onTap: () => setState(() => _newCat = e.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: active ? AppColors.dark : AppColors.bg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            e.key,
                            style: AppText.caption(
                              size: 12,
                              color: active ? Colors.white : AppColors.muted,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
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
