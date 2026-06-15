import '../../../core/result.dart';
import 'note.dart';
import 'note_category.dart';

abstract class NoteRepo {
  /// Streams notes. When [dateKey] is provided, only that day's notes
  /// (createdAt desc); otherwise all notes ordered by dateKey then createdAt.
  Stream<List<Note>> watchNotes({String? dateKey});

  /// Streams the notes embedding [catId] (createdAt desc).
  Stream<List<Note>> watchNotesByCategory(String catId);

  /// Streams the set of dateKeys with ≥1 note (for calendar dot indicators).
  Stream<Set<String>> watchNoteDateKeys();

  /// Creates a new note, uploading any [attachments] first. Returns the new id.
  Future<Result<String>> add(Note note, {List<PendingAttachment> attachments});

  /// Updates [note]. Uploads any newly picked [added] attachments and merges
  /// them onto [note.attachments] (the kept existing set); [removed] existing
  /// attachments have their Storage object + `extracted_texts` doc cleaned up.
  Future<Result<void>> update(
    Note note, {
    List<PendingAttachment> added,
    List<NoteAttachment> removed,
  });

  Future<Result<void>> delete(String id);

  /// Sets the embedded category snapshot on a note (no AI in Phase 1).
  Future<Result<void>> setCategory(String id, NoteCategoryRef category);

  // ── Note categories ───────────────────────────────────────────────────────

  Stream<List<NoteCategory>> watchNoteCategories();

  /// Creates a category and returns its new document id.
  Future<Result<String>> addNoteCategory(NoteCategory category);

  Future<Result<void>> updateNoteCategory(NoteCategory category);

  /// Deletes only the category doc; `categoryFanout` reassigns affected notes
  /// to the `無分類` sentinel.
  Future<Result<void>> deleteNoteCategory(String id);
}
