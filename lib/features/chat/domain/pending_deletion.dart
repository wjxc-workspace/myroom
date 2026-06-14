import 'package:cloud_firestore/cloud_firestore.dart';

/// A proposed deletion written by the AI chat function, awaiting user
/// confirmation. Lives at `users/{uid}/pending_deletions/{id}`.
///
/// [type] is one of `'event'`, `'todo'`, `'idea'`, `'note'`.
class PendingDeletion {
  final String id;
  final String type;
  final String targetId;
  final String displayTitle;

  const PendingDeletion({
    required this.id,
    required this.type,
    required this.targetId,
    required this.displayTitle,
  });

  factory PendingDeletion.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PendingDeletion(
      id: doc.id,
      type: (d['type'] as String?) ?? '',
      targetId: (d['targetId'] as String?) ?? '',
      displayTitle: (d['displayTitle'] as String?) ?? '',
    );
  }
}
