import 'package:cloud_firestore/cloud_firestore.dart';

import 'todo.dart';

/// A proposed todo written by the AI chat function, awaiting user confirmation.
/// Lives at `users/{uid}/pending_todos/{id}`.
class PendingTodo {
  final String id;
  final String title;
  final TodoCategoryRef category;

  const PendingTodo({
    required this.id,
    required this.title,
    required this.category,
  });

  factory PendingTodo.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PendingTodo(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      category: TodoCategoryRef.fromMap(d['category'] as Map<String, dynamic>?),
    );
  }

  Todo toTodo(int sortOrder) => Todo(
        id: '',
        title: title,
        isCompleted: false,
        sortOrder: sortOrder,
        category: category,
      );
}
