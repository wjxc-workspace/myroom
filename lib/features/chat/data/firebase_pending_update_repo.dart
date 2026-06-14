import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/app_errors.dart';
import '../../../core/firebase_failure.dart';
import '../../../core/result.dart';
import '../domain/pending_update.dart';
import '../domain/pending_update_repo.dart';

class FirebasePendingUpdateRepo implements PendingUpdateRepo {
  FirebasePendingUpdateRepo(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(_uid).collection('pending_updates');

  @override
  Stream<List<PendingUpdate>> watchPendingUpdates() => _col
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(PendingUpdate.fromFirestore).toList());

  @override
  Future<Result<void>> confirmPendingUpdate(PendingUpdate update) async {
    final path = _targetPath(update.type, update.targetId);
    if (path == null) return dismissPendingUpdate(update.id);
    try {
      final updateMap = Map<String, dynamic>.from(update.updateData);
      // Events have no updatedAt; todos and notes do.
      if (update.type != 'event') {
        updateMap['updatedAt'] = FieldValue.serverTimestamp();
      }
      await _db.doc(path).update(updateMap);
      await _col.doc(update.id).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> dismissPendingUpdate(String id) async {
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
        'note' => 'users/$_uid/notes/$targetId',
        _ => null,
      };
}
