import 'package:flutter/material.dart';

class TodoItem {
  final int id;
  final String text;
  final bool done;
  final String cat;
  final Color color;

  const TodoItem({
    required this.id,
    required this.text,
    required this.done,
    required this.cat,
    required this.color,
  });

  TodoItem copyWith({
    int? id,
    String? text,
    bool? done,
    String? cat,
    Color? color,
  }) =>
      TodoItem(
        id: id ?? this.id,
        text: text ?? this.text,
        done: done ?? this.done,
        cat: cat ?? this.cat,
        color: color ?? this.color,
      );
}
