import 'package:cloud_firestore/cloud_firestore.dart';

/// A proposed field-level update written by the AI chat function, awaiting
/// user confirmation. Lives at `users/{uid}/pending_updates/{id}`.
///
/// [type] is one of `'event'`, `'todo'`, `'note'`.
/// [updateData] is passed directly to Firestore `.update()` on confirm.
class PendingUpdate {
  final String id;
  final String type;
  final String targetId;
  final String displayTitle;
  final String changeDescription;
  final Map<String, dynamic> updateData;

  const PendingUpdate({
    required this.id,
    required this.type,
    required this.targetId,
    required this.displayTitle,
    required this.changeDescription,
    required this.updateData,
  });

  factory PendingUpdate.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PendingUpdate(
      id: doc.id,
      type: (d['type'] as String?) ?? '',
      targetId: (d['targetId'] as String?) ?? '',
      displayTitle: (d['displayTitle'] as String?) ?? '',
      changeDescription: (d['changeDescription'] as String?) ?? '',
      updateData:
          Map<String, dynamic>.from(d['updateData'] as Map? ?? const {}),
    );
  }
}
