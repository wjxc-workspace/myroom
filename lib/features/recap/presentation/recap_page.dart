import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/app_errors.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/ai/domain/ai_service.dart';
import '../../calendar/domain/event.dart';
import '../../calendar/domain/event_repo.dart';
import '../../ideas/domain/idea.dart';
import '../../ideas/domain/idea_repo.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_repo.dart';
import '../../todo/domain/todo.dart';
import '../../todo/domain/todo_repo.dart';
import '../domain/achievement.dart';
import '../domain/achievement_repo.dart';
import '../domain/recap.dart';
import '../domain/recap_repo.dart';

// ─── Era model (local — the design's `Era` enum + theme maps) ──────────────────

enum _Era { past, now, future }

const _eraColor = <_Era, Color>{
  _Era.past: AppColors.amber,
  _Era.now: AppColors.sage,
  _Era.future: AppColors.blue,
};
const _eraLabel = <_Era, String>{
  _Era.past: '過去',
  _Era.now: '現在',
  _Era.future: '未來',
};
const _eraSubtitle = <_Era, String>{
  _Era.past: '成就回顧',
  _Era.now: '3個月目標',
  _Era.future: '長遠願景',
};
const _eraIcon = <_Era, IconData>{
  _Era.past: LucideIcons.milestone,
  _Era.now: LucideIcons.compass,
  _Era.future: LucideIcons.sparkles,
};

String _fmt2(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

/// A single era-tagged review card (the design's `RecapItem`). Built from the
/// user's [Achievement] era blocks and [Recap] entries — there is no dedicated
/// "recap item" document in this app.
class _RecapItem {
  final _Era era;
  final String title;
  final String desc;
  final String displayDate;
  const _RecapItem({
    required this.era,
    required this.title,
    required this.desc,
    required this.displayDate,
  });
}

List<_RecapItem> _buildRecapItems(
  List<Achievement> achievements,
  List<Recap> recaps,
) {
  final items = <_RecapItem>[];

  for (final a in achievements) {
    final date = _fmtDate(a.createdAt);
    void addBlock(_Era era, String content) {
      final trimmed = content.trim();
      if (trimmed.isEmpty) return;
      final nl = trimmed.indexOf('\n');
      final title = nl == -1 ? trimmed : trimmed.substring(0, nl).trim();
      final desc = nl == -1 ? '' : trimmed.substring(nl + 1).trim();
      items.add(_RecapItem(
          era: era, title: title, desc: desc, displayDate: date));
    }

    addBlock(_Era.past, a.pastContent);
    addBlock(_Era.now, a.currentContent);
    addBlock(_Era.future, a.futureContent);
  }

  // Titled recaps are reviews of past time → surfaced as past milestones.
  for (final r in recaps) {
    items.add(_RecapItem(
      era: _Era.past,
      title: r.title.isEmpty ? '無標題' : r.title,
      desc: r.content,
      displayDate: _fmtDate(r.createdAt),
    ));
  }

  return items;
}

// ─── AI content per era ───────────────────────────────────────────────────────

class _AIContent {
  String? insight;
  bool loading = false;
  bool loaded = false;
}

// ─── RecapPage (provider wiring) ──────────────────────────────────────────────

/// Recap tab — an era journey (過去 / 現在 / 未來) over the user's live data.
/// Streams todos, events, ideas, notes, achievements and recaps; the app shell
/// supplies the top bar, page title and bottom nav.
class RecapPage extends StatelessWidget {
  const RecapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        StreamProvider<List<Todo>>(
          create: (c) => c.read<TodoRepo>().watchTodos(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <Todo>[];
          },
        ),
        StreamProvider<List<CalendarEvent>>(
          create: (c) => c.read<EventRepo>().watchEvents(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <CalendarEvent>[];
          },
        ),
        StreamProvider<List<Idea>>(
          create: (c) => c.read<IdeaRepo>().watchIdeas(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <Idea>[];
          },
        ),
        StreamProvider<List<Note>>(
          create: (c) => c.read<NoteRepo>().watchNotes(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <Note>[];
          },
        ),
        StreamProvider<List<Achievement>>(
          create: (c) => c.read<AchievementRepo>().watchAchievements(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <Achievement>[];
          },
        ),
        StreamProvider<List<Recap>>(
          create: (c) => c.read<RecapRepo>().watchRecaps(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <Recap>[];
          },
        ),
      ],
      child: const _RecapBody(),
    );
  }
}

class _RecapBody extends StatefulWidget {
  const _RecapBody();

  @override
  State<_RecapBody> createState() => _RecapBodyState();
}

class _RecapBodyState extends State<_RecapBody> {
  static const _dow = ['日', '一', '二', '三', '四', '五', '六'];
  bool _showMonthly = false;

