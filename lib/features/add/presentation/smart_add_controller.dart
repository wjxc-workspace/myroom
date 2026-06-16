import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/app_errors.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/ai/domain/ai_service.dart';
import '../../../shared/ai/domain/classification.dart';
import '../../calendar/domain/event.dart';
import '../../calendar/domain/event_repo.dart';
import '../../ideas/domain/idea_repo.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_category.dart';
import '../../notes/domain/note_repo.dart';
import '../../recap/domain/recap.dart';
import '../../recap/domain/recap_repo.dart';
import '../../todo/domain/todo.dart';
import '../../todo/domain/todo_category.dart';
import '../../todo/domain/todo_repo.dart';

/// A Smart Add submission captured when the user taps add: the raw text plus a
/// snapshot of the attachments (copied so the overlay can reset/dispose freely).
class SmartAddInput {
  final String text;
  final List<PendingAttachment> attachments;
  const SmartAddInput({required this.text, required this.attachments});
}

enum SmartAddStatus { idle, processing, ready }

/// Drives the background Smart Add flow (AI_proxy.md §5) without blocking the
/// overlay: [start] runs transcription + `classifyMultiInput` in the background;
/// the result surfaces as a shell-level bar that the user [accept]s (writes the
/// items to their repos) or re-routes via [reclassify] (a fresh AI pass
/// restricted to the chosen pages). Held in memory only — no pending Firestore
/// docs. Provided once at the authenticated scope so both Add entry points (the
/// `/add` route and the swipe-strip overlay) feed the same bar.
class SmartAddController extends ChangeNotifier {
  SmartAddController({
    required AiService ai,
    required TodoRepo todoRepo,
    required EventRepo eventRepo,
    required IdeaRepo ideaRepo,
    required NoteRepo noteRepo,
    required RecapRepo recapRepo,
  })  : _ai = ai,
        _todoRepo = todoRepo,
        _eventRepo = eventRepo,
        _ideaRepo = ideaRepo,
        _noteRepo = noteRepo,
        _recapRepo = recapRepo;

  final AiService _ai;
  final TodoRepo _todoRepo;
  final EventRepo _eventRepo;
  final IdeaRepo _ideaRepo;
  final NoteRepo _noteRepo;
  final RecapRepo _recapRepo;

  SmartAddStatus _status = SmartAddStatus.idle;
  SmartAddInput? _input;
  List<ClassificationItem> _items = const [];
  // Sub-category overrides chosen in the edit sheet, applied at write time.
  String? _todoCatOverride;
  String? _noteCatOverride;
  // Guards a stale background pass from overwriting a newer submission.
  int _runId = 0;

  SmartAddStatus get status => _status;
  bool get isProcessing => _status == SmartAddStatus.processing;
  bool get isReady => _status == SmartAddStatus.ready;
  bool get isIdle => _status == SmartAddStatus.idle;
  List<ClassificationItem> get items => _items;

  int get eventCount => _items.whereType<ClassifiedTodoWithTime>().length;
  int get todoCount => _items.whereType<ClassifiedTodo>().length;
  int get ideaCount => _items.whereType<ClassifiedIdea>().length;
  int get noteCount => _items.whereType<ClassifiedNote>().length;
  int get recapCount => _items.whereType<ClassifiedRecap>().length;

  /// e.g. "AI 想新增 3 個行程、2 個待辦、1 則札記".
  String get summary {
    final parts = <String>[
      if (eventCount > 0) '$eventCount 個行程',
      if (todoCount > 0) '$todoCount 個待辦',
      if (ideaCount > 0) '$ideaCount 個靈感',
      if (noteCount > 0) '$noteCount 則札記',
      if (recapCount > 0) '$recapCount 則回顧',
    ];
    return parts.isEmpty ? 'AI 沒有可新增的項目' : 'AI 想新增 ${parts.join('、')}';
  }

  // ── Step 1: background classify ─────────────────────────────────────────────

  Future<void> start(SmartAddInput input) async {
    final run = ++_runId;
    _input = input;
    _items = const [];
    _todoCatOverride = null;
    _noteCatOverride = null;
    _status = SmartAddStatus.processing;
    notifyListeners();

    final items = await _classify(input, userSpecifiedCat: '');
    if (run != _runId) return; // a newer submission superseded this pass

    if (items == null) {
      // Error already surfaced by AiService — drop back to idle.
      _status = SmartAddStatus.idle;
      notifyListeners();
      return;
    }
    if (items.isEmpty) {
      _status = SmartAddStatus.idle;
      notifyListeners();
      _toast('AI 沒有辨識出可新增的項目');
      return;
    }
    _items = items;
    _status = SmartAddStatus.ready;
    notifyListeners();
  }

  // ── Step 2a: re-route via AI (edit) ─────────────────────────────────────────

