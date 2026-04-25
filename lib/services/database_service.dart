import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/event.dart';
import '../models/todo_item.dart';
import '../models/idea.dart';
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
    return openDatabase(
      fullPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE todos (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        text       TEXT    NOT NULL,
        done       INTEGER NOT NULL DEFAULT 0,
        cat        TEXT    NOT NULL,
        color      INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE events (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT    NOT NULL,
        start_day  INTEGER NOT NULL,
        start_hour INTEGER NOT NULL,
        start_min  INTEGER NOT NULL,
        end_day    INTEGER NOT NULL,
        end_hour   INTEGER NOT NULL,
        end_min    INTEGER NOT NULL,
        color      INTEGER NOT NULL,
        all_day    INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ideas (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        text       TEXT    NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        date_key   TEXT    NOT NULL UNIQUE,
        content    TEXT    NOT NULL,
        updated_at INTEGER NOT NULL
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

    // Seed initial data on first run
    await _seed(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE ideas ADD COLUMN ai_summary TEXT');
      await db.execute('ALTER TABLE ideas ADD COLUMN links      TEXT');
    }
  }

  Future<void> _seed(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final e in SeedData.initEvents) {
      await db.insert('events', {
        'title': e.title,
        'start_day': e.startDay, 'start_hour': e.startHour, 'start_min': e.startMin,
        'end_day': e.endDay,   'end_hour': e.endHour,   'end_min': e.endMin,
        'color': e.color.toARGB32(),
        'all_day': e.allDay ? 1 : 0,
        'created_at': now,
      });
    }

    for (final t in SeedData.initTodos) {
      await db.insert('todos', {
        'text': t.text,
        'done': t.done ? 1 : 0,
        'cat': t.cat,
        'color': t.color.toARGB32(),
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
  }

  /// Only seeds if all tables are empty (i.e. fresh install).
  Future<void> seedIfEmpty() async {
    final database = await db;
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM todos'),
    ) ?? 0;
    if (count == 0) await _seed(database);
  }

  // ─── TODOS ─────────────────────────────────────────────────────────────────

  Future<List<TodoItem>> getTodos() async {
    final database = await db;
    final rows = await database.query('todos', orderBy: 'created_at ASC');
    return rows.map(_rowToTodo).toList();
  }

  Future<int> insertTodo(TodoItem t) async {
    final database = await db;
    return database.insert('todos', {
      'text': t.text,
      'done': t.done ? 1 : 0,
      'cat': t.cat,
      'color': t.color.toARGB32(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateTodo(TodoItem t) async {
    final database = await db;
    await database.update(
      'todos',
      {'done': t.done ? 1 : 0, 'text': t.text, 'cat': t.cat, 'color': t.color.toARGB32()},
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  Future<void> deleteTodo(int id) async {
    final database = await db;
    await database.delete('todos', where: 'id = ?', whereArgs: [id]);
  }

  TodoItem _rowToTodo(Map<String, dynamic> r) => TodoItem(
    id: r['id'] as int,
    text: r['text'] as String,
    done: (r['done'] as int) == 1,
    cat: r['cat'] as String,
    color: Color(r['color'] as int),
  );

  // ─── EVENTS ────────────────────────────────────────────────────────────────

  Future<List<CalendarEvent>> getEvents() async {
    final database = await db;
    final rows = await database.query('events', orderBy: 'start_day ASC, start_hour ASC');
    return rows.map(_rowToEvent).toList();
  }

  Future<int> insertEvent(CalendarEvent e) async {
    final database = await db;
    return database.insert('events', {
      'title': e.title,
      'start_day': e.startDay, 'start_hour': e.startHour, 'start_min': e.startMin,
      'end_day': e.endDay,   'end_hour': e.endHour,   'end_min': e.endMin,
      'color': e.color.toARGB32(),
      'all_day': e.allDay ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateEvent(CalendarEvent e) async {
    final database = await db;
    await database.update(
      'events',
      {
        'title': e.title,
        'start_day': e.startDay, 'start_hour': e.startHour, 'start_min': e.startMin,
        'end_day': e.endDay,   'end_hour': e.endHour,   'end_min': e.endMin,
        'color': e.color.toARGB32(),
        'all_day': e.allDay ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [e.id],
    );
  }

  CalendarEvent _rowToEvent(Map<String, dynamic> r) => CalendarEvent(
    id: r['id'] as int,
    title: r['title'] as String,
    startDay: r['start_day'] as int, startHour: r['start_hour'] as int, startMin: r['start_min'] as int,
    endDay: r['end_day'] as int,   endHour: r['end_hour'] as int,   endMin: r['end_min'] as int,
    color: Color(r['color'] as int),
    allDay: (r['all_day'] as int) == 1,
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

  // ─── NOTES ─────────────────────────────────────────────────────────────────

  Future<Map<String, String>> getNotes() async {
    final database = await db;
    final rows = await database.query('notes');
    return {for (final r in rows) r['date_key'] as String: r['content'] as String};
  }

  Future<void> upsertNote(String dateKey, String content) async {
    final database = await db;
    if (content.isEmpty) {
      await database.delete('notes', where: 'date_key = ?', whereArgs: [dateKey]);
    } else {
      await database.insert(
        'notes',
        {
          'date_key': dateKey,
          'content': content,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

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

  /// Returns notes updated within the last [days] days, newest first.
  Future<Map<String, String>> getRecentNotes({int days = 7}) async {
    final database = await db;
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final rows = await database.query(
      'notes',
      where: 'updated_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'date_key DESC',
    );
    return {for (final r in rows) r['date_key'] as String: r['content'] as String};
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

  Future<String> buildContextSummary() async {
    final results = await Future.wait([
      getTodos(),
      getEvents(),
      getRecentNotes(),
      getIdeas(),
      getActiveRecapItems(),
    ]);

    final todos  = results[0] as List<TodoItem>;
    final events = results[1] as List<CalendarEvent>;
    final notes  = results[2] as Map<String, String>;
    final ideas  = results[3] as List<Idea>;
    final goals  = results[4] as List<RecapItem>;

    final buf = StringBuffer();
    buf.writeln('現在日期：${todayKey()}');
    buf.writeln();

    buf.writeln('【待辦事項】');
    if (todos.isEmpty) {
      buf.writeln('（無待辦）');
    } else {
      for (final t in todos) {
        buf.writeln('- [${t.done ? '✓' : '✗'}] ${t.text}（${t.cat}）');
      }
    }
    buf.writeln();

    buf.writeln('【行程】');
    if (events.isEmpty) {
      buf.writeln('（無行程）');
    } else {
      for (final e in events) {
        if (e.allDay) {
          buf.writeln('- [全天] ${e.title}（${e.startDay}日–${e.endDay}日）');
        } else {
          buf.writeln('- ${e.startDay}日 ${fmtHm(e.startHour, e.startMin)}–${fmtHm(e.endHour, e.endMin)}：${e.title}');
        }
      }
    }
    buf.writeln();

    buf.writeln('【最近筆記（最近 7 天）】');
    if (notes.isEmpty) {
      buf.writeln('（無近期筆記）');
    } else {
      for (final entry in notes.entries) {
        final preview = entry.value.length > 60
            ? '${entry.value.substring(0, 60)}…'
            : entry.value;
        buf.writeln('${entry.key}：$preview');
      }
    }
    buf.writeln();

    buf.writeln('【靈感清單】');
    if (ideas.isEmpty) {
      buf.writeln('（無靈感）');
    } else {
      for (int i = 0; i < ideas.length; i++) {
        buf.writeln('${i + 1}. ${ideas[i].text}');
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
}
