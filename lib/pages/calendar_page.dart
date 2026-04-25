import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../models/event.dart';
import '../data/seed_data.dart';
import '../widgets/mr_icon_button.dart';

enum CalendarView { month, week, day }

const int kHourH = 56;
const int kDayStart = 7;
const int kDayEnd = 22;
const int kBaseWeekStart = 19; // Sun Apr 19 2026

class CalendarPage extends StatefulWidget {
  final List<CalendarEvent> events;
  final ValueChanged<CalendarEvent> onEventAdded;

  const CalendarPage({
    super.key,
    required this.events,
    required this.onEventAdded,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarView _view = CalendarView.month;
  int _year = 2026;
  int _month = 3; // April (0-indexed)
  int _weekOffset = 0;
  int _dayView = 24;

  void _navigate(int delta) {
    setState(() {
      switch (_view) {
        case CalendarView.month:
          _month += delta;
          if (_month > 11) { _month = 0; _year++; }
          if (_month < 0) { _month = 11; _year--; }
        case CalendarView.week:
          _weekOffset += delta;
        case CalendarView.day:
          _dayView = (_dayView + delta).clamp(1, 30);
      }
    });
  }

  String get _headerLabel {
    switch (_view) {
      case CalendarView.month:
        return '$_year年${kMonthNames[_month]}';
      case CalendarView.week:
        final start = kBaseWeekStart + _weekOffset * 7;
        return '4月 $start – ${start + 6}日';
      case CalendarView.day:
        return '4月${_dayView}日';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 22, 8),
          child: Text('行事曆', style: AppText.display()),
        ),

        // View toggle + navigation
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
              // View toggle
              Container(
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: CalendarView.values.map((v) {
                    final active = _view == v;
                    final labels = ['月', '週', '日'];
                    return GestureDetector(
                      onTap: () => setState(() => _view = v),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: active ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: active ? const [kBtnShadow] : null,
                        ),
                        child: Text(
                          labels[v.index],
                          style: AppText.body(
                            size: 13,
                            weight: active ? FontWeight.w600 : FontWeight.w400,
                            color: active ? AppColors.dark : AppColors.muted,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Spacer(),
              // Nav chevrons
              MrIconButton(
                icon: LucideIcons.chevronLeft,
                iconSize: 16,
                onTap: () => _navigate(-1),
              ),
              const SizedBox(width: 6),
              Text(_headerLabel, style: AppText.body(size: 13, weight: FontWeight.w500)),
              const SizedBox(width: 6),
              MrIconButton(
                icon: LucideIcons.chevronRight,
                iconSize: 16,
                onTap: () => _navigate(1),
              ),
            ],
          ),
        ),

        Expanded(
          child: () {
            switch (_view) {
              case CalendarView.month:
                return _MonthView(
                  year: _year,
                  month: _month,
                  events: widget.events,
                  onDayTap: (d) => _showAddModal(selectedDay: d),
                );
              case CalendarView.week:
                return _WeekView(
                  weekStart: kBaseWeekStart + _weekOffset * 7,
                  events: widget.events,
                  onDayTap: (d) => setState(() {
                    _dayView = d;
                    _view = CalendarView.day;
                  }),
                );
              case CalendarView.day:
                return _DayView(
                  day: _dayView,
                  events: widget.events,
                  onAdd: () => _showAddModal(selectedDay: _dayView),
                );
            }
          }(),
        ),
      ],
    );
  }

  void _showAddModal({int? selectedDay}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEventModal(
        selectedDay: selectedDay,
        onSave: (e) => widget.onEventAdded(e),
      ),
    );
  }
}

// ─── Month View ───────────────────────────────────────────────────────────────

class _MonthView extends StatelessWidget {
  final int year, month;
  final List<CalendarEvent> events;
  final ValueChanged<int> onDayTap;

