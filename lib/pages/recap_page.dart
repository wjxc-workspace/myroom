import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../data/seed_data.dart';
import '../models/recap_item.dart';
import '../models/todo_item.dart';
import '../models/event.dart';
import '../models/idea.dart';
import '../services/openai_service.dart';

// ─── AI content per era ───────────────────────────────────────────────────────

class _AIContent {
  String? insight;
  String? imageUrl;
  bool loading = false;
  bool loaded = false;
}

// ─── RecapPage ────────────────────────────────────────────────────────────────

class RecapPage extends StatefulWidget {
  final ValueChanged<int> onNavTo;
  final List<TodoItem> todos;
  final List<CalendarEvent> events;
  final List<Idea> ideas;
  final Map<String, String> notes;
  final List<RecapItem> recapItems;

  const RecapPage({
    super.key,
    required this.onNavTo,
    required this.todos,
    required this.events,
    required this.ideas,
    required this.notes,
    required this.recapItems,
  });

  @override
  State<RecapPage> createState() => _RecapPageState();
}

class _RecapPageState extends State<RecapPage> {
  late PageController _pageCtrl;
  int _eraIdx = 1;

  static const _eras = [Era.past, Era.now, Era.future];
  static const _eraSubtitles = {
    Era.past:   '成就回顧',
    Era.now:    '3個月目標',
    Era.future: '長遠願景',
  };

