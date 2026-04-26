import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'theme.dart';
import 'models/event.dart';
import 'models/todo_item.dart';
import 'models/idea.dart';
import 'models/recap_item.dart';
import 'data/seed_data.dart' show kCatColors, kDow, todayKey;
import 'services/database_service.dart';
import 'services/openai_service.dart';
import 'widgets/mr_icon_button.dart';
import 'widgets/bottom_nav_bar.dart';
import 'pages/calendar_page.dart';
import 'pages/todo_page.dart';
import 'pages/idea_page.dart';
import 'pages/note_page.dart';
import 'pages/recap_page.dart';
import 'pages/setting_page.dart';
import 'overlays/add_overlay.dart';
import 'overlays/ai_chat_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const MyRoomApp());
}

class MyRoomApp extends StatelessWidget {
  const MyRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyRoom',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.light(surface: AppColors.bg),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      home: const MyRoomShell(),
    );
  }
}

enum _Overlay { none, add, ai }

class MyRoomShell extends StatefulWidget {
  const MyRoomShell({super.key});

  @override
  State<MyRoomShell> createState() => _MyRoomShellState();
}

class _MyRoomShellState extends State<MyRoomShell> {
  int _activeTab = 0;
  List<CalendarEvent> _events = [];
  List<TodoItem> _todos = [];
  List<TodoCategory> _categories = [];
  List<Idea> _ideas = [];
  Map<String, String> _notes = {};
  List<RecapItem> _recapItems = [];
  bool _loaded = false;
  _Overlay _overlay = _Overlay.none;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final db = DatabaseService.instance;
    await db.seedIfEmpty();
    final results = await Future.wait([
      db.getEvents(),
      db.getTodos(),
      db.getIdeas(),
      db.getNotes(),
      db.getCategories(),
      db.getRecapItems(),
    ]);
    if (!mounted) return;
    setState(() {
      _events      = results[0] as List<CalendarEvent>;
      _todos       = results[1] as List<TodoItem>;
      _ideas       = results[2] as List<Idea>;
      _notes       = results[3] as Map<String, String>;
      _categories  = results[4] as List<TodoCategory>;
      _recapItems  = results[5] as List<RecapItem>;
      _loaded = true;
    });
  }

  void _onTodoAdded(TodoItem t) async {
    await DatabaseService.instance.insertTodo(t);
    final updated = await DatabaseService.instance.getTodos();
    if (mounted) setState(() => _todos = updated);
  }

  void _onTodoToggled(TodoItem t) async {
    await DatabaseService.instance.updateTodo(t);
    final updated = await DatabaseService.instance.getTodos();
    if (mounted) setState(() => _todos = updated);
  }

  void _onTodoDeleted(int id) async {
    await DatabaseService.instance.deleteTodo(id);
    final updated = await DatabaseService.instance.getTodos();
    if (mounted) setState(() => _todos = updated);
  }

  void _onCategoryAdded(String name, Color color) async {
    await DatabaseService.instance.insertCategory(name, color);
    final updated = await DatabaseService.instance.getCategories();
    if (mounted) setState(() => _categories = updated);
  }

  void _onCategoryDeleted(int id) async {
    await DatabaseService.instance.deleteCategory(id);
    final updated = await DatabaseService.instance.getCategories();
    if (mounted) setState(() => _categories = updated);
  }

  void _onEventAdded(CalendarEvent e) async {
    await DatabaseService.instance.insertEvent(e);
    final updated = await DatabaseService.instance.getEvents();
    if (mounted) setState(() => _events = updated);
  }

  void _onEventDeleted(int id) async {
    await DatabaseService.instance.deleteEvent(id);
    final updated = await DatabaseService.instance.getEvents();
    if (mounted) setState(() => _events = updated);
  }

  Future<void> _onIdeaAdded(String text) async {
    final db = DatabaseService.instance;

    // Save immediately so data isn't lost even if AI fails
    final id = await db.insertIdea(text);
    var updated = await db.getIdeas();
    if (mounted) setState(() => _ideas = updated);

    // AI enrichment — card shows "AI 分析中..." until this completes
    final enrichment = await OpenAIService.instance.enrichIdea(text);
    if (enrichment != null) {
      final linksJson = jsonEncode(
        enrichment.links.map((l) => {'title': l.title, 'url': l.url}).toList(),
      );
      await db.updateIdeaAiResult(id, enrichment.summary, linksJson);
    }

    updated = await db.getIdeas();
    if (mounted) setState(() => _ideas = updated);
  }

  Future<void> _onIdeaDeleted(int id) async {
    await DatabaseService.instance.deleteIdea(id);
    final updated = await DatabaseService.instance.getIdeas();
    if (mounted) setState(() => _ideas = updated);
  }

  Future<void> _onNotesMutated() async {
    final updated = await DatabaseService.instance.getNotes();
    if (mounted) setState(() => _notes = updated);
  }

  // Fire-and-forget: classify a newly inserted note into a user category.
  Future<void> _classifyInsertedNote(int noteId, String content) async {
    final db = DatabaseService.instance;
    final categories = await db.getNoteCategories();
    if (categories.isEmpty) return;
    final catId = await OpenAIService.instance.classifyNoteToCategory(content, categories);
    if (catId == null) return;
    await db.updateNoteCat(noteId, catId);
  }

  void _onItemClassified(ClassificationResult r) async {
    final db = DatabaseService.instance;

    switch (r) {
      case ClassifiedTodo():
        final color = kCatColors[r.cat] ?? AppColors.rose;
        await db.insertTodo(TodoItem(id: 0, text: r.text, done: false, cat: r.cat, color: color));
        final todos = await db.getTodos();
        if (mounted) setState(() => _todos = todos);

      case ClassifiedTodoWithTime():
        final color = kCatColors[r.cat] ?? AppColors.rose;
        final results = await Future.wait([
          db.insertEvent(CalendarEvent(
            id: 0,
            title: r.text,
            startYear: r.startYear,   startMonth: r.startMonth,
            startDay: r.startDay, startHour: r.startHour, startMin: r.startMin,
            endYear: r.endYear,   endMonth: r.endMonth,
            endDay: r.endDay,   endHour: r.endHour,   endMin: r.endMin,
            color: color,
          )),
        ]);
        // Only fetch after both inserts complete
        if (results.isNotEmpty) {
          final todos  = await db.getTodos();
          final events = await db.getEvents();
          if (mounted) setState(() { _todos = todos; _events = events; });
        }

      case ClassifiedIdea():
        await _onIdeaAdded(r.text);

      case ClassifiedNote():
        final id = await db.upsertNote(r.dateKey, r.content);
        final notes = await db.getNotes();
        if (mounted) setState(() => _notes = notes);
        if (id > 0) _classifyInsertedNote(id, r.content);

      case ClassifiedRecap():
        await db.insertRecapItem(RecapItem(
          id: '0',
          era: r.era,
          title: r.title,
          desc: r.desc,
          completedDate: r.era == Era.past ? r.date : null,
          targetDate:    r.era != Era.past ? r.date : null,
        ));

      case ClassificationError():
        final raw = r.rawText;
        if (raw != null && raw.isNotEmpty) {
          await db.upsertNote(todayKey(), raw);
          final notes = await db.getNotes();
          if (mounted) setState(() => _notes = notes);
        }
    }
  }

  static const _pageTitles = ['行事曆', '待辦', '靈感', '筆記', '回顧'];

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
      child: Row(
        children: [
          MrIconButton(
            icon: LucideIcons.plus,
            bg: AppColors.dark,
            iconColor: Colors.white,
            showBorder: false,
            borderRadius: 13,
            onTap: () => setState(() => _overlay = _Overlay.add),
          ),
          const Spacer(),
          Text('myroom', style: AppText.display(size: 23, weight: FontWeight.w400, italic: true)),
          const Spacer(),
          Row(
            children: [
              MrIconButton(
                icon: LucideIcons.search,
                iconSize: 17,
                onTap: () => setState(() => _overlay = _Overlay.ai),
              ),
              const SizedBox(width: 7),
              MrIconButton(
                icon: LucideIcons.user,
                iconSize: 16,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingPage()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageTitle() {
    if (_activeTab == 0 || _activeTab == 4) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_pageTitles[_activeTab], style: AppText.display()),
          const SizedBox(height: 3),
          Text('${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日，星期${kDow[DateTime.now().weekday % 7]}', style: AppText.caption()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: SizedBox(
            width: 28, height: 28,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(),
                _buildPageTitle(),
                Expanded(
                  child: ClipRect(
                    child: IndexedStack(
                      index: _activeTab,
                      children: [
                        CalendarPage(events: _events, onEventAdded: _onEventAdded, onEventDeleted: _onEventDeleted),
                        TodoPage(
                          todos: _todos,
                          categories: _categories,
                          onTodoAdded: _onTodoAdded,
                          onTodoToggled: _onTodoToggled,
                          onTodoDeleted: _onTodoDeleted,
                          onCategoryAdded: _onCategoryAdded,
                          onCategoryDeleted: _onCategoryDeleted,
                        ),
                        IdeaPage(ideas: _ideas, onIdeaAdded: _onIdeaAdded, onIdeaDeleted: _onIdeaDeleted),
                        NotePage(notes: _notes, onNotesMutated: _onNotesMutated),
                        RecapPage(
                          onNavTo: (tab) => setState(() => _activeTab = tab),
                          todos: _todos,
                          events: _events,
                          ideas: _ideas,
                          notes: _notes,
                          recapItems: _recapItems,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (_overlay == _Overlay.ai)
              AIChatOverlay(
                onClose: () => setState(() => _overlay = _Overlay.none),
                onDataMutated: _loadAll,
              ),
            if (_overlay == _Overlay.add)
              AddOverlay(
                onClose: () => setState(() => _overlay = _Overlay.none),
                onItemClassified: _onItemClassified,
              ),
            
            
            if (_overlay == _Overlay.none)
              Positioned(
                bottom: 22, left: 20, right: 20,
                child: BottomNavBar(
                  activeIndex: _activeTab,
                  onTap: (i) => setState(() {
                    _activeTab = i;
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
