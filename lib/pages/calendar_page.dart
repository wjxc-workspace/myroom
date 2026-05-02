import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../models/event.dart';
import '../data/seed_data.dart';
import '../widgets/mr_icon_button.dart';

enum CalendarView { month, week, day }

const int kHourH = 56;

// ─── 24h Scroll Time Picker ───────────────────────────────────────────────────

Future<TimeOfDay?> _show24hTimePicker(BuildContext context, TimeOfDay initial) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _TimePickerSheet(initial: initial),
  );
}

class _TimePickerSheet extends StatefulWidget {
  final TimeOfDay initial;
  const _TimePickerSheet({required this.initial});
  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  static const int _minStep = 5;
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hCtrl;
  late final FixedExtentScrollController _mCtrl;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _minute = (widget.initial.minute ~/ _minStep) * _minStep;
    _hCtrl = FixedExtentScrollController(initialItem: _hour);
    _mCtrl = FixedExtentScrollController(initialItem: _minute ~/ _minStep);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('選擇時間', style: AppText.body(size: 16, weight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 46,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        controller: _hCtrl,
                        itemExtent: 46,
                        perspective: 0.003,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (i) =>
                            setState(() => _hour = i),
                        childDelegate: ListWheelChildLoopingListDelegate(
                          children: List.generate(
                            24,
                            (h) => Center(
                              child: Text(
                                fmt2(h),
                                style: AppText.body(
                                    size: 24, weight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      ':',
                      style: AppText.body(
                          size: 26,
                          weight: FontWeight.w700,
                          color: AppColors.dark),
                    ),
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        controller: _mCtrl,
                        itemExtent: 46,
                        perspective: 0.003,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (i) =>
                            setState(() => _minute = i * _minStep),
                        childDelegate: ListWheelChildLoopingListDelegate(
                          children: List.generate(
                            60 ~/ _minStep,
                            (i) => Center(
                              child: Text(
                                fmt2(i * _minStep),
                                style: AppText.body(
                                    size: 24, weight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => Navigator.pop(
                  context, TimeOfDay(hour: _hour, minute: _minute)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.dark,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '確認',
                    style: AppText.body(
                        size: 15,
                        weight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CalendarPage ─────────────────────────────────────────────────────────────

class CalendarPage extends StatefulWidget {
  final List<CalendarEvent> events;
  final ValueChanged<CalendarEvent> onEventAdded;
  final ValueChanged<int> onEventDeleted;
  final ValueChanged<CalendarEvent> onEventEdited;

  const CalendarPage({
    super.key,
    required this.events,
    required this.onEventAdded,
    required this.onEventDeleted,
    required this.onEventEdited,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarView _view = CalendarView.month;
  DateTime _focusDate = DateTime.now();
  late final PageController _calViewCtrl;

  @override
  void initState() {
    super.initState();
    _calViewCtrl = PageController(initialPage: 1);
  }

  @override
  void dispose() {
    _calViewCtrl.dispose();
    super.dispose();
  }

  DateTime _weekStartFor(DateTime date) {
    final dow = date.weekday % 7;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: dow));
  }

  DateTime get _weekStart => _weekStartFor(_focusDate);

  DateTime _dateForOffset(int delta) {
    switch (_view) {
      case CalendarView.month:
        return DateTime(_focusDate.year, _focusDate.month + delta, 1);
      case CalendarView.week:
        return _focusDate.add(Duration(days: delta * 7));
      case CalendarView.day:
        return _focusDate.add(Duration(days: delta));
    }
  }

  void _navigate(int delta) {
    setState(() => _focusDate = _dateForOffset(delta));
    _resetCalView();
  }

  void _resetCalView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_calViewCtrl.hasClients) _calViewCtrl.jumpToPage(1);
    });
  }

  String get _headerLabel {
    switch (_view) {
      case CalendarView.month:
        return '${_focusDate.year}年${_focusDate.month}月';
      case CalendarView.week:
        final ws = _weekStart;
        final we = ws.add(const Duration(days: 6));
        return '${ws.month}/${ws.day}–${we.month}/${we.day}';
      case CalendarView.day:
        return '${_focusDate.month}月${_focusDate.day}日';
    }
  }

  // Fixed: all events (allDay or not) span their full date range.
  bool _eventIsOnDay(CalendarEvent e, DateTime day) {
    final start = DateTime(e.startYear, e.startMonth, e.startDay);
    final end = DateTime(e.endYear, e.endMonth, e.endDay);
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
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
                      onTap: () {
                        setState(() => _view = v);
                        _resetCalView();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: active ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: active ? const [kBtnShadow] : null,
                        ),
                        child: Text(
                          labels[v.index],
                          style: AppText.body(
                            size: 13,
                            weight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color:
                                active ? AppColors.dark : AppColors.muted,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Spacer(),
              MrIconButton(
                icon: LucideIcons.calendar,
                iconSize: 16,
                onTap: _openDatePicker,
              ),
              const SizedBox(width: 4),
              MrIconButton(
                icon: LucideIcons.chevronLeft,
                iconSize: 16,
                onTap: () => _navigate(-1),
              ),
              const SizedBox(width: 6),
              Text(_headerLabel,
                  style: AppText.body(size: 13, weight: FontWeight.w500)),
              const SizedBox(width: 6),
              MrIconButton(
                icon: LucideIcons.chevronRight,
                iconSize: 16,
                onTap: () => _navigate(1),
              ),
            ],
          ),
        ),
        // Inner PageView captures horizontal swipes for within-calendar
        // navigation, taking priority over the outer tab-switching PageView.
        Expanded(
          child: PageView.builder(
            controller: _calViewCtrl,
            onPageChanged: (i) {
              if (i != 1) {
                final newDate = _dateForOffset(i == 0 ? -1 : 1);
                setState(() => _focusDate = newDate);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_calViewCtrl.hasClients) _calViewCtrl.jumpToPage(1);
                });
              }
            },
            itemCount: 3,
            itemBuilder: (context, i) =>
                _buildViewForDate(_dateForOffset(i - 1)),
          ),
        ),
      ],
    );
  }

  Widget _buildViewForDate(DateTime date) {
    switch (_view) {
      case CalendarView.month:
        return _MonthView(
          year: date.year,
          month: date.month,
          events: widget.events,
          eventIsOnDay: _eventIsOnDay,
          onDayTap: _onMonthDayTap,
          // onEventTap: _showEventDetail,
        );
      case CalendarView.week:
        return _WeekView(
          weekStart: _weekStartFor(date),
          events: widget.events,
          eventIsOnDay: _eventIsOnDay,
          onDayTap: (d) {
            setState(() {
              _focusDate = d;
              _view = CalendarView.day;
            });
            _resetCalView();
          },
          onTimeTap: (dt) => _showAddModal(selectedDate: dt),
          onEventTap: _showEventDetail,
        );
      case CalendarView.day:
        return _DayView(
          date: date,
          events: widget.events,
          eventIsOnDay: _eventIsOnDay,
          onAdd: (dt) => _showAddModal(selectedDate: dt),
          onEventTap: _showEventDetail,
        );
    }
  }

  // Month day tap → switch directly to day view.
  void _onMonthDayTap(DateTime day) {
    setState(() {
      _focusDate = day;
      _view = CalendarView.day;
    });
    _resetCalView();
  }

  Future<void> _openDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _focusDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() => _focusDate = picked);
      _resetCalView();
    }
  }

  void _showAddModal({DateTime? selectedDate}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.25,
        maxChildSize: 0.97,
        expand: false,
        shouldCloseOnMinExtent: true,
        builder: (_, scrollCtrl) => _AddEventModal(
          selectedDate: selectedDate ?? _focusDate,
          onSave: (e) => widget.onEventAdded(e),
          scrollController: scrollCtrl,
        ),
      ),
    );
  }

  void _showEditModal(CalendarEvent e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.25,
        maxChildSize: 0.97,
        expand: false,
        shouldCloseOnMinExtent: true,
        builder: (_, scrollCtrl) => _AddEventModal(
          selectedDate:
              DateTime(e.startYear, e.startMonth, e.startDay),
          initialEvent: e,
          onSave: (updated) => widget.onEventEdited(updated),
          scrollController: scrollCtrl,
        ),
      ),
    );
  }

  void _showEventDetail(CalendarEvent e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EventDetailSheet(
        event: e,
        onDelete: (id) {
          Navigator.pop(context);
          widget.onEventDeleted(id);
        },  
        onEdit: () {
          Navigator.pop(context);
          _showEditModal(e);
        },
      ),
    );
  }
}

