import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants.dart';

/// A denormalized snapshot of the note's category embedded in `notes/{id}`.
/// Refreshed by the `categoryFanout` Cloud Function when the source category
/// changes.
class NoteCategoryRef {
  final String id;
  final String label;
  final Color color;
  final String iconName;

  const NoteCategoryRef({
    required this.id,
    required this.label,
    required this.color,
    this.iconName = '',
  });

  /// The `無分類` sentinel reference used as the default for new notes.
  /// Matches the server-provisioned sentinel (label `無分類`, neutral grey) so a
  /// note written via the fallback path carries the canonical snapshot.
  static const NoteCategoryRef undefined = NoteCategoryRef(
    id: kUndefinedCategoryId,
    label: '無分類',
    color: Color(0xFF9A8A7E),
    iconName: 'tag',
  );

  factory NoteCategoryRef.fromMap(Map<String, dynamic>? m) {
    if (m == null) return undefined;
    return NoteCategoryRef(
      id: (m['id'] as String?) ?? kUndefinedCategoryId,
      label: (m['label'] as String?) ?? '無分類',
      color: Color((m['colorVal'] as int?) ?? 0xFF9A8A7E),
      iconName: (m['iconName'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'colorVal': color.toARGB32(),
    'iconName': iconName,
  };
}

/// One attachment entry stored inside `notes/{id}.attachments[]`.
/// Stores `storagePath` only — the UI resolves a download URL on demand.
/// `attId` = `sha256(bytes)` hex, the join key to `extracted_texts/{attId}`.
class NoteAttachment {
  final String type; // image | audio | file
  final String filename;
  final String storagePath;
  final String attId;

  const NoteAttachment({
    required this.type,
    required this.filename,
    required this.storagePath,
    required this.attId,
  });

  factory NoteAttachment.fromMap(Map<String, dynamic> m) => NoteAttachment(
    type: (m['type'] as String?) ?? 'file',
    filename: (m['filename'] as String?) ?? '',
    storagePath: (m['storagePath'] as String?) ?? '',
    attId: (m['attId'] as String?) ?? '',
  );

  Map<String, dynamic> toMap() => {
    'type': type,
    'filename': filename,
    'storagePath': storagePath,
    'attId': attId,
  };
}

/// A freshly picked / recorded attachment, built by the page from picked files
/// and passed to [NoteRepo.add]. Not yet uploaded.
class PendingAttachment {
  final Uint8List bytes;
  final String type; // image | audio | file
  final String filename;
  final String ext;
  final String? extractedText;

  const PendingAttachment({
    required this.bytes,
    required this.type,
    required this.filename,
    required this.ext,
    this.extractedText,
  });
}

/// `users/{uid}/notes/{id}`.
class Note {
  final String id;
  final String dateKey; // YYYY-MM-DD
  final String title;
  final String content;
  final NoteCategoryRef category;
  final List<NoteAttachment> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.dateKey,
    this.title = '無標題',
    required this.content,
    this.category = NoteCategoryRef.undefined,
    this.attachments = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawAttachments = (d['attachments'] as List<dynamic>?) ?? const [];
    return Note(
      id: doc.id,
      dateKey: (d['dateKey'] as String?) ?? '',
      title: (d['title'] as String?) ?? '無標題',
      content: (d['content'] as String?) ?? '',
      category: NoteCategoryRef.fromMap(
        (d['category'] as Map<String, dynamic>?),
      ),
      attachments: rawAttachments
          .map((a) => NoteAttachment.fromMap(a as Map<String, dynamic>))
          .toList(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Client-writable data fields only. The repo injects createdAt/updatedAt.
  Map<String, dynamic> toJson() => {
    'dateKey': dateKey,
    'title': title,
    'content': content,
    'category': category.toMap(),
    'attachments': attachments.map((a) => a.toMap()).toList(),
  };

  Note copyWith({
    String? id,
    String? dateKey,
    String? title,
    String? content,
    NoteCategoryRef? category,
    List<NoteAttachment>? attachments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Note(
    id: id ?? this.id,
    dateKey: dateKey ?? this.dateKey,
    title: title ?? this.title,
    content: content ?? this.content,
    category: category ?? this.category,
    attachments: attachments ?? this.attachments,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