  @override
  Widget build(BuildContext context) {
    final todos = context.watch<List<Todo>>();
    final events = context.watch<List<CalendarEvent>>();
    final ideas = context.watch<List<Idea>>();
    final notes = context.watch<List<Note>>();
    final achievements = context.watch<List<Achievement>>();
    final recaps = context.watch<List<Recap>>();

    final now = DateTime.now();
    final dateStr =
        '${now.year}年${now.month}月${now.day}日，星期${_dow[now.weekday % 7]}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title row — replaces AppScaffold._buildPageTitle for this tab
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _showMonthly ? '月旬' : '時光軸',
                    style: AppText.display(),
                  ),
                  const SizedBox(height: 3),
                  Text(dateStr, style: AppText.caption()),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _SubTabSwitcher(
                  showMonthly: _showMonthly,
                  onToggle: (v) => setState(() => _showMonthly = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(-0.06, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: anim,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              ),
            ),
            child: _showMonthly
                ? _MonthlyView(
                    key: const ValueKey('monthly'),
                    todos: todos,
                    events: events,
                    notes: notes,
                  )
                : _RecapView(
                    key: const ValueKey('recap'),
                    todos: todos,
                    events: events,
                    ideas: ideas,
                    notes: notes,
                    recapItems: _buildRecapItems(achievements, recaps),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── RecapView (era panel + vertical pager) ───────────────────────────────────

class _RecapView extends StatefulWidget {
  final List<Todo> todos;
  final List<CalendarEvent> events;
  final List<Idea> ideas;
  final List<Note> notes;
  final List<_RecapItem> recapItems;

  const _RecapView({
    super.key,
    required this.todos,
    required this.events,
    required this.ideas,
    required this.notes,
    required this.recapItems,
  });

  @override
  State<_RecapView> createState() => _RecapViewState();
}

class _RecapViewState extends State<_RecapView> {
  late final PageController _pageCtrl;
  int _eraIdx = 1; // 現在

  static const _eras = _Era.values;

  final Map<_Era, _AIContent> _ai = {
    for (final e in _Era.values) e: _AIContent(),
  };

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: _eraIdx);
    _loadAI(_eras[_eraIdx]);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goToEra(int idx) {
    setState(() => _eraIdx = idx);
    _loadAI(_eras[idx]);
    if (_pageCtrl.hasClients) {
      _pageCtrl.animateToPage(idx,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _loadAI(_Era era) async {
    final c = _ai[era]!;
    if (c.loaded || c.loading) return;
    setState(() => c.loading = true);

    final res = await context.read<AiService>().generateEraInsight(
          eraLabel: _eraLabel[era]!,
          dataSummary: _dataSummary(era),
        );
    if (!mounted) return;
    setState(() {
      if (res is Ok<String> && res.value.trim().isNotEmpty) {
        c.insight = res.value.trim();
      }
      c.loading = false;
      c.loaded = true;
    });
  }

  // ── AI prompt input ─────────────────────────────────────────────────────────

  String _dataSummary(_Era era) {
    final buf = StringBuffer();
    switch (era) {
      case _Era.past:
        final done = widget.todos.where((t) => t.isCompleted).toList();
        buf.writeln('已完成任務：${done.length} 項');
        buf.writeln('札記：${widget.notes.length} 頁');
        buf.writeln(
            '里程碑：${widget.recapItems.where((r) => r.era == _Era.past).length} 個');
        if (done.isNotEmpty) {
          buf.writeln('代表任務：${done.take(3).map((t) => t.title).join('、')}');
        }
      case _Era.now:
        final active = widget.todos.where((t) => !t.isCompleted).toList();
        buf.writeln('進行中任務：${active.length} 項');
        buf.writeln('3個月內行程：${_upcomingEvents().length} 個');
        if (active.isNotEmpty) {
          buf.writeln('主要待辦：${active.take(3).map((t) => t.title).join('、')}');
        }
      case _Era.future:
        buf.writeln('靈感：${widget.ideas.length} 個');
        buf.writeln(
            '長期願景：${widget.recapItems.where((r) => r.era == _Era.future).length} 個');
        if (widget.ideas.isNotEmpty) {
          buf.writeln('靈感包括：${widget.ideas.take(3).map((i) => i.text).join('、')}');
        }
    }
    final out = buf.toString().trim();
    return out.isEmpty ? '（使用者尚未填寫內容，請給予溫暖、具體的鼓勵）' : out;
  }

  List<CalendarEvent> _upcomingEvents() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = DateTime(now.year, now.month + 3, now.day);
    return widget.events.where((e) {
      final d = DateTime(
          e.startTime.year, e.startTime.month, e.startTime.day);
      return !d.isBefore(today) && d.isBefore(cutoff);
    }).toList();
  }

  // ── Era panel summaries ─────────────────────────────────────────────────────

  String _eraSummary(_Era era) {
    switch (era) {
      case _Era.past:
        final done = widget.todos.where((t) => t.isCompleted).length;
        return '完成 $done 項 · ${widget.notes.length} 頁札記';
      case _Era.now:
        final active = widget.todos.where((t) => !t.isCompleted).length;
        return '$active 項待辦 · ${_upcomingEvents().length} 個行程';
      case _Era.future:
        return '${widget.ideas.length} 個靈感孕育中';
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(-60 * (1 - v), 0),
          child: child,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                    right: BorderSide(color: AppColors.border, width: 1)),
              ),
              child: _buildEraPanel(),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              physics: const _SlowPagePhysics(),
              scrollDirection: Axis.vertical,
              itemCount: _eras.length,
              onPageChanged: (idx) {
                setState(() => _eraIdx = idx);
                _loadAI(_eras[idx]);
              },
              itemBuilder: (_, i) {
                final era = _eras[i];
                final ai = _ai[era]!;
                return _EraPage(
                  era: era,
                  recapItems:
                      widget.recapItems.where((r) => r.era == era).toList(),
                  todos: widget.todos,
                  upcoming: _upcomingEvents(),
                  ideas: widget.ideas,
                  notes: widget.notes,
                  insight: ai.insight,
                  aiLoading: ai.loading,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEraPanel() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 120),
      children: List.generate(_eras.length, (i) {
        final era = _eras[i];
        final c = _eraColor[era]!;
        final isActive = i == _eraIdx;
        final count = widget.recapItems.where((r) => r.era == era).length;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _goToEra(i),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      width: isActive ? 13 : 8,
                      height: isActive ? 13 : 8,
                      decoration: BoxDecoration(
                        color: c.withOpacity(isActive ? 1.0 : 0.35),
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                    color: c.withOpacity(0.3),
                                    blurRadius: 0,
                                    spreadRadius: 3)
                              ]
                            : null,
                      ),
                    ),
                    if (i < _eras.length - 1)
                      Container(
                          width: 1, height: 68, color: c.withOpacity(0.15)),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.mix(c, Colors.white, 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _eraLabel[era]!,
                          style: AppText.caption(
                            size: 13,
                            weight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive ? c : AppColors.dark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(_eraSubtitle[era]!,
                            style:
                                AppText.caption(size: 10, color: AppColors.muted)),
                        const SizedBox(height: 4),
                        Text(
                          _eraSummary(era),
                          style: AppText.caption(
                              size: 10, color: isActive ? c : AppColors.muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (count > 0) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$count 個項目',
                                style: AppText.caption(
                                    size: 9,
                                    color: c,
                                    weight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ─── Era page ─────────────────────────────────────────────────────────────────

class _EraPage extends StatelessWidget {
  final _Era era;
  final List<_RecapItem> recapItems;
  final List<Todo> todos;
  final List<CalendarEvent> upcoming;
  final List<Idea> ideas;
  final List<Note> notes;
  final String? insight;
  final bool aiLoading;

  const _EraPage({
    required this.era,
    required this.recapItems,
    required this.todos,
    required this.upcoming,
    required this.ideas,
    required this.notes,
    required this.insight,
    required this.aiLoading,
  });

  @override
  Widget build(BuildContext context) {
    final c = _eraColor[era]!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImage(c),
          const SizedBox(height: 12),
          _buildInsight(c),
          const SizedBox(height: 18),
          _buildData(c),
          if (recapItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionTitle(label: _itemsLabel, color: c),
            const SizedBox(height: 10),
            ...recapItems.map((r) => _RecapItemCard(item: r, color: c)),
          ],
        ],
      ),
    );
  }

  String get _itemsLabel {
    switch (era) {
      case _Era.past:
        return '里程碑';
      case _Era.now:
        return '主要目標';
      case _Era.future:
        return '長期願景';
    }
  }

  // ── Hero banner (gradient + faded era glyph; no image backend) ──────────────

  Widget _buildImage(Color c) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 172,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.mix(c, Colors.white, 0.12),
                    AppColors.mix(c, Colors.white, 0.32),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -10,
              bottom: -18,
              child: Icon(_eraIcon[era]!,
                  size: 150, color: Colors.white.withOpacity(0.35)),
            ),
            Positioned(
              bottom: 10,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 5,
                        height: 5,
                        decoration:
                            BoxDecoration(color: c, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(
                      _eraLabel[era]!,
                      style: AppText.caption(
                          size: 9,
                          color: Colors.white,
                          weight: FontWeight.w700,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Insight section ──────────────────────────────────────────────────────────

  Widget _buildInsight(Color c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.mix(c, Colors.white, 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.sparkles, size: 14, color: c),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: aiLoading && insight == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonLine(color: c, widthFactor: 1.0),
                      const SizedBox(height: 7),
                      _SkeletonLine(color: c, widthFactor: 0.8),
                      const SizedBox(height: 7),
                      _SkeletonLine(color: c, widthFactor: 0.6),
                    ],
                  )
                : Text(
                    insight ?? _fallback,
                    style: AppText.body(size: 13, height: 1.7),
                  ),
          ),
        ],
      ),
    );
  }

  String get _fallback {
    switch (era) {
      case _Era.past:
        return '回顧過去，每一步都算數。你已經走了很長的路，這些成果值得被好好記住。';
      case _Era.now:
        return '此刻是最好的起點。一步一步前進，你正在朝著目標靠近。';
      case _Era.future:
        return '每一個夢想都始於一個念頭。把它們記下來，是讓它成真的第一步。';
    }
  }

  // ── Data section ─────────────────────────────────────────────────────────────

  Widget _buildData(Color c) {
    switch (era) {
      case _Era.past:
        return _pastData(c);
      case _Era.now:
        return _nowData(c);
      case _Era.future:
        return _futureData(c);
    }
  }

  Widget _pastData(Color c) {
    final done = todos.where((t) => t.isCompleted).toList();
    final noteList = [...notes]
      ..sort((a, b) => b.dateKey.compareTo(a.dateKey));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatsRow(color: c, chips: [
          _StatData('${done.length}', '已完成\n任務'),
          _StatData('${noteList.length}', '札記\n頁數'),
          _StatData('${recapItems.length}', '達成\n里程碑'),
        ]),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle(label: '完成的任務', color: c),
          const SizedBox(height: 8),
          ...done.take(5).map((t) => _TodoRow(todo: t)),
          if (done.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('還有 ${done.length - 5} 項…',
                  style: AppText.caption(size: 11, color: AppColors.muted)),
            ),
        ],
        if (noteList.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle(label: '近期札記', color: c),
          const SizedBox(height: 8),
          ...noteList.take(2).map((n) => _NoteCard(note: n)),
        ],
      ],
    );
  }

  Widget _nowData(Color c) {
    final active = todos.where((t) => !t.isCompleted).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final sortedUpcoming = [...upcoming]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatsRow(color: c, chips: [
          _StatData('${active.length}', '進行中\n任務'),
          _StatData('${sortedUpcoming.length}', '近期\n行程'),
          _StatData('${recapItems.length}', '主要\n目標'),
        ]),
        if (active.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle(label: '待完成的任務', color: c, sub: '依優先度'),
          const SizedBox(height: 8),
          ...active.take(5).map((t) => _TodoRow(todo: t)),
          if (active.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('還有 ${active.length - 5} 項…',
                  style: AppText.caption(size: 11, color: AppColors.muted)),
            ),
        ],
        if (sortedUpcoming.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle(label: '近 3 個月行程', color: c),
          const SizedBox(height: 8),
          ...sortedUpcoming.take(5).map((e) => _EventRow(event: e)),
          if (sortedUpcoming.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('還有 ${sortedUpcoming.length - 5} 項…',
                  style: AppText.caption(size: 11, color: AppColors.muted)),
            ),
        ],
      ],
    );
  }

  Widget _futureData(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatsRow(color: c, chips: [
          _StatData('${ideas.length}', '靈感\n想法'),
          _StatData('${recapItems.length}', '長期\n願景'),
        ]),
        if (ideas.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle(label: '靈感與想法', color: c),
          const SizedBox(height: 8),
          ...ideas.map((i) => _IdeaRow(idea: i, color: c)),
        ],
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String label;
  final Color color;
  final String? sub;
  const _SectionTitle({required this.label, required this.color, this.sub});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 7),
        Text(label,
            style: AppText.caption(
                size: 12, weight: FontWeight.w700, color: AppColors.dark)),
        if (sub != null) ...[
          const SizedBox(width: 6),
          Text(sub!, style: AppText.caption(size: 10, color: AppColors.muted)),
        ],
      ],
    );
  }
}