  /// Re-runs classification restricted to [cats] (the pages chosen in the edit
  /// sheet, mapped to classifier type names via `userSpecifiedCat`), optionally
  /// pinning the todo/note sub-category applied at write time.
  Future<void> reclassify({
    required Set<String> cats,
    String? todoCatId,
    String? noteCatId,
  }) async {
    final input = _input;
    if (input == null || cats.isEmpty) return;
    final run = ++_runId;
    _status = SmartAddStatus.processing;
    notifyListeners();

    final allowed = cats.map(_catKeyToType).join(', ');
    final items = await _classify(input, userSpecifiedCat: allowed);
    if (run != _runId) return;

    if (items == null || items.isEmpty) {
      // Keep the previous result rather than wiping it on a failed re-route.
      _status = SmartAddStatus.ready;
      notifyListeners();
      if (items != null && items.isEmpty) _toast('AI 沒有辨識出可新增的項目');
      return;
    }
    _items = items;
    _todoCatOverride = todoCatId;
    _noteCatOverride = noteCatId;
    _status = SmartAddStatus.ready;
    notifyListeners();
  }

  // ── Step 2b: accept → write to repos ────────────────────────────────────────

  /// Writes the current items to their repos and clears the bar. Returns the
  /// number of items written (for the success toast).
  Future<int> accept() async {
    final input = _input;
    if (input == null || _items.isEmpty) return 0;

    final todoCats = await _todoRepo.watchTodoCategories().first;
    final noteCats = await _noteRepo.watchNoteCategories().first;
    final attachments = input.attachments;

    int count = 0;
    for (final item in _items) {
      switch (item) {
        case ClassifiedTodo t:
          await _todoRepo.add(Todo(
            id: '',
            title: t.text,
            category: _todoRef(_todoCatOverride ?? t.catId, todoCats),
          ));
          count++;
        case ClassifiedTodoWithTime tt:
          await _eventRepo.add(CalendarEvent(
            id: '',
            title: tt.text,
            startTime: tt.start,
            endTime: tt.end,
            color: AppColors.sage,
            createdAt: DateTime.now(),
          ));
          count++;
        case ClassifiedIdea idea:
          await _ideaRepo.add(idea.text);
          count++;
        case ClassifiedNote note:
          final routed = note.attachmentIndices
              .where((i) => i >= 0 && i < attachments.length)
              .map((i) => attachments[i])
              .toList();
          await _noteRepo.add(
            Note(
              id: '',
              dateKey: note.dateKey,
              content: note.content,
              category: _noteRef(_noteCatOverride ?? note.noteCatId, noteCats),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            attachments: routed,
          );
          count++;
        case ClassifiedRecap r:
          await _recapRepo.add(Recap(
            id: '',
            title: r.title.isEmpty ? '回顧' : r.title,
            content: r.description,
            createdAt: DateTime.now(),
          ));
          count++;
      }
    }
    _clear();
    return count;
  }

  /// Discards the pending result without writing.
  void dismiss() => _clear();

  void _clear() {
    _runId++;
    _input = null;
    _items = const [];
    _todoCatOverride = null;
    _noteCatOverride = null;
    _status = SmartAddStatus.idle;
    notifyListeners();
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  // Transcribes any untranscribed audio, then builds the multimodal payload
  // (base64 images for vision + concatenated file/audio text + manifest) and
  // classifies. Returns null on error, [] when nothing was detected.
  Future<List<ClassificationItem>?> _classify(
    SmartAddInput input, {
    required String userSpecifiedCat,
  }) async {
    final attachments = input.attachments;
    for (int i = 0; i < attachments.length; i++) {
      final a = attachments[i];
      if (a.type == 'audio' &&
          (a.extractedText == null || a.extractedText!.isEmpty)) {
        final r = await _ai.transcribe(audioBytes: a.bytes, filename: a.filename);
        if (r is Ok<String>) {
          attachments[i] = PendingAttachment(
            type: a.type,
            filename: a.filename,
            bytes: a.bytes,
            ext: a.ext,
            extractedText: r.value,
          );
        }
      }
    }

    final images = <String>[];
    final fileTextParts = <String>[];
    final manifest = <AiAttachmentRef>[];
    for (int i = 0; i < attachments.length; i++) {
      final a = attachments[i];
      manifest.add(AiAttachmentRef(i: i, type: a.type, name: a.filename));
      if (a.type == 'image') {
        images.add(base64Encode(a.bytes));
      } else if (a.extractedText != null && a.extractedText!.isNotEmpty) {
        fileTextParts.add('【${a.filename}】\n${a.extractedText}');
      }
    }

    final res = await _ai.classifyMultiInput(
      text: input.text,
      images: images,
      fileText: fileTextParts.join('\n\n'),
      attachments: manifest,
      userSpecifiedCat: userSpecifiedCat,
    );
    if (res is! Ok<List<ClassificationItem>>) return null;
    return res.value;
  }

  // Maps an edit-sheet page key to a classifier type name.
  String _catKeyToType(String key) =>
      key == 'calendar' ? 'todo_with_time' : key;

  TodoCategoryRef _todoRef(String id, List<TodoCategory> cats) {
    for (final c in cats) {
      if (c.id == id) {
        return TodoCategoryRef(id: c.id, label: c.label, color: c.color);
      }
    }
    return TodoCategoryRef.undefined;
  }

  NoteCategoryRef _noteRef(String id, List<NoteCategory> cats) {
    for (final c in cats) {
      if (c.id == id) {
        return NoteCategoryRef(
            id: c.id, label: c.label, color: c.color, iconName: c.iconName);
      }
    }
    return NoteCategoryRef.undefined;
  }

  void _toast(String msg) {
    scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: AppText.body(size: 13, color: Colors.white)),
        backgroundColor: AppColors.dark,
        behavior: SnackBarBehavior.floating,
      ));
  }
}
