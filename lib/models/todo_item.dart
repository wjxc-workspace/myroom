import 'package:flutter/material.dart';

class TodoItem {
  final int id;
  final String text;
  final bool done;
  final String cat;
  final Color color;
  final int priority;   // 1 = highest … 4 = lowest; done tasks are always last
  final int createdAt;  // milliseconds since epoch

  const TodoItem({
    required this.id,
    required this.text,
    required this.done,
    required this.cat,
    required this.color,
    this.priority = 3,
    this.createdAt = 0,
  });

  TodoItem copyWith({
    int? id,
    String? text,
    bool? done,
    String? cat,
    Color? color,
    int? priority,
    int? createdAt,
  }) =>
      TodoItem(
        id: id ?? this.id,
        text: text ?? this.text,
        done: done ?? this.done,
        cat: cat ?? this.cat,
        color: color ?? this.color,
        priority: priority ?? this.priority,
        createdAt: createdAt ?? this.createdAt,
      );
}

// Custom category (stored in DB + in-memory)
class TodoCategory {
  final int id;
  final String name;
  final Color color;

  const TodoCategory({required this.id, required this.name, required this.color});
}
