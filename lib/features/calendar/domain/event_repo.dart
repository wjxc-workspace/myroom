import 'package:flutter/material.dart';

import '../../../core/result.dart';
import 'event.dart';
import 'pending_event.dart';

abstract class EventRepo {
  /// Streams events ordered by `startTime` ascending. When [window] is given,
  /// only events whose `startTime` falls within it are streamed.
  Stream<List<CalendarEvent>> watchEvents({DateTimeRange? window});

  Future<Result<void>> add(CalendarEvent event);

  Future<Result<void>> update(CalendarEvent event);

  Future<Result<void>> delete(String id);

  /// Streams AI-proposed events awaiting user confirmation.
  Stream<List<PendingEvent>> watchPendingEvents();

  Future<Result<void>> deletePendingEvent(String id);
}
