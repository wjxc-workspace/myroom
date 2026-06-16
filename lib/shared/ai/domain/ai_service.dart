import 'dart:typed_data';

import '../../../core/result.dart';
import 'ai_resource.dart';
import 'chat_action.dart';
import 'classification.dart';

/// Client surface over the Cloud Functions AI callables (AI_proxy.md). There is
/// no client OpenAI key — every call goes through Functions. Errors come back as
/// typed [Failure]s (AiFailure / RateLimitFailure) and are surfaced as the top
/// error banner by the implementation.
abstract class AiService {
  /// Sends a chat message; the function appends the user + assistant turns to
  /// `chat_messages` (the UI updates from its stream). Returns the reply text
  /// plus any data changes the AI proposed but deferred for the user to confirm
  /// (see [applyChatActions]).
  Future<Result<ChatTurn>> chat(String message);

  /// Applies the [actions] the user accepted on a chat confirm card. The server
  /// re-runs the same tool executors and appends an assistant result message;
  /// returns the per-action result strings.
  Future<Result<List<String>>> applyChatActions(List<ProposedAction> actions);

  /// Classifies a Smart Add submission into typed items (AI_proxy.md §5).
  Future<Result<List<ClassificationItem>>> classifyMultiInput({
    required String text,
    List<String> images,
    String fileText,
    List<AiAttachmentRef> attachments,
    String? userSpecifiedCat,
  });

  /// Web-search-backed resource recommendations from up to 5 idea texts.
  Future<Result<List<AiResource>>> fetchRecommendations(List<String> ideaTexts);

  /// Reflective era / recap summary. Routing is decided by the caller.
  Future<Result<String>> generateEraInsight({
    required String eraLabel,
    required String dataSummary,
  });

  /// Whisper transcription for a Smart Add audio attachment.
  Future<Result<String>> transcribe({
    required Uint8List audioBytes,
    required String filename,
  });

  /// Renders a recap export server-side; returns the stored `storagePath`.
  Future<Result<String>> exportRecap(String recapId);

  /// Renders one era of an achievement export; returns the stored `storagePath`.
  Future<Result<String>> exportAchievement({
    required String achievementId,
    required String era, // past | current | future
  });
}
