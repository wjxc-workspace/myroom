import 'package:flutter/material.dart';

class NoteCategory {
  final String id;
  final String label;
  final String iconName; // key into kNoteIconMap in note_page.dart
  final Color color;
  final Color bg;
  final int sortOrder;

  const NoteCategory({
    required this.id,
    required this.label,
    required this.iconName,
    required this.color,
    required this.bg,
    required this.sortOrder,
  });
}

class NoteItem {
  final int id;
  final String dateKey;
  final String content;
  final String? catId; // null = primary date note
  final int updatedAt;

  const NoteItem({
    required this.id,
    required this.dateKey,
    required this.content,
    this.catId,
    required this.updatedAt,
  });
}
