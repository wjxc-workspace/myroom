import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants.dart';

/// `users/{uid}/note_categories/{id}` — a note's own category (independent of
/// todo categories). Carries an [iconName] (key into `kNoteIconMap`).
class NoteCategory {
  final String id;
  final String label;
  final Color color;
  final String iconName;
  final int sortOrder;

  const NoteCategory({
    required this.id,
    required this.label,
    required this.color,
    this.iconName = '',
    required this.sortOrder,
  });

  factory NoteCategory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return NoteCategory(
      id: doc.id,
      label: (d['label'] as String?) ?? '',
      color: Color((d['colorVal'] as int?) ?? 0xFF9A8A7E),
      iconName: (d['iconName'] as String?) ?? '',
      sortOrder: (d['sortOrder'] as int?) ?? 0,
    );
  }

  /// The permanent `無分類` sentinel (fixed id `undefined`). Matches the
  /// server-provisioned sentinel (label `無分類`, neutral grey).
  static const NoteCategory undefined = NoteCategory(
    id: kUndefinedCategoryId,
    label: '無分類',
    color: Color(0xFF9A8A7E),
    iconName: 'tag',
    sortOrder: 0,
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'colorVal': color.toARGB32(),
    'iconName': iconName,
    'sortOrder': sortOrder,
  };

  NoteCategory copyWith({
    String? id,
    String? label,
    Color? color,
    String? iconName,
    int? sortOrder,
  }) => NoteCategory(
    id: id ?? this.id,
    label: label ?? this.label,
    color: color ?? this.color,
    iconName: iconName ?? this.iconName,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}