class _StatData {
  final String value;
  final String label;
  const _StatData(this.value, this.label);
}

class _StatsRow extends StatelessWidget {
  final Color color;
  final List<_StatData> chips;
  const _StatsRow({required this.color, required this.chips});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: chips
          .map((d) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: AppColors.mix(color, Colors.white, 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.15)),
                  ),
                  child: Column(
                    children: [
                      Text(d.value,
                          style: AppText.display(
                              size: 20, weight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(d.label,
                          style:
                              AppText.caption(size: 9, color: AppColors.muted),
                          textAlign: TextAlign.center,
                          maxLines: 2),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final Color color;
  final double widthFactor;
  const _SkeletonLine({required this.color, required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 11,
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  final Todo todo;
  const _TodoRow({required this.todo});

  @override
  Widget build(BuildContext context) {
    final c = todo.category.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: todo.isCompleted ? c : Colors.transparent,
              border: Border.all(color: c, width: 1.5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              todo.title,
              style: AppText.caption(
                      size: 12,
                      color: todo.isCompleted ? AppColors.muted : AppColors.dark)
                  .copyWith(
                      decoration: todo.isCompleted
                          ? TextDecoration.lineThrough
                          : null),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(todo.category.label,
                style: AppText.caption(size: 9, color: c)),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final CalendarEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final s = event.startTime;
    final dateStr = '${s.month}/${s.day}';
    final timeStr =
        event.isAllDay ? '全天' : '${_fmt2(s.hour)}:${_fmt2(s.minute)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: event.color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(dateStr,
              style: AppText.caption(
                  size: 11, color: AppColors.muted, weight: FontWeight.w600)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(event.title,
                style: AppText.caption(size: 12, color: AppColors.dark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text(timeStr, style: AppText.caption(size: 10, color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final content = note.content;
    final preview =
        content.length > 65 ? '${content.substring(0, 65)}…' : content;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note.dateKey.isEmpty ? note.title : note.dateKey,
              style: AppText.caption(size: 10, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(preview.isEmpty ? '（無內容）' : preview,
              style: AppText.caption(size: 12, color: AppColors.dark)
                  .copyWith(height: 1.55)),
        ],
      ),
    );
  }
}

class _IdeaRow extends StatelessWidget {
  final Idea idea;
  final Color color;
  const _IdeaRow({required this.idea, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(LucideIcons.lightbulb, size: 12, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(idea.text,
                    style: AppText.caption(size: 12, color: AppColors.dark),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (idea.aiSummary != null &&
                    idea.aiSummary!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(idea.aiSummary!,
                      style: AppText.caption(size: 10, color: AppColors.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapItemCard extends StatelessWidget {
  final _RecapItem item;
  final Color color;
  const _RecapItemCard({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.22), width: 1.5),
        boxShadow: const [kCardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(item.title,
                    style: AppText.body(
                        size: 14,
                        weight: FontWeight.w600,
                        color: AppColors.dark)),
              ),
              const SizedBox(width: 8),
              Text(item.displayDate,
                  style: AppText.caption(size: 11, color: color)),
            ],
          ),
          if (item.desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.desc,
                style: AppText.caption(size: 12, color: AppColors.muted)
                    .copyWith(height: 1.6),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

// ─── Sub-page tab switcher ────────────────────────────────────────────────────

class _SubTabSwitcher extends StatelessWidget {
  const _SubTabSwitcher({required this.showMonthly, required this.onToggle});
  final bool showMonthly;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SubTab(
              label: '時光軸',
              active: !showMonthly,
              onTap: () => onToggle(false)),
          _SubTab(
              label: '月旬',
              active: showMonthly,
              onTap: () => onToggle(true)),
        ],
      ),
    );
  }
}

class _SubTab extends StatelessWidget {
  const _SubTab(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.dark : Colors.transparent,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Text(
          label,
          style: AppText.caption(
            size: 12,
            weight: FontWeight.w600,
            color: active ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

// ─── Monthly view (月旬) ──────────────────────────────────────────────────────

class _MonthlyView extends StatefulWidget {
  const _MonthlyView({
    super.key,
    required this.todos,
    required this.events,
    required this.notes,
  });
  final List<Todo> todos;
  final List<CalendarEvent> events;
  final List<Note> notes;

  @override
  State<_MonthlyView> createState() => _MonthlyViewState();
}

class _MonthlyViewState extends State<_MonthlyView>
    with SingleTickerProviderStateMixin {
  static const _warmAccent = Color(0xFFC8956C);

  static const _monthCn = [
    '', '一', '二', '三', '四', '五', '六',
    '七', '八', '九', '十', '十一', '十二',
  ];

  // Sentiment lexicon for client-side mood detection.
  // Positive values lift score toward 5 (happy), negative toward 1 (low).
  static const _moodLex = <String, int>{
    '開心': 2, '快樂': 2, '高興': 2, '興奮': 2, '幸福': 2,
    '感謝': 1, '感動': 1, '充實': 1, '進步': 1, '成功': 1,
    '順利': 1, '完成': 1, '滿足': 1, '輕鬆': 1, '享受': 1,
    '期待': 1, '有趣': 1, '愉快': 1, '放鬆': 1, '舒服': 1,
    '難過': -2, '沮喪': -2, '崩潰': -2, '痛苦': -2, '絕望': -2,
    '焦慮': -1, '擔心': -1, '煩惱': -1, '壓力': -1, '疲憊': -1,
    '疲倦': -1, '累': -1, '迷茫': -1, '困難': -1, '卡住': -1,
    '生氣': -1, '憤怒': -1, '後悔': -1, '失落': -1, '無聊': -1,
  };

  String? _selectedCat;
  String? _insight;
  bool _insightLoading = false;
  bool _insightLoaded = false;
  late AnimationController _enter;

  int get _year => DateTime.now().year;
  int get _month => DateTime.now().month;
  String get _monthKey => '$_year-${_month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _loadInsight();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  // Returns an animation for a specific stagger interval.
  Animation<double> _fade(double start, double end) => CurvedAnimation(
        parent: _enter,
        curve: Interval(start, end, curve: Curves.easeOut),
      );

  Animation<Offset> _slide(double start, double end) =>
      Tween<Offset>(begin: const Offset(-0.22, 0), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _enter,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );

  // Wraps [child] in a staggered fade + left-to-right slide.
  Widget _anim(Widget child, {required double start, required double end}) {
    return FadeTransition(
      opacity: _fade(start, end),
      child: SlideTransition(position: _slide(start, end), child: child),
    );
  }

  List<Note> get _monthNotes => widget.notes
      .where((n) => n.dateKey.startsWith(_monthKey))
      .toList()
    ..sort((a, b) => b.dateKey.compareTo(a.dateKey));

  List<CalendarEvent> get _monthEvents => widget.events
      .where((e) =>
          e.startTime.year == _year && e.startTime.month == _month)
      .toList();

  List<Todo> get _monthDone {
    final y = _year, m = _month;
    return widget.todos
        .where((t) =>
            t.isCompleted &&
            t.updatedAt.year == y &&
            t.updatedAt.month == m)
        .toList();
  }

  int get _photoCount => _monthNotes
      .where((n) => n.attachments.any((a) => a.type == 'image'))
      .length;

  List<String> get _categories {
    final seen = <String>{};
    final result = <String>[];
    for (final n in _monthNotes) {
      final l = n.category.label;
      if (l.isNotEmpty && l != '無分類' && seen.add(l)) result.add(l);
    }
    return result;
  }

  List<Note> get _filteredNotes {
    final mn = _monthNotes;
    if (_selectedCat == null) return mn;
    return mn.where((n) => n.category.label == _selectedCat).toList();
  }

  // Per-week mood scores (1–5) derived from sentiment analysis of note text.
  // Scans each note for words in _moodLex; empty weeks default to 3 (neutral).
  List<double> get _weeklyMoodScores {
    final weeks = [<Note>[], <Note>[], <Note>[], <Note>[]];
    for (final n in _monthNotes) {
      final dk = n.dateKey;
      if (dk.length < 10) continue;
      final day = int.tryParse(dk.substring(8, 10)) ?? 1;
      weeks[((day - 1) ~/ 7).clamp(0, 3)].add(n);
    }
    return weeks.map((wNotes) {
      if (wNotes.isEmpty) return 3.0;
      var sentiment = 0.0;
      var hits = 0;
      for (final n in wNotes) {
        final text = '${n.title} ${n.content}';
        for (final entry in _moodLex.entries) {
          var idx = 0;
          while (idx < text.length) {
            final pos = text.indexOf(entry.key, idx);
            if (pos == -1) break;
            sentiment += entry.value;
            hits++;
            idx = pos + entry.key.length;
          }
        }
      }
      if (hits == 0) return 3.0;
      return (3.0 + (sentiment / hits).clamp(-2.0, 2.0)).clamp(1.0, 5.0);
    }).toList();
  }

  // Most frequent mood words found in this month's notes (up to 6).
  List<String> get _moodKeywords {
    final counts = <String, int>{};
    for (final n in _monthNotes) {
      final text = '${n.title} ${n.content}';
      for (final word in _moodLex.keys) {
        if (text.contains(word)) {
          counts[word] = (counts[word] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) return [];
    return (counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(6)
        .map((e) => e.key)
        .toList();
  }

  Future<void> _loadInsight() async {
    if (_insightLoaded || _insightLoading) return;
    setState(() => _insightLoading = true);

    final notes = _monthNotes;
    final events = _monthEvents;
    final done = _monthDone;
    final keywords = _moodKeywords;
    final scores = _weeklyMoodScores;
    final avgScore = scores.reduce((a, b) => a + b) / scores.length;

    final buf = StringBuffer()
      ..writeln('月份：${_monthCn[_month]}月 $_year')
      ..writeln('行事曆行程：${events.length} 個')
      ..writeln('完成待辦：${done.length} 項')
      ..writeln('日記札記：${notes.length} 則')
      ..writeln('本月平均情緒分數（1-5）：${avgScore.toStringAsFixed(1)}');

    if (keywords.isNotEmpty) {
      buf.writeln('偵測到的情緒詞：${keywords.join('、')}');
    }

    if (notes.isNotEmpty) {
      buf.writeln('\n札記摘錄：');
      for (final n in notes.take(5)) {
        final title =
            (n.title.isNotEmpty && n.title != '無標題') ? n.title : '';
        final snippet = n.content.length > 80
            ? n.content.substring(0, 80)
            : n.content;
        final line = title.isNotEmpty ? '$title：$snippet' : snippet;
        if (line.trim().isNotEmpty) buf.writeln('・$line');
      }
    }

    if (done.isNotEmpty) {
      buf.writeln('完成任務：${done.take(3).map((t) => t.title).join('、')}');
    }

    final summary = buf.toString().trim();

    final res = await context.read<AiService>().generateEraInsight(
          eraLabel: '本月生活狀態回顧',
          dataSummary:
              summary.isEmpty ? '（本月尚無記錄，請給予溫暖的鼓勵）' : summary,
        );
    if (!mounted) return;
    setState(() {
      if (res is Ok<String> && res.value.trim().isNotEmpty) {
        _insight = res.value.trim();
      }
      _insightLoading = false;
      _insightLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categories;
    final events = _monthEvents;
    final done = _monthDone;
    final notes = _monthNotes;
    final filtered = _filteredNotes;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ① Hero
          _anim(_buildHero(), start: 0.0, end: 0.5),
          const SizedBox(height: 14),

          // ② Category chips + stats
          _anim(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cats.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children:
                        cats.map((c) => _MthChip(label: '#$c')).toList(),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    _MthStat(
                        icon: LucideIcons.calendar,
                        value: '${events.length}',
                        label: '行事曆',
                        unit: '件'),
                    _MthStat(
                        icon: LucideIcons.squareCheck,
                        value: '${done.length}',
                        label: '完成待辦',
                        unit: '件'),
                    _MthStat(
                        icon: LucideIcons.fileText,
                        value: '${notes.length}',
                        label: '札記',
                        unit: '則'),
                    _MthStat(
                        icon: LucideIcons.image,
                        value: '$_photoCount',
                        label: '照片',
                        unit: '張'),
                  ],
                ),
              ],
            ),
            start: 0.14,
            end: 0.62,
          ),
          const SizedBox(height: 22),

          // ③ 主題與亮點
          _anim(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _SectionTitle(
                        label: '主題與亮點', color: _warmAccent),
                    if (cats.isNotEmpty) _buildCatFilter(cats),
                  ],
                ),
                const SizedBox(height: 10),
                _buildHighlightCards(filtered),
              ],
            ),
            start: 0.28,
            end: 0.75,
          ),
          const SizedBox(height: 22),

          // ④ 反思與心情 + AI 觀察
          _anim(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(label: '反思與心情', color: _warmAccent),
                const SizedBox(height: 12),
                _buildReflection(),
                const SizedBox(height: 14),
                _buildInsightBox(),
              ],
            ),
            start: 0.42,
            end: 0.88,
          ),
        ],
      ),
    );
  }

  Widget _buildCatFilter(List<String> cats) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _MthFilterChip(
            label: '全部',
            active: _selectedCat == null,
            onTap: () => setState(() => _selectedCat = null),
          ),
          ...cats.map(
            (c) => _MthFilterChip(
              label: c,
              active: _selectedCat == c,
              onTap: () =>
                  setState(() => _selectedCat = _selectedCat == c ? null : c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightCards(List<Note> notes) {
    if (notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('本月暫無札記',
            style: AppText.caption(size: 13, color: AppColors.muted)),
      );
    }
    final items = notes.take(12).toList();
    return SizedBox(
      height: 188,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (_, i) => _MthHighlightCard(note: items[i]),
      ),
    );
  }

  Widget _buildReflection() {
    final keywords = _moodKeywords;
    final scores = _weeklyMoodScores;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: mood trend chart with emoji Y-axis
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本月心情趨勢',
                    style: AppText.caption(size: 11, color: AppColors.muted)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Emoji Y-axis: top / mid / bottom
                    const SizedBox(
                      width: 22,
                      height: 115,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('😊', style: TextStyle(fontSize: 10)),
                          Text('😐', style: TextStyle(fontSize: 10)),
                          Text('😟', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SizedBox(
                        height: 115,
                        child: CustomPaint(
                          painter: _TrendPainter(
                              scores: scores, lineColor: _warmAccent),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('第1週',
                          style: AppText.caption(
                              size: 9, color: AppColors.muted)),
                      Text('第2週',
                          style: AppText.caption(
                              size: 9, color: AppColors.muted)),
                      Text('第3週',
                          style: AppText.caption(
                              size: 9, color: AppColors.muted)),
                      Text('第4週',
                          style: AppText.caption(
                              size: 9, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 140, color: AppColors.border),
          const SizedBox(width: 14),
          // Right: mood keyword chips extracted from note content
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('心情關鍵字',
                    style: AppText.caption(size: 11, color: AppColors.muted)),
                const SizedBox(height: 8),
                if (keywords.isEmpty)
                  Text('本月尚未偵測到情緒詞',
                      style:
                          AppText.caption(size: 11, color: AppColors.muted))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: keywords.map((word) {
                      final positive = (_moodLex[word] ?? 0) > 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: positive
                              ? const Color(0xFFD6EDD6)
                              : const Color(0xFFF5EDE4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: positive
                                ? const Color(0xFF8BBB8B)
                                : _warmAccent.withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          word,
                          style: AppText.caption(
                              size: 11,
                              color: AppColors.dark,
                              weight: FontWeight.w500),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final mn = '${_monthCn[_month]}月';
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 168,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE8D9C4),
                    Color(0xFFD4B896),
                    Color(0xFFC8956C),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 18,
              top: 14,
              child: Icon(
                LucideIcons.leaf,
                size: 52,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$mn $_year',
                    style: AppText.display(size: 28, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '你的$mn月旬',
                    style: AppText.caption(
                        size: 13, color: const Color(0xFF5C3D1E)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EDE4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warmAccent.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.sparkles, size: 14, color: _warmAccent),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _insightLoading && _insight == null
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonLine(color: _warmAccent, widthFactor: 1.0),
                      SizedBox(height: 7),
                      _SkeletonLine(color: _warmAccent, widthFactor: 0.8),
                      SizedBox(height: 7),
                      _SkeletonLine(color: _warmAccent, widthFactor: 0.55),
                    ],
                  )
                : Text(
                    _insight ??
                        '這個月，每一則記錄都是你的一部分。慢下來回顧，你會發現更多。',
                    style: AppText.body(size: 13, height: 1.7),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Monthly sub-widgets ──────────────────────────────────────────────────────

class _MthStat extends StatelessWidget {
  const _MthStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.unit,
  });
  final IconData icon;
  final String value;
  final String label;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 17, color: AppColors.muted),
          const SizedBox(height: 5),
          Text(value,
              style: AppText.display(size: 20, weight: FontWeight.w700)),
          Text(
            '$label  $unit',
            style: AppText.caption(size: 9, color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MthChip extends StatelessWidget {
  const _MthChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label,
          style: AppText.caption(size: 12, color: AppColors.dark)),
    );
  }
}

class _MthFilterChip extends StatelessWidget {
  const _MthFilterChip(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.dark : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: active ? AppColors.dark : AppColors.border),
        ),
        child: Text(
          label,
          style: AppText.caption(
            size: 12,
            color: active ? Colors.white : AppColors.dark,
            weight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _MthHighlightCard extends StatelessWidget {
  const _MthHighlightCard({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final hasImg = note.attachments.any((a) => a.type == 'image');
    final content = note.content;
    final preview =
        content.length > 45 ? '${content.substring(0, 45)}…' : content;
    final dk = note.dateKey;
    final dateStr = dk.length >= 10
        ? '${int.parse(dk.substring(5, 7))}/${int.parse(dk.substring(8, 10))}'
        : dk;
    final title =
        (note.title.isEmpty || note.title == '無標題') ? '' : note.title;
    final catColor = note.category.color;

    return Container(
      width: 148,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [kCardShadow],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 100,
            width: double.infinity,
            color: catColor.withOpacity(hasImg ? 0.18 : 0.08),
            child: Center(
              child: Icon(
                hasImg ? LucideIcons.image : LucideIcons.fileText,
                size: 28,
                color: catColor.withOpacity(0.55),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isNotEmpty ? title : preview,
                  style: AppText.body(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.dark),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Text(
                  dateStr,
                  style: AppText.caption(size: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trend chart painter ─────────────────────────────────────────────────────

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.scores, required this.lineColor});

  // Each value is a mood score in the range [1, 5].
  final List<double> scores;
  final Color lineColor;

  // Maps score 1–5 to a y-coordinate (score 5 → top, score 1 → bottom).
  double _sy(double score, double h) => h * (1 - (score - 1) / 4.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.length < 2) return;

    // Very-light beige background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFFF9F2EB),
    );

    // Subtle horizontal guide lines at each score level (1–5)
    final guidePaint = Paint()
      ..color = const Color(0xFFD4B896).withOpacity(0.45)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    for (int s = 1; s <= 5; s++) {
      final y = _sy(s.toDouble(), size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
    }

    final step = size.width / (scores.length - 1);
    Offset pt(int i) => Offset(i * step, _sy(scores[i], size.height));

    // Fill area under the line
    final fillPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < scores.length; i++) {
      fillPath.lineTo(pt(i).dx, pt(i).dy);
    }
    fillPath
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = lineColor.withOpacity(0.12)
        ..style = PaintingStyle.fill,
    );

    // Main line
    final linePath = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < scores.length; i++) {
      linePath.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Circle dots — white fill + colored border
    final dotFill = Paint()
      ..color = const Color(0xFFF9F2EB)
      ..style = PaintingStyle.fill;
    final dotStroke = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < scores.length; i++) {
      canvas.drawCircle(pt(i), 4.5, dotFill);
      canvas.drawCircle(pt(i), 4.5, dotStroke);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.scores != scores || old.lineColor != lineColor;
}

// ─── Scroll physics ───────────────────────────────────────────────────────────

class _SlowPagePhysics extends PageScrollPhysics {
  const _SlowPagePhysics({super.parent});

  @override
  _SlowPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _SlowPagePhysics(parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      super.applyPhysicsToUserOffset(position, offset * 0.45);
}