  final Map<Era, _AIContent> _ai = {
    for (final e in Era.values) e: _AIContent(),
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

  void _loadAI(Era era) {
    final c = _ai[era]!;
    if (c.loaded || c.loading) return;
    setState(() => c.loading = true);

    Future.wait([
      OpenAIService.instance.generateEraInsight(kEraLabel[era]!, _dataSummary(era)),
      OpenAIService.instance.generateEraImage(_imagePrompt(era)),
    ]).then((results) {
      if (!mounted) return;
      setState(() {
        c.insight  = results[0];
        c.imageUrl = results[1];
        c.loading  = false;
        c.loaded   = true;
      });
    });
  }

  String _dataSummary(Era era) {
    final buf = StringBuffer();
    switch (era) {
      case Era.past:
        final done = widget.todos.where((t) => t.done).toList();
        buf.writeln('已完成任務：${done.length} 項');
        buf.writeln('筆記：${widget.notes.length} 頁');
        buf.writeln('里程碑：${widget.recapItems.where((r) => r.era == Era.past).length} 個');
        if (done.isNotEmpty) {
          buf.writeln('代表任務：${done.take(3).map((t) => t.text).join('、')}');
        }

      case Era.now:
        final active = widget.todos.where((t) => !t.done).toList();
        final now = DateTime.now();
        final cutoff = DateTime(now.year, now.month + 3, now.day);
        final upcoming = widget.events.where((e) {
          final d = DateTime(e.startYear, e.startMonth, e.startDay);
          return !d.isBefore(DateTime(now.year, now.month, now.day)) && d.isBefore(cutoff);
        }).length;
        buf.writeln('進行中任務：${active.length} 項');
        buf.writeln('3個月內行程：$upcoming 個');
        if (active.isNotEmpty) {
          buf.writeln('主要待辦：${active.take(3).map((t) => t.text).join('、')}');
        }

      case Era.future:
        buf.writeln('靈感：${widget.ideas.length} 個');
        buf.writeln('長期願景：${widget.recapItems.where((r) => r.era == Era.future).length} 個');
        if (widget.ideas.isNotEmpty) {
          buf.writeln('靈感包括：${widget.ideas.take(3).map((i) => i.text).join('、')}');
        }
    }
    return buf.toString();
  }

  String _imagePrompt(Era era) {
    switch (era) {
      case Era.past:
        return 'Soft watercolor illustration of a cozy room with journals and warm candlelight, amber golden tones, nostalgic Japanese minimalist aesthetic, horizontal landscape format, no text, painterly style';
      case Era.now:
        return 'Clean minimalist illustration of a sunlit workspace with plants and a task list, sage green and white tones, modern flat design, calm energetic atmosphere, horizontal landscape format, no text';
      case Era.future:
        return 'Dreamy expansive illustration of a path toward glowing horizon with stars and floating lights, deep blue and indigo tones, abstract aspirational mood, horizontal landscape format, no text';
    }
  }

  String _eraSummary(Era era) {
    switch (era) {
      case Era.past:
        final done = widget.todos.where((t) => t.done).length;
        return '完成 $done 項 · ${widget.notes.length} 頁筆記';
      case Era.now:
        final active = widget.todos.where((t) => !t.done).length;
        final now = DateTime.now();
        final cutoff = DateTime(now.year, now.month + 3, now.day);
        final upcoming = widget.events.where((e) {
          final d = DateTime(e.startYear, e.startMonth, e.startDay);
          return !d.isBefore(DateTime(now.year, now.month, now.day)) && d.isBefore(cutoff);
        }).length;
        return '$active 項待辦 · $upcoming 個行程';
      case Era.future:
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
              border: Border(right: BorderSide(color: AppColors.border, width: 1)),
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
                recapItems: widget.recapItems.where((r) => r.era == era).toList(),
                todos: widget.todos,
                events: widget.events,
                ideas: widget.ideas,
                notes: widget.notes,
                insight: ai.insight,
                imageUrl: ai.imageUrl,
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
        final c = kEraColor[era]!;
        final isActive = i == _eraIdx;
        final count = widget.recapItems.where((r) => r.era == era).length;

        return GestureDetector(
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
                            ? [BoxShadow(color: c.withOpacity(0.3), blurRadius: 0, spreadRadius: 3)]
                            : null,
                      ),
                    ),
                    if (i < _eras.length - 1)
                      Container(width: 1, height: 68, color: c.withOpacity(0.15)),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.mix(c, Colors.white, 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kEraLabel[era]!,
                          style: AppText.caption(
                            size: 13,
                            weight: isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive ? c : AppColors.dark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(_eraSubtitles[era]!,
                            style: AppText.caption(size: 10, color: AppColors.muted)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$count 個項目',
                                style: AppText.caption(
                                    size: 9, color: c, weight: FontWeight.w600)),
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
  final Era era;
  final List<RecapItem> recapItems;
  final List<TodoItem> todos;
  final List<CalendarEvent> events;
  final List<Idea> ideas;
  final Map<String, String> notes;
  final String? insight;
  final String? imageUrl;
  final bool aiLoading;

  const _EraPage({
    required this.era,
    required this.recapItems,
    required this.todos,
    required this.events,
    required this.ideas,
    required this.notes,
    this.insight,
    this.imageUrl,
    required this.aiLoading,
  });

  @override
  Widget build(BuildContext context) {
    final c = kEraColor[era]!;
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
      case Era.past:   return '里程碑';
      case Era.now:    return '主要目標';
      case Era.future: return '長期願景';
    }
  }

  // ── Image section ──────────────────────────────────────────────────────────

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
                    AppColors.mix(c, Colors.white, 0.05),
                    AppColors.mix(c, Colors.white, 0.22),
                  ],
                ),
              ),
            ),
            if (imageUrl != null)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            if (aiLoading && imageUrl == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: c),
                    ),
                    const SizedBox(height: 8),
                    Text('生成插圖中…', style: AppText.caption(size: 10, color: c)),
                  ],
                ),
              ),
            Positioned(
              bottom: 10, left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(
                      kEraLabel[era]!.toUpperCase(),
                      style: AppText.caption(
                          size: 9, color: Colors.white,
                          weight: FontWeight.w700, letterSpacing: 1),
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

  // ── Insight section ────────────────────────────────────────────────────────

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
                    style: AppText.label(size: 13).copyWith(height: 1.7),
                  ),
          ),
        ],
      ),
    );
  }

  String get _fallback {
    switch (era) {
      case Era.past:
        return '回顧過去，每一步都算數。你已經走了很長的路，這些成果值得被好好記住。';
      case Era.now:
        return '此刻是最好的起點。一步一步前進，你正在朝著目標靠近。';
      case Era.future:
        return '每一個夢想都始於一個念頭。把它們記下來，是讓它成真的第一步。';
    }
  }

  // ── Data section ───────────────────────────────────────────────────────────

  Widget _buildData(Color c) {
    switch (era) {
      case Era.past:   return _pastData(c);
      case Era.now:    return _nowData(c);
      case Era.future: return _futureData(c);
    }
  }

  Widget _pastData(Color c) {
    final done = todos.where((t) => t.done).toList();
    final noteList = notes.entries.toList()..sort((a, b) => b.key.compareTo(a.key));

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
          ...noteList.take(2).map((e) => _NoteCard(dateKey: e.key, content: e.value)),
        ],
      ],
    );
  }

  Widget _nowData(Color c) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = DateTime(now.year, now.month + 3, now.day);

    final active = todos.where((t) => !t.done).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));

    final upcoming = events.where((e) {
      final d = DateTime(e.startYear, e.startMonth, e.startDay);
      return !d.isBefore(today) && d.isBefore(cutoff);
    }).toList()
      ..sort((a, b) => DateTime(a.startYear, a.startMonth, a.startDay)
          .compareTo(DateTime(b.startYear, b.startMonth, b.startDay)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatsRow(color: c, chips: [
          _StatData('${active.length}', '進行中\n任務'),
          _StatData('${upcoming.length}', '近期\n行程'),
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
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle(label: '近 3 個月行程', color: c),
          const SizedBox(height: 8),
          ...upcoming.take(5).map((e) => _EventRow(event: e)),
          if (upcoming.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('還有 ${upcoming.length - 5} 項…',
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
          width: 3, height: 13,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 7),
        Text(label,
            style: AppText.caption(size: 12, weight: FontWeight.w700, color: AppColors.dark)),
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
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: AppColors.mix(color, Colors.white, 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.15)),
                  ),
                  child: Column(
                    children: [
                      Text(d.value,
                          style: AppText.display(size: 20, weight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(d.label,
                          style: AppText.caption(size: 9, color: AppColors.muted),
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
  final TodoItem todo;
  const _TodoRow({required this.todo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: todo.done ? todo.color : Colors.transparent,
              border: Border.all(color: todo.color, width: 1.5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              todo.text,
              style: AppText.caption(
                      size: 12,
                      color: todo.done ? AppColors.muted : AppColors.dark)
                  .copyWith(
                      decoration: todo.done ? TextDecoration.lineThrough : null),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: todo.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(todo.cat, style: AppText.caption(size: 9, color: todo.color)),
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
    final dateStr = '${event.startMonth}/${event.startDay}';
    final timeStr =
        event.allDay ? '全天' : '${fmt2(event.startHour)}:${fmt2(event.startMin)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: event.color, shape: BoxShape.circle)),
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
  final String dateKey;
  final String content;
  const _NoteCard({required this.dateKey, required this.content});

  @override
  Widget build(BuildContext context) {
    final preview = content.length > 65
        ? '${content.substring(0, 65)}…'
        : content;
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
          Text(dateKey, style: AppText.caption(size: 10, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(preview,
              style:
                  AppText.caption(size: 12, color: AppColors.dark).copyWith(height: 1.55)),
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
                if (idea.aiSummary != null) ...[
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
  final RecapItem item;
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
            children: [
              Expanded(
                child: Text(item.title,
                    style: AppText.caption(
                        size: 14, weight: FontWeight.w600, color: AppColors.dark)),
              ),
              Text(item.displayDate, style: AppText.caption(size: 11, color: color)),
            ],
          ),
          if (item.desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.desc,
                style:
                    AppText.caption(size: 12, color: AppColors.muted).copyWith(height: 1.6),
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
