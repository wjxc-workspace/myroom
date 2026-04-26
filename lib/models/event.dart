import 'package:flutter/material.dart';

class CalendarEvent {
  final int id;
  final String title;
  final int startYear;
  final int startMonth;
  final int startDay;
  final int startHour;
  final int startMin;
  final int endYear;
  final int endMonth;
  final int endDay;
  final int endHour;
  final int endMin;
  final Color color;
  final bool allDay;
  final String? description;
  final String? location;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.startYear = 2026,
    this.startMonth = 4,
    required this.startDay,
    required this.startHour,
    required this.startMin,
    this.endYear = 2026,
    this.endMonth = 4,
    required this.endDay,
    required this.endHour,
    required this.endMin,
    required this.color,
    this.allDay = false,
    this.description,
    this.location,
  });

  CalendarEvent copyWith({
    int? id,
    String? title,
    int? startYear,
    int? startMonth,
    int? startDay,
    int? startHour,
    int? startMin,
    int? endYear,
    int? endMonth,
    int? endDay,
    int? endHour,
    int? endMin,
    Color? color,
    bool? allDay,
    String? description,
    String? location,
  }) =>
      CalendarEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        startYear: startYear ?? this.startYear,
        startMonth: startMonth ?? this.startMonth,
        startDay: startDay ?? this.startDay,
        startHour: startHour ?? this.startHour,
        startMin: startMin ?? this.startMin,
        endYear: endYear ?? this.endYear,
        endMonth: endMonth ?? this.endMonth,
        endDay: endDay ?? this.endDay,
        endHour: endHour ?? this.endHour,
        endMin: endMin ?? this.endMin,
        color: color ?? this.color,
        allDay: allDay ?? this.allDay,
        description: description ?? this.description,
        location: location ?? this.location,
      );
}
