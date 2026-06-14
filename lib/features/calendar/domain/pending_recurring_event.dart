import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'event.dart';

/// A proposed recurring event written by the AI chat function, awaiting user
/// confirmation. Lives at `users/{uid}/pending_recurring_events/{id}`.
///
/// On confirm, [toEvents] is expanded into [repeatWeeks] individual
/// [CalendarEvent]s via a single Firestore batch write.
class PendingRecurringEvent {
  final String id;
  final String title;
  final String? description;
  final String? location;
  final Color color;
  final DateTime firstStart;
  final DateTime firstEnd;
  final int repeatWeeks;

  const PendingRecurringEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.color,
    required this.firstStart,
    required this.firstEnd,
    required this.repeatWeeks,
  });

  factory PendingRecurringEvent.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PendingRecurringEvent(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      description: d['description'] as String?,
      location: d['location'] as String?,
      color: Color((d['color'] as int?) ?? 0xFF7B9E87),
      firstStart:
          (d['firstStart'] as Timestamp?)?.toDate() ?? DateTime.now(),
      firstEnd: (d['firstEnd'] as Timestamp?)?.toDate() ?? DateTime.now(),
      repeatWeeks: (d['repeatWeeks'] as int?) ?? 1,
    );
  }

  /// Expands into one [CalendarEvent] per week, shifting by 7 days each time.
  List<CalendarEvent> toEvents() => List.generate(
        repeatWeeks,
        (i) => CalendarEvent(
          id: '',
          title: title,
          description: description,
          location: location,
          startTime: firstStart.add(Duration(days: 7 * i)),
          endTime: firstEnd.add(Duration(days: 7 * i)),
          isAllDay: false,
          color: color,
          createdAt: DateTime.now(),
        ),
      );
}
