import 'chat_message.dart';

/// Single flat `chat_messages` thread (no sessions). The client only reads;
/// messages are appended server-side by the chat Cloud Function (Phase 2).
abstract class ChatRepo {
  /// Streams the latest page of messages in chronological order (oldest →
  /// newest). The window is bounded (DataModel.md "Pagination"); older history
  /// is fetched on demand via [loadOlder].
  Stream<List<ChatMessage>> watchMessages();

  /// One-shot fetch of the page of messages strictly older than [before] (the
  /// `createdAt` of the oldest message currently shown), returned in
  /// chronological order (oldest → newest) for prepending in the UI. Fewer than
  /// a full page means there is no more history.
  Future<List<ChatMessage>> loadOlder(DateTime before);
}