// ─── Month View ───────────────────────────────────────────────────────────────

class _MonthView extends StatelessWidget {
  final int year, month;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onDayTap;
  final bool Function(CalendarEvent, DateTime) eventIsOnDay;

  const _MonthView({
    required this.year,
    required this.month,
    required this.events,
    required this.onDayTap,
    required this.eventIsOnDay,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDow = DateTime(year, month, 1).weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final cells = firstDow + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: kDow
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: AppText.caption(
                                weight: FontWeight.w600,
                                color: AppColors.muted)),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.only(left: 20, right: 20, bottom: 100),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 90,
              ),
              itemCount: rows * 7,
              itemBuilder: (_, idx) {
                final day = idx - firstDow + 1;
                if (day < 1 || day > daysInMonth) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                            color: AppColors.border.withOpacity(0.5)),
                        bottom: BorderSide(
                            color: AppColors.border.withOpacity(0.5)),
                      ),
                    ),
                  );
                }
                final date = DateTime(year, month, day);
                final isToday = date.year == today.year &&
                    date.month == today.month &&
                    date.day == today.day;
                final isPast = date.isBefore(
                    DateTime(today.year, today.month, today.day));
                final dayEvents =
                    events.where((e) => eventIsOnDay(e, date)).toList();

                return GestureDetector(
                  onTap: () => onDayTap(date),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                            color: AppColors.border.withOpacity(0.5)),
                        bottom: BorderSide(
                            color: AppColors.border.withOpacity(0.5)),
                      ),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Flex(
                      direction: Axis.vertical,
                      clipBehavior: Clip.hardEdge,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: isToday
                                ? const BoxDecoration(
                                    color: AppColors.dark,
                                    shape: BoxShape.circle)
                                : null,
                            child: Center(
                              child: Text(
                                '$day',
                                style: AppText.caption(
                                  size: 11,
                                  weight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w400,
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
                        ...dayEvents.take(2).map((e) => GestureDetector(
                              child: Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                    color: e.color,
                                    borderRadius:
                                        BorderRadius.circular(4)),
                                child: Text(
                                  e.title,
                                  style: const TextStyle(
                                      fontSize: 8, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )),
                        if (dayEvents.length > 2)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: 2, left: 3),
                            child: Text('+${dayEvents.length - 2}',
                                style: AppText.caption(size: 8)),
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

class _WeekView extends StatefulWidget {
  final DateTime weekStart;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<DateTime> onTimeTap;
  final ValueChanged<CalendarEvent> onEventTap;
  final bool Function(CalendarEvent, DateTime) eventIsOnDay;

  const _WeekView({
    required this.weekStart,
    required this.events,
    required this.onDayTap,
    required this.onTimeTap,
    required this.onEventTap,
    required this.eventIsOnDay,
  });

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<_WeekView> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final weekEnd = widget.weekStart.add(const Duration(days: 7));
    final isCurrentWeek =
        !now.isBefore(widget.weekStart) && now.isBefore(weekEnd);
    final scrollHour = isCurrentWeek ? now.hour : 8;
    _scrollCtrl = ScrollController(
      initialScrollOffset:
          (scrollHour * kHourH - 60.0).clamp(0.0, double.infinity),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // True when [d] is a middle day of a multi-day timed event [e] —
  // strictly between start date and end date (not the start/end day itself).
  bool _isMiddleDay(CalendarEvent e, DateTime d) {
    if (e.allDay) return false;
    final startDate = DateTime(e.startYear, e.startMonth, e.startDay);
    final endDate = DateTime(e.endYear, e.endMonth, e.endDay);
    final day = DateTime(d.year, d.month, d.day);
    return day.isAfter(startDate) && day.isBefore(endDate);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(
        7, (i) => widget.weekStart.add(Duration(days: i)));
    final allDayEvts = widget.events.where((e) => e.allDay).toList();
    final timedEvts = widget.events.where((e) => !e.allDay).toList();
    final totalH = 24 * kHourH.toDouble();

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 44),
            ...days.map((d) {
              final isToday = d.year == today.year &&
                  d.month == today.month &&
                  d.day == today.day;
              final dow = kDow[d.weekday % 7];
              final isPast =
                  d.isBefore(DateTime(today.year, today.month, today.day));
              return Expanded(
                child: GestureDetector(
                  onTap: () => widget.onDayTap(d),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dow,
                        style: AppText.caption(
                            size: 9, color: AppColors.muted),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 3),
                      Container(
                        alignment: Alignment.center,
                        padding:
                            const EdgeInsets.symmetric(vertical: 2),
                        decoration: isToday
                            ? BoxDecoration(
                                color: AppColors.dark,
                                borderRadius:
                                    BorderRadius.circular(8))
                            : null,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${d.month}/${d.day}',
                            style: AppText.caption(
                              size: 10,
                              weight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isToday
                                  ? Colors.white
                                  : isPast
                                      ? AppColors.muted
                                      : AppColors.dark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        if (allDayEvts.any((e) => days.any((d) => widget.eventIsOnDay(e, d))) ||
            timedEvts.any((e) => days.any((d) => _isMiddleDay(e, d))))
          Container(
            margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            height: 26,
            child: Row(
              children: [
                const SizedBox(width: 34),
                ...days.map((d) {
                  final chipsForDay = [
                    ...allDayEvts.where((e) => widget.eventIsOnDay(e, d)),
                    ...timedEvts.where((e) => _isMiddleDay(e, d)),
                  ];
                  return Expanded(
                    child: Row(
                      children: chipsForDay
                          .map((e) => Expanded(
                                child: GestureDetector(
                                  onTap: () => widget.onEventTap(e),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 1),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3),
                                    decoration: BoxDecoration(
                                        color: e.color,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        border: e.allDay
                                            ? null
                                            : Border.all(
                                                color: e.color,
                                                width: 1)),
                                    child: Text(
                                      e.title,
                                      style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  );
                }),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.only(bottom: 100),
            child: SizedBox(
              height: totalH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Stack(
                      children: List.generate(
                        24,
                        (h) => Positioned(
                          // Fix: 00:00 was at top=-7 (clipped); clamp to 2
                          top: h == 0
                              ? 2.0
                              : h * kHourH.toDouble() - 7,
                          child: SizedBox(
                            width: 42,
                            child: Text(
                              '${fmt2(h)}:00',
                              style: AppText.caption(
                                  size: 9, color: AppColors.muted),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...days.map((d) {
                    // Middle days are shown in the all-day chips row above.
                    final dayTimed = timedEvts
                        .where((e) =>
                            widget.eventIsOnDay(e, d) && !_isMiddleDay(e, d))
                        .toList();
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          final tapH =
                              details.localPosition.dy / kHourH;
                          final hour = tapH.floor().clamp(0, 23);
                          final minute =
                              ((tapH - hour) * 60).round().clamp(0, 59);
                          final snappedMinute = (minute ~/ 15) * 15;
                          widget.onTimeTap(DateTime(d.year, d.month,
                              d.day, hour, snappedMinute));
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ...List.generate(
                              24,
                              (h) => Positioned(
                                top: h * kHourH.toDouble(),
                                left: 0,
                                right: 0,
                                child: Divider(
                                  height: 1,
                                  color: h == 0
                                      ? Colors.transparent
                                      : AppColors.border
                                          .withOpacity(0.6),
                                ),
                              ),
                            ),
                            ...dayTimed.map((e) {
                              // Clamp event bounds to this day so multi-day
                              // timed events render correctly in each column.
                              final eStart = DateTime(
                                  e.startYear,
                                  e.startMonth,
                                  e.startDay,
                                  e.startHour,
                                  e.startMin);
                              final eEnd = DateTime(
                                  e.endYear,
                                  e.endMonth,
                                  e.endDay,
                                  e.endHour,
                                  e.endMin);
                              final dMid =
                                  DateTime(d.year, d.month, d.day);
                              final dNext = dMid
                                  .add(const Duration(days: 1));
                              final dispStart = eStart.isBefore(dMid)
                                  ? dMid
                                  : eStart;
                              final dispEnd =
                                  eEnd.isAfter(dNext) ? dNext : eEnd;
                              final topFrac = dispStart.hour +
                                  dispStart.minute / 60.0;
                              final durH = dispEnd
                                      .difference(dispStart)
                                      .inMinutes /
                                  60.0;
                              final top = topFrac * kHourH;
                              final height =
                                  max(durH * kHourH, 20.0);
                              return Positioned(
                                top: top,
                                left: 1,
                                right: 1,
                                height: height,
                                child: GestureDetector(
                                  onTap: () => widget.onEventTap(e),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: e.color,
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: Color(0x26000000),
                                            blurRadius: 4,
                                            offset: Offset(0, 1))
                                      ],
                                    ),
                                    child: Text(
                                      height > 28
                                          ? '${e.title}\n${fmtHm(e.startHour, e.startMin)}'
                                          : e.title,
                                      style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.white,
                                          height: 1.3),
                                      overflow: TextOverflow.fade,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Day View ─────────────────────────────────────────────────────────────────

class _DayView extends StatelessWidget {
  final DateTime date;
  final List<CalendarEvent> events;
  final bool Function(CalendarEvent, DateTime) eventIsOnDay;
  final ValueChanged<DateTime> onAdd;
  final ValueChanged<CalendarEvent> onEventTap;

  const _DayView({
    required this.date,
    required this.events,
    required this.eventIsOnDay,
    required this.onAdd,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    final allDay =
        events.where((e) => e.allDay && eventIsOnDay(e, date)).toList();
    final timed = events
        .where((e) => !e.allDay && eventIsOnDay(e, date))
        .toList()
      ..sort((a, b) => a.startHour != b.startHour
          ? a.startHour - b.startHour
          : a.startMin - b.startMin);
    final all = [...allDay, ...timed];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Add button at the top
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: GestureDetector(
            onTap: () =>
                onAdd(DateTime(date.year, date.month, date.day, 9, 0)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.plus,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('新增行程',
                      style: AppText.label(
                          size: 13, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: all.isEmpty
              ? Center(
                  child: Text('今天沒有行程',
                      style: AppText.body(color: AppColors.muted)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  itemCount: all.length,
                  itemBuilder: (context, i) {
                    final e = all[i];
                    return GestureDetector(
                      onTap: () => onEventTap(e),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [kCardShadow],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 5,
                              height: 64,
                              decoration: BoxDecoration(
                                color: e.color,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  bottomLeft: Radius.circular(16),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.title,
                                      style: AppText.body(
                                          size: 15,
                                          weight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    if (e.allDay)
                                      Text('全天',
                                          style:
                                              AppText.caption(size: 12))
                                    else
                                      Text(
                                        '${fmtHm(e.startHour, e.startMin)} – ${fmtHm(e.endHour, e.endMin)}',
                                        style:
                                            AppText.caption(size: 12),
                                      ),
                                    if (e.location != null &&
                                        e.location!.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Row(children: [
                                        const Icon(LucideIcons.mapPin,
                                            size: 11,
                                            color: AppColors.muted),
                                        const SizedBox(width: 4),
                                        Expanded(
                                            child: Text(
                                          e.location!,
                                          style:
                                              AppText.caption(size: 11),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        )),
                                      ]),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(right: 14),
                              child: Icon(LucideIcons.chevronRight,
                                  size: 14, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Add / Edit Event Modal ───────────────────────────────────────────────────

class _AddEventModal extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<CalendarEvent> onSave;
  final CalendarEvent? initialEvent; // non-null = edit mode
  final ScrollController? scrollController;

  const _AddEventModal({
    required this.selectedDate,
    required this.onSave,
    this.initialEvent,
    this.scrollController,
  });

  @override
  State<_AddEventModal> createState() => _AddEventModalState();
}

class _AddEventModalState extends State<_AddEventModal> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  late DateTime _startDt;
  late DateTime _endDt;
  Color _color = AppColors.sage;
  bool _allDay = false;

  static const _colors = [
    AppColors.sage,
    AppColors.amber,
    AppColors.blue,
    AppColors.rose,
    AppColors.dark
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.initialEvent;
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description ?? '';
      _locationCtrl.text = e.location ?? '';
      _startDt = DateTime(
          e.startYear, e.startMonth, e.startDay, e.startHour, e.startMin);
      _endDt =
          DateTime(e.endYear, e.endMonth, e.endDay, e.endHour, e.endMin);
      _color = e.color;
      _allDay = e.allDay;
    } else {
      final d = widget.selectedDate;
      final hasTime = d.hour != 0 || d.minute != 0;
      _startDt = DateTime(d.year, d.month, d.day,
          hasTime ? d.hour : 9, hasTime ? d.minute : 0);
      _endDt = _startDt.add(const Duration(hours: 1));
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _startDt,
        firstDate: DateTime(2020),
        lastDate: DateTime(2035));
    if (d == null || !mounted) return;
    setState(() {
      _startDt = DateTime(
          d.year, d.month, d.day, _startDt.hour, _startDt.minute);
      if (_endDt.isBefore(_startDt)) {
        _endDt = _startDt.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickStartTime() async {
    final t = await _show24hTimePicker(
        context, TimeOfDay.fromDateTime(_startDt));
    if (t == null || !mounted) return;
    setState(() {
      _startDt = DateTime(
          _startDt.year, _startDt.month, _startDt.day, t.hour, t.minute);
      if (_endDt.isBefore(_startDt)) {
        _endDt = _startDt.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickEndDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _endDt,
        firstDate: _startDt,
        lastDate: DateTime(2035));
    if (d == null || !mounted) return;
    setState(() => _endDt =
        DateTime(d.year, d.month, d.day, _endDt.hour, _endDt.minute));
  }

  Future<void> _pickEndTime() async {
    final t = await _show24hTimePicker(
        context, TimeOfDay.fromDateTime(_endDt));
    if (t == null || !mounted) return;
    setState(() => _endDt = DateTime(
        _endDt.year, _endDt.month, _endDt.day, t.hour, t.minute));
  }

  void _save() {
    if (_titleCtrl.text.trim().isEmpty) return;
    final e = CalendarEvent(
      id: widget.initialEvent?.id ?? 0,
      title: _titleCtrl.text.trim(),
      startYear: _startDt.year,
      startMonth: _startDt.month,
      startDay: _startDt.day,
      startHour: _allDay ? 0 : _startDt.hour,
      startMin: _allDay ? 0 : _startDt.minute,
      endYear: _endDt.year,
      endMonth: _endDt.month,
      endDay: _endDt.day,
      endHour: _allDay ? 23 : _endDt.hour,
      endMin: _allDay ? 59 : _endDt.minute,
      color: _color,
      allDay: _allDay,
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      location: _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim(),
    );
    widget.onSave(e);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.initialEvent != null;
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: SingleChildScrollView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 20),
            Text(isEdit ? '編輯行程' : '新增行程',
                style: AppText.body(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 14),
            Text('標題',
                style: AppText.label(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.dark)),
            const SizedBox(height: 6),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                hintText: '行程名稱',
                hintStyle: AppText.body(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
              ),
              style: AppText.body(size: 14),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Text('全天活動',
                  style: AppText.label(
                      size: 12,
                      weight: FontWeight.w500,
                      color: AppColors.dark)),
              const Spacer(),
              Switch(
                  value: _allDay,
                  onChanged: (v) => setState(() => _allDay = v),
                  activeColor: AppColors.dark),
            ]),
            const SizedBox(height: 10),
            Text('開始時間',
                style: AppText.label(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.dark)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                  child: _DateTimeChip(
                      label:
                          '${_startDt.year}/${fmt2(_startDt.month)}/${fmt2(_startDt.day)}',
                      icon: LucideIcons.calendar,
                      onTap: _pickStartDate)),
              if (!_allDay) ...[
                const SizedBox(width: 8),
                Expanded(
                    child: _DateTimeChip(
                        label: fmtHm(_startDt.hour, _startDt.minute),
                        icon: LucideIcons.clock,
                        onTap: _pickStartTime)),
              ],
            ]),
            const SizedBox(height: 10),
            Text('結束時間',
                style: AppText.label(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.dark)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                  child: _DateTimeChip(
                      label:
                          '${_endDt.year}/${fmt2(_endDt.month)}/${fmt2(_endDt.day)}',
                      icon: LucideIcons.calendar,
                      onTap: _pickEndDate)),
              if (!_allDay) ...[
                const SizedBox(width: 8),
                Expanded(
                    child: _DateTimeChip(
                        label: fmtHm(_endDt.hour, _endDt.minute),
                        icon: LucideIcons.clock,
                        onTap: _pickEndTime)),
              ],
            ]),
            const SizedBox(height: 14),
            Text('地點',
                style: AppText.label(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.dark)),
            const SizedBox(height: 6),
            TextField(
              controller: _locationCtrl,
              decoration: InputDecoration(
                hintText: '新增地點',
                hintStyle: AppText.body(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.bg,
                prefixIcon: const Icon(LucideIcons.mapPin,
                    size: 16, color: AppColors.muted),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
              ),
              style: AppText.body(size: 13),
            ),
            const SizedBox(height: 12),
            Text('備註',
                style: AppText.label(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.dark)),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '新增備註說明',
                hintStyle: AppText.body(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
              ),
              style: AppText.body(size: 13),
            ),
            const SizedBox(height: 14),
            Text('顏色',
                style: AppText.label(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.dark)),
            const SizedBox(height: 8),
            Row(
              children: _colors
                  .map((c) => GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _color == c
                                    ? AppColors.dark
                                    : Colors.transparent,
                                width: 3),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(16)),
                  child: Center(
                    child: Text(
                      isEdit ? '儲存修改' : '儲存行程',
                      style: AppText.body(
                          size: 15,
                          weight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Event Detail Sheet ───────────────────────────────────────────────────────

class _EventDetailSheet extends StatelessWidget {
  final CalendarEvent event;
  final ValueChanged<int> onDelete;
  final VoidCallback onEdit;

  const _EventDetailSheet({
    required this.event,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final e = event;
    final isMultiDay = e.startYear != e.endYear ||
        e.startMonth != e.endMonth ||
        e.startDay != e.endDay;
    final durMin =
        (e.endHour - e.startHour) * 60 + (e.endMin - e.startMin);

    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: e.color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(e.title,
                    style: AppText.body(
                        size: 18, weight: FontWeight.w600))),
            GestureDetector(
              onTap: onEdit,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(LucideIcons.pencil,
                    size: 18, color: AppColors.muted),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('刪除行程'),
                  content: Text('確定要刪除「${e.title}」嗎？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onDelete(e.id);
                      },
                      child: const Text('刪除',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(LucideIcons.trash2,
                    size: 18, color: AppColors.muted),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (!e.allDay)
            _DetailRow(
              icon: LucideIcons.clock,
              text: isMultiDay
                  ? '${e.startYear}年${e.startMonth}月${e.startDay}日 ${fmtHm(e.startHour, e.startMin)} – ${e.endYear}年${e.endMonth}月${e.endDay}日 ${fmtHm(e.endHour, e.endMin)}'
                  : '${e.startYear}年${e.startMonth}月${e.startDay}日  ${fmtHm(e.startHour, e.startMin)} – ${fmtHm(e.endHour, e.endMin)}  （$durMin 分鐘）',
            )
          else
            _DetailRow(
              icon: LucideIcons.calendar,
              text:
                  '全天  ${e.startYear}年${e.startMonth}月${e.startDay}日 – ${e.endMonth}月${e.endDay}日',
            ),
          if (e.location != null && e.location!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailRow(icon: LucideIcons.mapPin, text: e.location!),
          ],
          if (e.description != null && e.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailRow(
                icon: LucideIcons.textAlignStart, text: e.description!),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                  color: AppColors.dark,
                  borderRadius: BorderRadius.circular(16)),
              child: Center(
                  child: Text('關閉',
                      style: AppText.body(
                          size: 15,
                          weight: FontWeight.w600,
                          color: Colors.white))),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: AppText.body(size: 13, color: AppColors.muted))),
      ],
    );
  }
}

// ─── DateTime Chip ────────────────────────────────────────────────────────────

class _DateTimeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DateTimeChip(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.muted),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    style: AppText.body(
                        size: 13, weight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
