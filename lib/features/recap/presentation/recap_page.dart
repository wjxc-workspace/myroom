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

class _RecapBody extends StatelessWidget {
  const _RecapBody();

  @override
  Widget build(BuildContext context) {
    final todos = context.watch<List<Todo>>();
    final events = context.watch<List<CalendarEvent>>();
    final ideas = context.watch<List<Idea>>();
    final notes = context.watch<List<Note>>();
    final achievements = context.watch<List<Achievement>>();
    final recaps = context.watch<List<Recap>>();

    return _RecapView(
      todos: todos,
      events: events,
      ideas: ideas,
      notes: notes,
      recapItems: _buildRecapItems(achievements, recaps),
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
        buf.writeln('筆記：${widget.notes.length} 頁');
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
        return '完成 $done 項 · ${widget.notes.length} 頁筆記';
      case _Era.now:
        final active = widget.todos.where((t) => !t.isCompleted).length;
        return '$active 項待辦 · ${_upcomingEvents().length} 個行程';
      case _Era.future:
        return '${widget.ideas.length} 個靈感孕育中';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Container(
            decoration: const BoxDecoration(
              border:
                  Border(right: BorderSide(color: AppColors.border, width: 1)),
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
          _StatData('${noteList.length}', '筆記\n頁數'),
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
          _SectionTitle(label: '近期筆記', color: c),
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
