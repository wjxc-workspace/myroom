import 'dart:typed_data';

import '../../../core/result.dart';
import 'ai_resource.dart';
import 'classification.dart';

/// Returned by [AiService.chat]: the assistant reply and the OpenAI response ID
/// to pass as [AiService.chat]'s `previousResponseId` on the next turn so the
/// session continues without re-sending history.
typedef ChatResult = ({String reply, String responseId});

/// Client surface over the Cloud Functions AI callables (AI_proxy.md). There is
/// no client OpenAI key — every call goes through Functions. Errors come back as
/// typed [Failure]s (AiFailure / RateLimitFailure) and are surfaced as the top
/// error banner by the implementation.
abstract class AiService {
  /// Sends a chat message and returns the assistant reply plus a session token.
  /// Pass the previous [ChatResult.responseId] as [previousResponseId] to
  /// continue the conversation within the same session; omit it (or pass null)
  /// to start a fresh thread.
  Future<Result<ChatResult>> chat(String message, {String? previousResponseId});

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
