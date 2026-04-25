import 'package:flutter/material.dart';

class CalendarEvent {
  final int id;
  final String title;
  final int startDay;
  final int startHour;
  final int startMin;
  final int endDay;
  final int endHour;
  final int endMin;
  final Color color;
  final bool allDay;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startDay,
    required this.startHour,
    required this.startMin,
    required this.endDay,
    required this.endHour,
    required this.endMin,
    required this.color,
    this.allDay = false,
  });

  CalendarEvent copyWith({
    int? id,
    String? title,
    int? startDay,
    int? startHour,
    int? startMin,
    int? endDay,
    int? endHour,
    int? endMin,
    Color? color,
    bool? allDay,
  }) =>
      CalendarEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        startDay: startDay ?? this.startDay,
        startHour: startHour ?? this.startHour,
        startMin: startMin ?? this.startMin,
        endDay: endDay ?? this.endDay,
        endHour: endHour ?? this.endHour,
        endMin: endMin ?? this.endMin,
        color: color ?? this.color,
        allDay: allDay ?? this.allDay,
      );
}
