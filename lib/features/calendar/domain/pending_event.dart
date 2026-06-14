import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'event.dart';

/// A proposed calendar event written by the AI chat function, awaiting
/// user confirmation. Lives at `users/{uid}/pending_events/{id}`.
class PendingEvent {
  final String id;
  final String title;
  final String? description;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final Color color;

  const PendingEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    required this.color,
  });

  factory PendingEvent.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PendingEvent(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      description: d['description'] as String?,
      location: d['location'] as String?,
      startTime: (d['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (d['endTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isAllDay: (d['isAllDay'] as bool?) ?? false,
      color: Color((d['color'] as int?) ?? 0xFF7B9E87),
    );
  }

  CalendarEvent toCalendarEvent() => CalendarEvent(
        id: '',
        title: title,
        description: description,
        location: location,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        color: color,
        createdAt: DateTime.now(),
      );
}
