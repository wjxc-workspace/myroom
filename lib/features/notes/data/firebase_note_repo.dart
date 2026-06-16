import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import '../../../core/app_errors.dart';
import '../../../core/firebase_failure.dart';
import '../../../core/result.dart';
import '../../../shared/storage/storage_repo.dart';
import '../domain/note.dart';
import '../domain/note_category.dart';
import '../domain/note_repo.dart';

class FirebaseNoteRepo implements NoteRepo {
  FirebaseNoteRepo(this._db, this._uid, this._storage);

  final FirebaseFirestore _db;
  final String _uid;
  final StorageRepo _storage;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(_uid).collection('notes');

  CollectionReference<Map<String, dynamic>> get _catCol =>
      _db.collection('users').doc(_uid).collection('note_categories');

  // ── Notes ───────────────────────────────────────────────────────────────

  @override
  Stream<List<Note>> watchNotes({String? dateKey}) {
    final Query<Map<String, dynamic>> query;
    if (dateKey != null) {
      query = _col
          .where('dateKey', isEqualTo: dateKey)
          .orderBy('createdAt', descending: true);
    } else {
      query = _col.orderBy('dateKey').orderBy('createdAt', descending: true);
    }
    return query
        .snapshots()
        .map((s) => s.docs.map(Note.fromFirestore).toList());
  }

  @override
  Stream<List<Note>> watchNotesByCategory(String catId) => _col
      .where('category.id', isEqualTo: catId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Note.fromFirestore).toList());

  @override
  Stream<Note?> watchNote(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Note.fromFirestore(d) : null);

  @override
  Stream<Set<String>> watchNoteDateKeys() => _col.snapshots().map(
        (s) => s.docs
            .map((d) => (d.data()['dateKey'] as String?) ?? '')
            .where((k) => k.isNotEmpty)
            .toSet(),
      );

  @override
  Future<Result<String>> add(
    Note note, {
    List<PendingAttachment> attachments = const [],
  }) async {
    try {
      final ref = _col.doc();
      final noteId = ref.id;

      final uploaded = <NoteAttachment>[];
      final extractedWrites = <(String attId, String filename, String summary)>[];

      for (final a in attachments) {
        final attId = sha256.convert(a.bytes).toString();
        final path = 'users/$_uid/notes/$noteId/$attId.${a.ext}';
        final up = await _storage.upload(
          uid: _uid,
          path: path,
          bytes: a.bytes,
          contentType: _contentType(a.type, a.ext),
        );
        switch (up) {
          case Ok(value: final file):
            uploaded.add(NoteAttachment(
              type: a.type,
              filename: a.filename,
              storagePath: file.storagePath,
              attId: attId,
            ));
            if (a.extractedText != null && a.type != 'image') {
              extractedWrites
                  .add((attId, a.filename, a.extractedText!));
            }
          case Err(failure: final f):
            // Upload error already surfaced by StorageRepo; abort the add.
            return Err(f);
        }
      }

      final noteWithAttachments = note.copyWith(attachments: uploaded);
      await ref.set({
        ...noteWithAttachments.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final w in extractedWrites) {
        await ref
            .collection('extracted_texts')
            .doc(w.$1)
            .set({'filename': w.$2, 'summary': w.$3});
      }

      return Ok(noteId);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> update(
    Note note, {
    List<PendingAttachment> added = const [],
    List<NoteAttachment> removed = const [],
  }) async {
    try {
      final ref = _col.doc(note.id);

      // Upload newly picked attachments first; abort the update on failure.
      final uploaded = <NoteAttachment>[];
      final extractedWrites = <(String attId, String filename, String summary)>[];
      for (final a in added) {
        final attId = sha256.convert(a.bytes).toString();
        final path = 'users/$_uid/notes/${note.id}/$attId.${a.ext}';
        final up = await _storage.upload(
          uid: _uid,
          path: path,
          bytes: a.bytes,
          contentType: _contentType(a.type, a.ext),
        );
        switch (up) {
          case Ok(value: final file):
            uploaded.add(NoteAttachment(
              type: a.type,
              filename: a.filename,
              storagePath: file.storagePath,
              attId: attId,
            ));
            if (a.extractedText != null && a.type != 'image') {
              extractedWrites.add((attId, a.filename, a.extractedText!));
            }
          case Err(failure: final f):
            return Err(f);
        }
      }

      final merged = note.copyWith(
        attachments: [...note.attachments, ...uploaded],
      );
      await ref.update({
        ...merged.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final w in extractedWrites) {
        await ref
            .collection('extracted_texts')
            .doc(w.$1)
            .set({'filename': w.$2, 'summary': w.$3});
      }

      // `storageCascade` only runs on note delete, so removed attachments must
      // be cleaned up here (best-effort — the object normally exists).
      for (final r in removed) {
        if (r.storagePath.isNotEmpty) await _storage.delete(r.storagePath);
        if (r.attId.isNotEmpty) {
          try {
            await ref.collection('extracted_texts').doc(r.attId).delete();
          } catch (_) {}
        }
      }

      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    // Storage bytes + extracted_texts are cleaned by the `storageCascade`
    // Cloud Function (onDelete) — never delete Storage here.
    try {
      await _col.doc(id).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> setCategory(String id, NoteCategoryRef category) async {
    try {
      await _col.doc(id).update({
        'category': category.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  // ── Note categories ───────────────────────────────────────────────────────

  @override
  Stream<List<NoteCategory>> watchNoteCategories() => _catCol
      .orderBy('sortOrder')
      .snapshots()
      .map((s) => s.docs.map(NoteCategory.fromFirestore).toList());

  @override
  Future<Result<String>> addNoteCategory(NoteCategory category) async {
    try {
      final ref = await _catCol.add(category.toJson());
      return Ok(ref.id);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> updateNoteCategory(NoteCategory category) async {
    try {
      await _catCol.doc(category.id).update(category.toJson());
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  @override
  Future<Result<void>> deleteNoteCategory(String id) async {
    // Only the category doc; `categoryFanout` reassigns notes to `無分類`.
    try {
      await _catCol.doc(id).delete();
      return const Ok(null);
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _contentType(String type, String ext) {
    switch (type) {
      case 'image':
        switch (ext) {
          case 'jpg':
          case 'jpeg':
            return 'image/jpeg';
          case 'png':
            return 'image/png';
          case 'gif':
            return 'image/gif';
          case 'webp':
            return 'image/webp';
          default:
            return 'image/$ext';
        }
      case 'audio':
        switch (ext) {
          case 'm4a':
            return 'audio/mp4';
          case 'mp3':
            return 'audio/mpeg';
          case 'wav':
            return 'audio/wav';
          case 'ogg':
            return 'audio/ogg';
          default:
            return 'audio/$ext';
        }
      default:
        switch (ext) {
          case 'pdf':
            return 'application/pdf';
          case 'txt':
            return 'text/plain';
          case 'md':
            return 'text/markdown';
          default:
            return 'application/octet-stream';
        }
    }
  }
}
