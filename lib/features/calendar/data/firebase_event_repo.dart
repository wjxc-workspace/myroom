import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/app_errors.dart';
import '../../../core/firebase_failure.dart';
import '../../../core/result.dart';
import '../domain/event.dart';
import '../domain/event_repo.dart';
import '../domain/pending_event.dart';

class FirebaseEventRepo implements EventRepo {
  FirebaseEventRepo(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(_uid).collection('events');

  @override
  Stream<List<CalendarEvent>> watchEvents({DateTimeRange? window}) {
    Query<Map<String, dynamic>> q = _col.orderBy('startTime');
    if (window != null) {
      q = q
          .where('startTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(window.start))
          .where('startTime',
              isLessThanOrEqualTo: Timestamp.fromDate(window.end));
    }
    return q
        .snapshots()
        .map((s) => s.docs.map(CalendarEvent.fromFirestore).toList());
  }

  @override
  Future<Result<void>> add(CalendarEvent event) async {
    try {
      await _col.add({
        ...event.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> update(CalendarEvent event) async {
    try {
      await _col.doc(event.id).update(event.toJson());
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await _col.doc(id).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  CollectionReference<Map<String, dynamic>> get _pendingCol =>
      _db.collection('users').doc(_uid).collection('pending_events');

  @override
  Stream<List<PendingEvent>> watchPendingEvents() => _pendingCol
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(PendingEvent.fromFirestore).toList());

  @override
  Future<Result<void>> deletePendingEvent(String id) async {
    try {
      await _pendingCol.doc(id).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }
}
