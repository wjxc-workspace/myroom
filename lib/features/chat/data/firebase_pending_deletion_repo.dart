import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/app_errors.dart';
import '../../../core/firebase_failure.dart';
import '../../../core/result.dart';
import '../domain/pending_deletion.dart';
import '../domain/pending_deletion_repo.dart';

class FirebasePendingDeletionRepo implements PendingDeletionRepo {
  FirebasePendingDeletionRepo(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(_uid).collection('pending_deletions');

  @override
  Stream<List<PendingDeletion>> watchPendingDeletions() => _col
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(PendingDeletion.fromFirestore).toList());

  @override
  Future<Result<void>> confirmPendingDeletion(PendingDeletion deletion) async {
    final path = _targetPath(deletion.type, deletion.targetId);
    if (path == null) {
      // Unknown type — just dismiss the card so it doesn't stick forever.
      return dismissPendingDeletion(deletion.id);
    }
    try {
      await _db.doc(path).delete();
      await _col.doc(deletion.id).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> dismissPendingDeletion(String id) async {
    try {
      await _col.doc(id).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  String? _targetPath(String type, String targetId) => switch (type) {
        'event' => 'users/$_uid/events/$targetId',
        'todo' => 'users/$_uid/todos/$targetId',
        'idea' => 'users/$_uid/ideas/data/user_ideas/$targetId',
        'note' => 'users/$_uid/notes/$targetId',
        _ => null,
      };
}
