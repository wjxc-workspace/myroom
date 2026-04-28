import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/event.dart';
import '../models/todo_item.dart';
import '../models/idea.dart';
import '../models/ai_resource.dart';
import '../models/note_item.dart';
import '../models/recap_item.dart';
import '../data/seed_data.dart';

// ─── Simple ChatMessage model (used only by DatabaseService) ─────────────────
class DbChatMessage {
  final int id;
  final bool isUser;
  final String text;
  final int createdAt;

  const DbChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.createdAt,
  });
}

// ─── DatabaseService singleton ────────────────────────────────────────────────
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final fullPath = join(dbPath, 'myroom.db');
    return openDatabase(fullPath, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE todos (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        text       TEXT    NOT NULL,
        done       INTEGER NOT NULL DEFAULT 0,
        cat        TEXT    NOT NULL,
        color      INTEGER NOT NULL,
        priority   INTEGER NOT NULL DEFAULT 3,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        name  TEXT    NOT NULL UNIQUE,
        color INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        title       TEXT    NOT NULL,
        start_year  INTEGER NOT NULL DEFAULT 2026,
        start_month INTEGER NOT NULL DEFAULT 4,
        start_day   INTEGER NOT NULL,
        start_hour  INTEGER NOT NULL,
        start_min   INTEGER NOT NULL,
        end_year    INTEGER NOT NULL DEFAULT 2026,
        end_month   INTEGER NOT NULL DEFAULT 4,
        end_day     INTEGER NOT NULL,
        end_hour    INTEGER NOT NULL,
        end_min     INTEGER NOT NULL,
        color       INTEGER NOT NULL,
        all_day     INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        location    TEXT,
        created_at  INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ideas (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        text       TEXT    NOT NULL,
        ai_summary TEXT,
        links      TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // notes: no UNIQUE on date_key — multiple notes per date are allowed
    // cat_id NULL = primary date note; non-null = categorized note
    await db.execute('''
      CREATE TABLE notes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        date_key   TEXT    NOT NULL,
        content    TEXT    NOT NULL,
        cat_id     TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE note_categories (
        id         TEXT    PRIMARY KEY,
        label      TEXT    NOT NULL,
        icon_name  TEXT    NOT NULL,
        color_val  INTEGER NOT NULL,
        bg_val     INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE recap_items (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        era              TEXT    NOT NULL,
        title            TEXT    NOT NULL,
        completed_date   TEXT,
        target_date      TEXT,
        desc             TEXT    NOT NULL,
        note_link        TEXT,
        created_at       INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        is_user    INTEGER NOT NULL,
        text       TEXT    NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pinned_resources (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        title     TEXT    NOT NULL,
        type      TEXT    NOT NULL,
        desc      TEXT    NOT NULL,
        url       TEXT    NOT NULL UNIQUE,
        pinned_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE user_profile (
        id              INTEGER PRIMARY KEY DEFAULT 1,
        self_intro      TEXT    NOT NULL DEFAULT '',
        ai_instructions TEXT    NOT NULL DEFAULT ''
      )
    ''');

    // Seed initial data on first run
    await _seed(db);
  }

  Future<void> _seed(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final e in SeedData.initEvents) {
      await db.insert('events', {
        'title': e.title,
        'start_year': e.startYear, 'start_month': e.startMonth,
        'start_day': e.startDay,   'start_hour': e.startHour, 'start_min': e.startMin,
        'end_year': e.endYear,     'end_month': e.endMonth,
        'end_day': e.endDay,       'end_hour': e.endHour,   'end_min': e.endMin,
        'color': e.color.toARGB32(),
        'all_day': e.allDay ? 1 : 0,
        'description': e.description,
        'location': e.location,
        'created_at': now,
      });
    }

    for (final c in SeedData.initCategories) {
      await db.insert('categories', {
        'id': c.id,
        'name': c.name,
        'color': c.color.toARGB32(),
      });
    }

    for (final t in SeedData.initTodos) {
      await db.insert('todos', {
        'text': t.text,
        'done': t.done ? 1 : 0,
        'cat': t.cat,
        'color': t.color.toARGB32(),
        'priority': t.priority,
        'created_at': now,
      });
    }

    for (final i in SeedData.initIdeas) {
      await db.insert('ideas', {
        'text': i.text,
        'created_at': now,
      });
    }

    for (final entry in SeedData.initNotes.entries) {
      await db.insert('notes', {
        'date_key': entry.key,
        'content': entry.value,
        'cat_id': null,
        'updated_at': now,
      });
    }

    for (final r in SeedData.timelineData) {
      await db.insert('recap_items', {
        'era': r.era.name,
        'title': r.title,
        'completed_date': r.completedDate,
        'target_date': r.targetDate,
        'desc': r.desc,
        'note_link': r.noteLink,
        'created_at': now,
      });
    }

    for (final nc in SeedData.initNoteCategories) {
      await db.insert('note_categories', {
        'id': nc.id,
        'label': nc.label,
        'icon_name': nc.iconName,
        'color_val': nc.color.toARGB32(),
        'bg_val': nc.bg.toARGB32(),
        'sort_order': nc.sortOrder,
      });
    }
  }

  /// Only seeds if all tables are empty (i.e. fresh install).
  Future<void> seedIfEmpty() async {
    final database = await db;
    final todoCount = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM todos'),
    ) ?? 0;
    final eventCount = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM events'),
    ) ?? 0;
    if (todoCount == 0 && eventCount == 0) {
      await _seed(database);
    } else if (eventCount == 0) {
      // Events table was wiped by migration — re-seed events only
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in SeedData.initEvents) {
        await database.insert('events', {
          'title': e.title,
          'start_year': e.startYear, 'start_month': e.startMonth,
          'start_day': e.startDay,   'start_hour': e.startHour, 'start_min': e.startMin,
          'end_year': e.endYear,     'end_month': e.endMonth,
          'end_day': e.endDay,       'end_hour': e.endHour,   'end_min': e.endMin,
          'color': e.color.toARGB32(),
          'all_day': e.allDay ? 1 : 0,
          'description': e.description,
          'location': e.location,
          'created_at': now,
        });
      }
    }
  }

  // ─── TODOS ─────────────────────────────────────────────────────────────────

  Future<List<TodoItem>> getTodos() async {
    final database = await db;
    final rows = await database.query('todos', orderBy: 'created_at ASC');
    return rows.map(_rowToTodo).toList();
  }

  Future<List<TodoItem>> getTodosFiltered({bool includeDone = false}) async {
    final database = await db;
    final rows = await database.query(
      'todos',
      where: includeDone ? null : 'done = 0',
      orderBy: 'priority ASC, created_at ASC',
    );
    return rows.map(_rowToTodo).toList();
  }

  Future<int> insertTodo(TodoItem t) async {
    final database = await db;
    return database.insert('todos', {
      'text': t.text,
      'done': t.done ? 1 : 0,
      'cat': t.cat,
      'color': t.color.toARGB32(),
      'priority': t.priority,
      'created_at': t.createdAt > 0 ? t.createdAt : DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateTodo(TodoItem t) async {
    final database = await db;
    await database.update(
      'todos',
      {'done': t.done ? 1 : 0, 'text': t.text, 'cat': t.cat, 'color': t.color.toARGB32(), 'priority': t.priority},
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  Future<int> deleteTodo(int id) async {
    final database = await db;
    return database.delete('todos', where: 'id = ?', whereArgs: [id]);
  }

  TodoItem _rowToTodo(Map<String, dynamic> r) => TodoItem(
    id: r['id'] as int,
    text: r['text'] as String,
    done: (r['done'] as int) == 1,
    cat: r['cat'] as String,
    color: Color(r['color'] as int),
    priority: (r['priority'] as int?) ?? 3,
    createdAt: (r['created_at'] as int?) ?? 0,
  );

  // ─── CATEGORIES ────────────────────────────────────────────────────────────

  Future<List<TodoCategory>> getCategories() async {
    final database = await db;
    final rows = await database.query('categories', orderBy: 'id ASC');
    return rows.map((r) => TodoCategory(
      id: r['id'] as int,
      name: r['name'] as String,
      color: Color(r['color'] as int),
    )).toList();
  }

  Future<int> insertCategory(String name, Color color) async {
    final database = await db;
    return database.insert('categories', {'name': name, 'color': color.toARGB32()});
  }

  Future<void> deleteCategory(int id) async {
    final database = await db;
    await database.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ─── EVENTS ────────────────────────────────────────────────────────────────

  Future<List<CalendarEvent>> getEvents() async {
    final database = await db;
    final rows = await database.query('events', orderBy: 'start_day ASC, start_hour ASC');
    return rows.map(_rowToEvent).toList();
  }

  Future<List<CalendarEvent>> getEventsInWindow(int pastDays, int futureDays) async {
    final database = await db;
    final now = DateTime.now();
    final past   = now.subtract(Duration(days: pastDays));
    final future = now.add(Duration(days: futureDays));
    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
    final rows = await database.rawQuery(
      "SELECT * FROM events "
      "WHERE printf('%04d-%02d-%02d', start_year, start_month, start_day) >= ? "
      "  AND printf('%04d-%02d-%02d', start_year, start_month, start_day) <= ? "
      "ORDER BY start_year ASC, start_month ASC, start_day ASC, start_hour ASC",
      [fmtDate(past), fmtDate(future)],
    );
    return rows.map(_rowToEvent).toList();
  }

  Future<int> insertEvent(CalendarEvent e) async {
    final database = await db;
    return database.insert('events', {
      'title': e.title,
      'start_year': e.startYear, 'start_month': e.startMonth,
      'start_day': e.startDay,   'start_hour': e.startHour, 'start_min': e.startMin,
      'end_year': e.endYear,     'end_month': e.endMonth,
      'end_day': e.endDay,       'end_hour': e.endHour,   'end_min': e.endMin,
      'color': e.color.toARGB32(),
      'all_day': e.allDay ? 1 : 0,
      'description': e.description,
      'location': e.location,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> deleteEvent(int id) async {
    final database = await db;
    return database.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateEvent(CalendarEvent e) async {
    final database = await db;
    await database.update(
      'events',
      {
        'title': e.title,
        'start_year': e.startYear, 'start_month': e.startMonth,
        'start_day': e.startDay,   'start_hour': e.startHour, 'start_min': e.startMin,
        'end_year': e.endYear,     'end_month': e.endMonth,
        'end_day': e.endDay,       'end_hour': e.endHour,   'end_min': e.endMin,
        'color': e.color.toARGB32(),
        'all_day': e.allDay ? 1 : 0,
        'description': e.description,
        'location': e.location,
      },
      where: 'id = ?',
      whereArgs: [e.id],
    );
  }

  CalendarEvent _rowToEvent(Map<String, dynamic> r) => CalendarEvent(
    id: r['id'] as int,
    title: r['title'] as String,
    startYear:  (r['start_year']  as int?) ?? 2026,
    startMonth: (r['start_month'] as int?) ?? 4,
    startDay:   r['start_day']  as int,
    startHour:  r['start_hour'] as int,
    startMin:   r['start_min']  as int,
    endYear:    (r['end_year']   as int?) ?? 2026,
    endMonth:   (r['end_month']  as int?) ?? 4,
    endDay:     r['end_day']    as int,
    endHour:    r['end_hour']   as int,
    endMin:     r['end_min']    as int,
    color:      Color(r['color'] as int),
    allDay:     (r['all_day'] as int) == 1,
    description: r['description'] as String?,
    location:    r['location']    as String?,
  );

  // ─── IDEAS ─────────────────────────────────────────────────────────────────

  Future<List<Idea>> getIdeas() async {
    final database = await db;
    final rows = await database.query('ideas', orderBy: 'created_at ASC');
    return rows.map((r) {
      final linksJson = r['links'] as String?;
      final links = linksJson != null
          ? (jsonDecode(linksJson) as List)
              .map((l) => IdeaLink(title: l['title'] as String, url: l['url'] as String))
              .toList()
          : <IdeaLink>[];
      return Idea(
        id: r['id'] as int,
        text: r['text'] as String,
        aiSummary: r['ai_summary'] as String?,
        links: links,
      );
    }).toList();
  }

  Future<void> updateIdeaAiResult(int id, String aiSummary, String linksJson) async {
    final database = await db;
    await database.update(
      'ideas',
      {'ai_summary': aiSummary, 'links': linksJson},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertIdea(String text) async {
    final database = await db;
    return database.insert('ideas', {
      'text': text,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> deleteIdea(int id) async {
    final database = await db;
    return database.delete('ideas', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Idea>> getIdeasPaged({int limit = 30}) async {
    final database = await db;
    final rows = await database.query('ideas', orderBy: 'created_at DESC', limit: limit);
    return rows.map((r) {
      final linksJson = r['links'] as String?;
      final links = linksJson != null
          ? (jsonDecode(linksJson) as List)
              .map((l) => IdeaLink(title: l['title'] as String, url: l['url'] as String))
              .toList()
          : <IdeaLink>[];
      return Idea(
        id: r['id'] as int,
        text: r['text'] as String,
        aiSummary: r['ai_summary'] as String?,
        links: links,
      );
    }).toList();
  }

  // ─── PINNED RESOURCES ──────────────────────────────────────────────────────

  Future<List<AiResource>> getPinnedResources() async {
    final database = await db;
    final rows = await database.query('pinned_resources', orderBy: 'pinned_at DESC');
    return rows.map((r) => AiResource(
      title: r['title'] as String,
      type:  r['type']  as String,
      desc:  r['desc']  as String,
      url:   r['url']   as String,
    )).toList();
  }

  Future<void> pinResource(AiResource r) async {
    final database = await db;
    await database.insert(
      'pinned_resources',
      {
        'title': r.title,
        'type': r.type,
        'desc': r.desc,
        'url': r.url,
        'pinned_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> unpinResource(String url) async {
    final database = await db;
    await database.delete('pinned_resources', where: 'url = ?', whereArgs: [url]);
  }

  // ─── NOTES ─────────────────────────────────────────────────────────────────

  /// Returns one content string per date_key (the most recently updated).
  /// Used by main.dart to drive calendar dot indicators.
  Future<Map<String, String>> getNotes() async {
    final database = await db;
    final rows = await database.query('notes', orderBy: 'date_key ASC, updated_at DESC');
    final result = <String, String>{};
    for (final r in rows) {
      final key = r['date_key'] as String;
      if (!result.containsKey(key)) result[key] = r['content'] as String;
    }
    return result;
  }

  /// Upserts the primary date note (cat_id IS NULL) for [dateKey].
  /// Returns the note's id, or -1 if the note was deleted (empty content).
  Future<int> upsertNote(String dateKey, String content) async {
    final database = await db;
    final existing = await database.query(
      'notes',
      where: 'date_key = ? AND cat_id IS NULL',
      whereArgs: [dateKey],
      limit: 1,
    );
    if (content.isEmpty) {
      if (existing.isNotEmpty) {
        await database.delete('notes', where: 'id = ?', whereArgs: [existing.first['id']]);
      }
      return -1;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await database.update(
        'notes', {'content': content, 'updated_at': now},
        where: 'id = ?', whereArgs: [id],
      );
      return id;
    } else {
      return database.insert('notes', {
        'date_key': dateKey, 'content': content,
        'cat_id': null, 'updated_at': now,
      });
    }
  }

  /// Returns the primary date note (cat_id IS NULL) for [dateKey], or null.
  Future<NoteItem?> getNotePrimary(String dateKey) async {
    final database = await db;
    final rows = await database.query(
      'notes',
      where: 'date_key = ? AND cat_id IS NULL',
      whereArgs: [dateKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToNoteItem(rows.first);
  }

  /// Returns all notes for a category, newest first.
  Future<List<NoteItem>> getNotesByCategory(String catId) async {
    final database = await db;
    final rows = await database.query(
      'notes',
      where: 'cat_id = ?',
      whereArgs: [catId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_rowToNoteItem).toList();
  }

  /// Inserts a categorized note (from the 分類 tab). Returns the new id.
  Future<int> insertCatNote(
    String dateKey, String content, String catId,
  ) async {
    final database = await db;
    return database.insert('notes', {
      'date_key': dateKey,
      'content': content,
      'cat_id': catId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Assigns (or clears) the category on an existing note.
  Future<void> updateNoteCat(int id, String? catId) async {
    final database = await db;
    await database.update(
      'notes', {'cat_id': catId},
      where: 'id = ?', whereArgs: [id],
    );
  }

  /// Returns all notes for a date, oldest first (primary note first, then categorized).
  Future<List<NoteItem>> getNotesByDate(String dateKey) async {
    final database = await db;
    final rows = await database.query(
      'notes',
      where: 'date_key = ?',
      whereArgs: [dateKey],
      orderBy: 'updated_at ASC',
    );
    return rows.map(_rowToNoteItem).toList();
  }

  /// Returns true if a note with [id] exists.
  Future<bool> noteExists(int id) async {
    final database = await db;
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM notes WHERE id=?', [id]),
    ) ?? 0;
    return count > 0;
  }

  /// Deletes any note by id. Returns the number of rows deleted.
  Future<int> deleteNote(int id) async {
    final database = await db;
    return database.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  NoteItem _rowToNoteItem(Map<String, dynamic> r) => NoteItem(
    id: r['id'] as int,
    dateKey: r['date_key'] as String,
    content: r['content'] as String,
    catId: r['cat_id'] as String?,
    updatedAt: r['updated_at'] as int,
  );

  // ─── NOTE CATEGORIES ───────────────────────────────────────────────────────

  /// Returns all categories ordered by sort_order.
  Future<List<NoteCategory>> getNoteCategories() async {
    final database = await db;
    final rows = await database.query('note_categories', orderBy: 'sort_order ASC');
    return rows.map(_rowToCategory).toList();
  }

  /// Inserts a new user-defined category.
  Future<void> insertNoteCategory(NoteCategory cat) async {
    final database = await db;
    await database.insert('note_categories', {
      'id': cat.id,
      'label': cat.label,
      'icon_name': cat.iconName,
      'color_val': cat.color.toARGB32(),
      'bg_val': cat.bg.toARGB32(),
      'sort_order': cat.sortOrder,
    });
  }

  /// Deletes a category and all notes that belong to it.
  Future<void> deleteNoteCategory(String id) async {
    final database = await db;
    await database.delete('notes', where: 'cat_id = ?', whereArgs: [id]);
    await database.delete('note_categories', where: 'id = ?', whereArgs: [id]);
  }

  NoteCategory _rowToCategory(Map<String, dynamic> r) => NoteCategory(
    id: r['id'] as String,
    label: r['label'] as String,
    iconName: r['icon_name'] as String,
    color: Color(r['color_val'] as int),
    bg: Color(r['bg_val'] as int),
    sortOrder: r['sort_order'] as int,
  );

  // ─── RECAP ─────────────────────────────────────────────────────────────────

  Future<List<RecapItem>> getRecapItems() async {
    final database = await db;
    final rows = await database.query('recap_items', orderBy: 'created_at ASC');
    return rows.map(_rowToRecap).toList();
  }

  Future<int> insertRecapItem(RecapItem r) async {
    final database = await db;
    return database.insert('recap_items', {
      'era': r.era.name,
      'title': r.title,
      'completed_date': r.completedDate,
      'target_date': r.targetDate,
      'desc': r.desc,
      'note_link': r.noteLink,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  RecapItem _rowToRecap(Map<String, dynamic> r) => RecapItem(
    id: r['id'].toString(),
    era: Era.values.firstWhere((e) => e.name == r['era']),
    title: r['title'] as String,
    completedDate: r['completed_date'] as String?,
    targetDate: r['target_date'] as String?,
    desc: r['desc'] as String,
    noteLink: r['note_link'] as String?,
  );

  // ─── CHAT MESSAGES ─────────────────────────────────────────────────────────

  Future<List<DbChatMessage>> getChatMessages({int limit = 60}) async {
    final database = await db;
    // Fetch the most-recent rows in DESC order, then reverse for display.
    final rows = await database.query(
      'chat_messages',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.reversed
        .map((r) => DbChatMessage(
              id: r['id'] as int,
              isUser: (r['is_user'] as int) == 1,
              text: r['text'] as String,
              createdAt: r['created_at'] as int,
            ))
        .toList();
  }

  Future<void> insertChatMessage(bool isUser, String text) async {
    final database = await db;
    await database.insert('chat_messages', {
      'is_user': isUser ? 1 : 0,
      'text': text,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ─── CONTEXT SUMMARY (for AI chat) ─────────────────────────────────────────

  /// Returns notes updated within the last [days] days, newest first,
  /// deduplicated to one entry per date_key.
  Future<Map<String, String>> getRecentNotes({int days = 7}) async {
    final database = await db;
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final rows = await database.query(
      'notes',
      where: 'updated_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'date_key DESC, updated_at DESC',
    );
    final result = <String, String>{};
    for (final r in rows) {
      final key = r['date_key'] as String;
      if (!result.containsKey(key)) result[key] = r['content'] as String;
    }
    return result;
  }

  /// Returns only now/future recap items (past items excluded from AI context).
  Future<List<RecapItem>> getActiveRecapItems() async {
    final database = await db;
    final rows = await database.query(
      'recap_items',
      where: "era IN ('now', 'future')",
      orderBy: 'created_at ASC',
    );
    return rows.map(_rowToRecap).toList();
  }

  // ─── USER PROFILE ──────────────────────────────────────────────────────────

  Future<({String selfIntro, String aiInstructions})> getUserProfile() async {
    final database = await db;
    final rows = await database.query(
      'user_profile',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return (selfIntro: '', aiInstructions: '');
    return (
      selfIntro: rows.first['self_intro'] as String? ?? '',
      aiInstructions: rows.first['ai_instructions'] as String? ?? '',
    );
  }

  Future<void> saveUserProfile(String selfIntro, String aiInstructions) async {
    final database = await db;
    await database.insert(
      'user_profile',
      {'id': 1, 'self_intro': selfIntro, 'ai_instructions': aiInstructions},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns recent notes as NoteItems (with IDs) for the context summary.
  Future<List<NoteItem>> getRecentNoteItems({int days = 7}) async {
    final database = await db;
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final rows = await database.query(
      'notes',
      where: 'updated_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'date_key DESC, updated_at DESC',
    );
    final seen = <String>{};
    final result = <NoteItem>[];
    for (final r in rows) {
      final key = r['date_key'] as String;
      if (seen.add(key)) result.add(_rowToNoteItem(r));
    }
    return result;
  }

  Future<int> _getDoneCount() async {
    final database = await db;
    return Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM todos WHERE done = 1'),
    ) ?? 0;
  }

  Future<String> buildContextSummary() async {
    final (pendingTodos, doneCount, events, noteItems, ideas, goals) = await (
      getTodosFiltered(),
      _getDoneCount(),
      getEventsInWindow(3, 30),
      getRecentNoteItems(),
      getIdeasPaged(limit: 20),
      getActiveRecapItems(),
    ).wait;

    final buf = StringBuffer();
    buf.writeln('現在日期：${todayKey()}');
    buf.writeln('（以下清單中 id= 為資料庫 id，可用於刪除或修改操作）');
    buf.writeln();

    buf.writeln('【待辦事項】');
    if (pendingTodos.isEmpty) {
      buf.writeln(doneCount > 0 ? '（所有待辦均已完成，共 $doneCount 項）' : '（無待辦）');
    } else {
      for (final t in pendingTodos) {
        buf.writeln('- [✗][id=${t.id}] ${t.text}（${t.cat}）');
      }
      if (doneCount > 0) buf.writeln('（已完成：$doneCount 項，未顯示）');
    }
    buf.writeln();

    buf.writeln('【行程（近 3 天至未來 30 天）】');
    if (events.isEmpty) {
      buf.writeln('（此時段無行程）');
    } else {
      for (final e in events) {
        if (e.allDay) {
          buf.writeln('- [id=${e.id}][全天] ${e.title}（${e.startYear}/${e.startMonth}/${e.startDay}–${e.endYear}/${e.endMonth}/${e.endDay}）');
        } else {
          buf.writeln('- [id=${e.id}] ${e.startYear}/${e.startMonth}/${e.startDay} ${fmtHm(e.startHour, e.startMin)}–${fmtHm(e.endHour, e.endMin)}：${e.title}');
        }
      }
    }
    buf.writeln();

    buf.writeln('【最近筆記（最近 7 天）】');
    if (noteItems.isEmpty) {
      buf.writeln('（無近期筆記）');
    } else {
      for (final n in noteItems) {
        final preview = n.content.length > 60 ? '${n.content.substring(0, 60)}…' : n.content;
        buf.writeln('${n.dateKey}[id=${n.id}]：$preview');
      }
    }
    buf.writeln();

    buf.writeln('【靈感清單（最新 ${ideas.length} 則）】');
    if (ideas.isEmpty) {
      buf.writeln('（無靈感）');
    } else {
      for (int i = 0; i < ideas.length; i++) {
        buf.writeln('${i + 1}. [id=${ideas[i].id}] ${ideas[i].text}');
      }
    }
    buf.writeln();

    buf.writeln('【目標與回顧】');
    if (goals.isEmpty) {
      buf.writeln('（無目標）');
    } else {
      for (final r in goals) {
        final eraLabel = r.era == Era.now ? '現在' : '未來';
        buf.writeln('[$eraLabel] ${r.title} — ${r.displayDate}');
      }
    }

    return buf.toString();
  }

  Future<String> buildCompactSummary() async {
    final database = await db;
    final now = DateTime.now();
    final todayStr = todayKey();
    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
    final futureBound = fmtDate(now.add(const Duration(days: 30)));
    final cutoff7d = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;

    final results = await Future.wait([
      database.rawQuery('SELECT COUNT(*) FROM todos WHERE done = 0'),           // 0
      database.rawQuery('SELECT COUNT(*) FROM todos WHERE done = 1'),           // 1
      database.query('todos', where: 'done = 0',
          orderBy: 'priority ASC, created_at ASC', limit: 3),                   // 2
      database.rawQuery(                                                         // 3
        "SELECT COUNT(*) FROM events "
        "WHERE printf('%04d-%02d-%02d', start_year, start_month, start_day) >= ?",
        [todayStr],
      ),
      database.rawQuery(                                                         // 4
        "SELECT * FROM events "
        "WHERE printf('%04d-%02d-%02d', start_year, start_month, start_day) >= ? "
        "  AND printf('%04d-%02d-%02d', start_year, start_month, start_day) <= ? "
        "ORDER BY start_year ASC, start_month ASC, start_day ASC, start_hour ASC "
        "LIMIT 3",
        [todayStr, futureBound],
      ),
      database.rawQuery('SELECT COUNT(*) FROM ideas'),                          // 5
      database.query('ideas', orderBy: 'created_at DESC', limit: 3),           // 6
      database.rawQuery(                                                         // 7
        'SELECT COUNT(DISTINCT date_key) FROM notes WHERE updated_at >= ?',
        [cutoff7d],
      ),
      database.query('notes',                                                    // 8
          where: 'updated_at >= ?', whereArgs: [cutoff7d],
          orderBy: 'updated_at DESC', limit: 1),
      database.query('recap_items',                                             // 9
          where: "era IN ('now', 'future')", orderBy: 'created_at ASC'),
    ]);

    final pendingCount    = Sqflite.firstIntValue(results[0]) ?? 0;
    final doneCount       = Sqflite.firstIntValue(results[1]) ?? 0;
    final topTodos        = results[2].map(_rowToTodo).toList();
    final upcomingCount   = Sqflite.firstIntValue(results[3]) ?? 0;
    final nextEvents      = results[4].map(_rowToEvent).toList();
    final ideaCount       = Sqflite.firstIntValue(results[5]) ?? 0;
    final latestIdeas     = results[6].map((r) => r['text'] as String).toList();
    final recentNoteCount = Sqflite.firstIntValue(results[7]) ?? 0;
    final latestNote      = results[8].isNotEmpty ? results[8].first : null;
    final goals           = results[9].map(_rowToRecap).toList();

    final buf = StringBuffer();
    buf.writeln('現在日期：$todayStr');
    buf.writeln('（如需完整清單含 id，請使用 list_todos / list_events / list_ideas / list_notes 工具）');
    buf.writeln();

    if (pendingCount == 0 && doneCount == 0) {
      buf.writeln('【待辦】無待辦事項');
    } else if (pendingCount == 0) {
      buf.writeln('【待辦】所有 $doneCount 項已完成');
    } else {
      final topList = topTodos.map((t) => '${t.text}（${t.cat}）').join('、');
      buf.writeln('【待辦】待處理 $pendingCount 項（已完成 $doneCount 項）。'
          '最緊急：$topList${pendingCount > 3 ? "…" : ""}');
    }

    if (upcomingCount == 0) {
      buf.writeln('【行程】未來 30 天無行程');
    } else {
      final evtList = nextEvents.map((e) {
        if (e.allDay) return '${e.startMonth}/${e.startDay} 全天 ${e.title}';
        return '${e.startMonth}/${e.startDay} ${fmtHm(e.startHour, e.startMin)} ${e.title}';
      }).join('、');
      buf.writeln('【行程】未來 30 天 $upcomingCount 個。最近：$evtList${upcomingCount > 3 ? "…" : ""}');
    }

    if (ideaCount == 0) {
      buf.writeln('【靈感】無靈感記錄');
    } else {
      final ideaList = latestIdeas.join('、');
      buf.writeln('【靈感】共 $ideaCount 則。最新：$ideaList${ideaCount > 3 ? "…" : ""}');
    }

    if (recentNoteCount == 0) {
      buf.writeln('【筆記】近 7 天無筆記');
    } else {
      var preview = '';
      if (latestNote != null) {
        final content = latestNote['content'] as String;
        final dateKey = latestNote['date_key'] as String;
        final p = content.length > 20 ? '${content.substring(0, 20)}…' : content;
        preview = '（$dateKey）「$p」';
      }
      buf.writeln('【筆記】近 7 天 $recentNoteCount 則。最新 $preview');
    }

    if (goals.isEmpty) {
      buf.writeln('【目標】無進行中目標');
    } else {
      final goalList = goals.map((r) {
        final label = r.era == Era.now ? '現在' : '未來';
        return '$label：${r.title}';
      }).join('；');
      buf.writeln('【目標】$goalList');
    }

    return buf.toString();
  }
}