  const _MonthView({
    required this.year,
    required this.month,
    required this.events,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstDow = DateTime(year, month + 1, 1).weekday % 7; // 0=Sun
    final daysInMonth = DateTime(year, month + 2, 0).day;
    final cells = firstDow + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        // Day-of-week header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: kDow.map((d) => Expanded(
              child: Center(
                child: Text(d, style: AppText.caption(weight: FontWeight.w600, color: AppColors.muted)),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: (MediaQuery.of(context).size.height - 280) / rows,
              ),
              itemCount: rows * 7,
              itemBuilder: (_, idx) {
                final day = idx - firstDow + 1;
                if (day < 1 || day > daysInMonth) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: AppColors.border.withOpacity(0.5)),
                        bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
                      ),
                    ),
                  );
                }
                final isToday = year == 2026 && month == 3 && day == 24;
                final isPast = year == 2026 && month == 3 && day < 24;
                final dayEvents = events.where((e) {
                  if (e.allDay) return day >= e.startDay && day <= e.endDay;
                  return e.startDay == day;
                }).toList();

                return GestureDetector(
                  onTap: () => onDayTap(day),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: AppColors.border.withOpacity(0.5)),
                        bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
                      ),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: isToday
                                ? const BoxDecoration(
                                    color: AppColors.dark,
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Center(
                              child: Text(
                                '$day',
                                style: AppText.caption(
                                  size: 11,
                                  weight: isToday ? FontWeight.w700 : FontWeight.w400,
                                  color: isToday
                                      ? Colors.white
                                      : isPast
                                          ? AppColors.muted
                                          : AppColors.dark,
                                ),
                              ),
                            ),
                          ),
                        ),
                        ...dayEvents.take(2).map((e) => Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: e.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            e.title,
                            style: const TextStyle(fontSize: 8, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                        if (dayEvents.length > 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 3),
                            child: Text(
                              '+${dayEvents.length - 2}',
                              style: AppText.caption(size: 8),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Week View ────────────────────────────────────────────────────────────────

class _WeekView extends StatelessWidget {
  final int weekStart;
  final List<CalendarEvent> events;
  final ValueChanged<int> onDayTap;

  const _WeekView({
    required this.weekStart,
    required this.events,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart + i);
    final allDayEvents = events.where((e) => e.allDay).toList();
    final timedEvents = events.where((e) => !e.allDay).toList();
    final totalH = (kDayEnd - kDayStart) * kHourH.toDouble();

    return Column(
      children: [
        // Day strip header
        Padding(
          padding: const EdgeInsets.only(left: 58, right: 20),
          child: Row(
            children: days.map((d) {
              final isToday = d == 24;
              final dow = kDow[days.indexOf(d)];
              return Expanded(
                child: GestureDetector(
                  onTap: () => onDayTap(d),
                  child: Column(
                    children: [
                      Text(dow, style: AppText.caption(size: 9, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: isToday
                            ? const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle)
                            : null,
                        child: Center(
                          child: Text(
                            '$d',
                            style: AppText.body(
                              size: 12,
                              weight: isToday ? FontWeight.w700 : FontWeight.w400,
                              color: isToday ? Colors.white : (d < 24 ? AppColors.muted : AppColors.dark),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // All-day events strip
        if (allDayEvents.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            height: 26,
            child: Row(
              children: [
                const SizedBox(width: 38),
                ...days.map((d) => Expanded(
                  child: Row(
                    children: allDayEvents.where((e) => d >= e.startDay && d <= e.endDay).map((e) =>
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: e.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            e.title,
                            style: const TextStyle(fontSize: 9, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ).toList(),
                  ),
                )),
              ],
            ),
          ),

        const SizedBox(height: 6),

        // Time grid
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final colW = (constraints.maxWidth - 20 - 38 - 20) / 7;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: totalH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Time labels
                      SizedBox(
                        width: 38,
                        child: Stack(
                          children: List.generate(kDayEnd - kDayStart, (i) {
                            final h = kDayStart + i;
                            return Positioned(
                              top: i * kHourH.toDouble() - 6,
                              child: SizedBox(
                                width: 36,
                                child: Text(
                                  '${fmt2(h)}:00',
                                  style: AppText.caption(size: 9, color: AppColors.muted),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      // Day columns
                      ...days.map((d) {
                        final dayTimed = timedEvents.where((e) => e.startDay == d).toList();
                        return SizedBox(
                          width: colW,
                          child: Stack(
                            children: [
                              // Hour lines
                              ...List.generate(kDayEnd - kDayStart, (i) => Positioned(
                                top: i * kHourH.toDouble(),
                                left: 0,
                                right: 0,
                                child: Divider(
                                  height: 1,
                                  color: i == 0 ? Colors.transparent : AppColors.border.withOpacity(0.6),
                                ),
                              )),
                              // Events
                              ...dayTimed.map((e) {
                                final topFrac = (e.startHour - kDayStart) + e.startMin / 60.0;
                                final durH = (e.endHour - e.startHour) + (e.endMin - e.startMin) / 60.0;
                                final top = topFrac * kHourH;
                                final height = max(durH * kHourH, 20.0);
                                return Positioned(
                                  top: top,
                                  left: 1,
                                  right: 1,
                                  height: height,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: e.color,
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 4, offset: Offset(0, 1))],
                                    ),
                                    child: Text(
                                      height > 28 ? '${e.title}\n${fmtHm(e.startHour, e.startMin)}' : e.title,
                                      style: const TextStyle(fontSize: 9, color: Colors.white, height: 1.3),
                                      overflow: TextOverflow.fade,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─── Day View ─────────────────────────────────────────────────────────────────

class _DayView extends StatelessWidget {
  final int day;
  final List<CalendarEvent> events;
  final VoidCallback onAdd;

  const _DayView({required this.day, required this.events, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final allDay = events.where((e) => e.allDay && day >= e.startDay && day <= e.endDay).toList();
    final timed = events.where((e) => !e.allDay && e.startDay == day).toList()
      ..sort((a, b) => a.startHour != b.startHour ? a.startHour - b.startHour : a.startMin - b.startMin);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        if (allDay.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            children: allDay.map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(10)),
              child: Text(e.title, style: const TextStyle(fontSize: 13, color: Colors.white)),
            )).toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (timed.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Text('今天沒有行程', style: AppText.body(color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text('點下方按鈕新增', style: AppText.caption()),
                ],
              ),
            ),
          )
        else
          ...timed.map((e) {
            final durMin = (e.endHour - e.startHour) * 60 + (e.endMin - e.startMin);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [kCardShadow],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: e.color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.title, style: AppText.body(size: 14, weight: FontWeight.w500)),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${fmtHm(e.startHour, e.startMin)} – ${fmtHm(e.endHour, e.endMin)} · $durMin 分鐘',
                                    style: AppText.label(size: 12),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.plus, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Text('新增行程', style: AppText.label(size: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Add Event Modal ──────────────────────────────────────────────────────────

class _AddEventModal extends StatefulWidget {
  final int? selectedDay;
  final ValueChanged<CalendarEvent> onSave;

  const _AddEventModal({this.selectedDay, required this.onSave});

  @override
  State<_AddEventModal> createState() => _AddEventModalState();
}

class _AddEventModalState extends State<_AddEventModal> {
  final _titleCtrl = TextEditingController();
  final _rangeCtrl = TextEditingController();
  int _startDay = 24, _startHour = 9, _startMin = 0;
  int _endDay = 24, _endHour = 10, _endMin = 0;
  Color _color = AppColors.sage;
  Map<String, int>? _parsed;

  static const _colors = [AppColors.sage, AppColors.amber, AppColors.blue, AppColors.rose, AppColors.dark];

  @override
  void initState() {
    super.initState();
    if (widget.selectedDay != null) _startDay = _endDay = widget.selectedDay!;
    _rangeCtrl.addListener(_onRangeChanged);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _rangeCtrl.dispose();
    super.dispose();
  }

  void _onRangeChanged() {
    final p = parseEventRange(_rangeCtrl.text);
    setState(() {
      _parsed = p;
      if (p != null) {
        _startDay = p['startDay']!;
        _startHour = p['startHour']!;
        _startMin = p['startMin']!;
        _endDay = p['endDay']!;
        _endHour = p['endHour']!;
        _endMin = p['endMin']!;
      }
    });
  }

  void _save() {
    if (_titleCtrl.text.isEmpty) return;
    final e = CalendarEvent(
      id: 0,
      title: _titleCtrl.text,
      startDay: _startDay, startHour: _startHour, startMin: _startMin,
      endDay: _endDay, endHour: _endHour, endMin: _endMin,
      color: _color,
    );
    widget.onSave(e);
    Navigator.pop(context);
  }

  Widget _numInput(String label, int value, ValueChanged<int> onChanged, {int min = 0, int max = 59, int step = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption(size: 11)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () { if (value - step >= min) onChanged(value - step); },
                child: const Icon(LucideIcons.minus, size: 12, color: AppColors.muted),
              ),
              const SizedBox(width: 8),
              Text(fmt2(value), style: AppText.body(size: 13, weight: FontWeight.w500)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () { if (value + step <= max) onChanged(value + step); },
                child: const Icon(LucideIcons.plus, size: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text('標題', style: AppText.label(size: 12, weight: FontWeight.w500, color: AppColors.dark)),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  hintText: '行程名稱',
                  hintStyle: AppText.body(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                ),
                style: AppText.body(size: 14),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),

              // Quick range
              Text('快速輸入時間範圍', style: AppText.label(size: 12, weight: FontWeight.w500, color: AppColors.dark)),
              const SizedBox(height: 6),
              TextField(
                controller: _rangeCtrl,
                decoration: InputDecoration(
                  hintText: '例：4/24 9:00 - 4/24 10:00',
                  hintStyle: AppText.body(size: 13, color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _parsed != null ? AppColors.sage : Colors.transparent,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _parsed != null ? AppColors.sage : Colors.transparent,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _parsed != null ? AppColors.sage : AppColors.border,
                    ),
                  ),
                  suffixIcon: _parsed != null
                      ? const Icon(LucideIcons.circleCheck, color: AppColors.sage, size: 18)
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                ),
                style: AppText.body(size: 13),
              ),
              if (_parsed != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_parsed!['startDay']}日 ${fmtHm(_parsed!['startHour']!, _parsed!['startMin']!)} → ${_parsed!['endDay']}日 ${fmtHm(_parsed!['endHour']!, _parsed!['endMin']!)}',
                    style: AppText.caption(color: AppColors.sage),
                  ),
                ),
              const SizedBox(height: 16),

              // Manual pickers
              Text('手動設定時間', style: AppText.label(size: 12, weight: FontWeight.w500, color: AppColors.dark)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _numInput('開始日', _startDay, (v) => setState(() => _startDay = v), min: 1, max: 30),
                  _numInput('結束日', _endDay, (v) => setState(() => _endDay = v), min: 1, max: 30),
                  _numInput('開始時', _startHour, (v) => setState(() => _startHour = v), min: 0, max: 23),
                  _numInput('開始分', _startMin, (v) => setState(() => _startMin = v), min: 0, max: 59, step: 15),
                  _numInput('結束時', _endHour, (v) => setState(() => _endHour = v), min: 0, max: 23),
                  _numInput('結束分', _endMin, (v) => setState(() => _endMin = v), min: 0, max: 59, step: 15),
                ],
              ),
              const SizedBox(height: 16),

              // Color picker
              Text('顏色', style: AppText.label(size: 12, weight: FontWeight.w500, color: AppColors.dark)),
              const SizedBox(height: 8),
              Row(
                children: _colors.map((c) => GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32, height: 32,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c ? AppColors.dark : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text('儲存行程', style: AppText.body(size: 15, weight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
