import 'package:cloud_firestore/cloud_firestore.dart';

/// A proposed idea written by the AI chat function, awaiting user confirmation.
/// Lives at `users/{uid}/pending_ideas/{id}`.
class PendingIdea {
  final String id;
  final String text;

  const PendingIdea({required this.id, required this.text});

  factory PendingIdea.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PendingIdea(
      id: doc.id,
      text: (d['text'] as String?) ?? '',
    );
  }
}
