import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import '../../../core/app_errors.dart';
import '../../../core/constants.dart';
import '../../../core/firebase_failure.dart';
import '../../../core/result.dart';
import '../domain/idea.dart';
import '../domain/idea_repo.dart';
import '../domain/pinned_resource.dart';

class FirebaseIdeaRepo implements IdeaRepo {
  FirebaseIdeaRepo(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  DocumentReference<Map<String, dynamic>> get _root =>
      _db.collection('users').doc(_uid).collection('ideas').doc(kIdeasRootDocId);

  CollectionReference<Map<String, dynamic>> get _ideasCol =>
      _root.collection('user_ideas');

  CollectionReference<Map<String, dynamic>> get _pinnedCol =>
      _root.collection('pinned_resources');

  static String _docId(String url) =>
      sha1.convert(utf8.encode(url)).toString();

  @override
  Stream<List<Idea>> watchIdeas() => _ideasCol
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Idea.fromFirestore).toList());

  @override
  Future<Result<String>> add(String text) async {
    try {
      final ref = await _ideasCol.add({
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return Ok(ref.id);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> updateText(String id, String text) async {
    try {
      await _ideasCol.doc(id).update({
        'text': text,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> reenrich(String id) async {
    try {
      // Bump a client-writable nonce; the enrichIdea trigger re-runs on its
      // change. aiSummary/aiStatus/links remain fn-only (security rules).
      await _ideasCol.doc(id).update({
        'reenrichAt': FieldValue.serverTimestamp(),
      });
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
      await _ideasCol.doc(id).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Stream<List<PinnedResource>> watchPinnedResources() => _pinnedCol
      .orderBy('sortOrder')
      .snapshots()
      .map((s) => s.docs.map(PinnedResource.fromFirestore).toList());

  @override
  Future<Result<void>> pin(PinnedResource resource) async {
    try {
      await _pinnedCol.doc(_docId(resource.url)).set({
        ...resource.toJson(),
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
  Future<Result<void>> unpin(String url) async {
    try {
      await _pinnedCol.doc(_docId(url)).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }
}
