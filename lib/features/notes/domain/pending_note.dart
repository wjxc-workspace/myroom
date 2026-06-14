import 'package:cloud_firestore/cloud_firestore.dart';

import 'note.dart';

/// A proposed note written by the AI chat function, awaiting user confirmation.
/// Lives at `users/{uid}/pending_notes/{id}`.
class PendingNote {
  final String id;
  final String dateKey;
  final String content;

  const PendingNote({
    required this.id,
    required this.dateKey,
    required this.content,
  });

  factory PendingNote.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PendingNote(
      id: doc.id,
      dateKey: (d['dateKey'] as String?) ?? '',
      content: (d['content'] as String?) ?? '',
    );
  }

  Note toNote() => Note(
        id: '',
        dateKey: dateKey,
        title: '無標題',
        content: content,
        category: NoteCategoryRef.undefined,
        attachments: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}
