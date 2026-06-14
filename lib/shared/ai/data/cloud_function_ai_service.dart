import 'dart:convert';
import 'dart:typed_data';

// `cloud_functions` also exports a `Result` type — hide it so ours wins.
import 'package:cloud_functions/cloud_functions.dart' hide Result;

import '../../../core/app_errors.dart';
import '../../../core/firebase_failure.dart';
import '../../../core/result.dart';
import '../domain/ai_resource.dart';
import '../domain/ai_service.dart';
import '../domain/classification.dart';

/// [AiService] over Firebase Cloud Functions callables (AI_proxy.md §8). Any
/// `FirebaseFunctionsException` is mapped to a typed [Failure] (`resource-exhausted`
/// → RateLimitFailure, otherwise AiFailure) and surfaced as the top banner.
class CloudFunctionAiService implements AiService {
  CloudFunctionAiService(this._functions);

  final FirebaseFunctions _functions;

  HttpsCallable _fn(String name, {Duration? timeout}) => _functions.httpsCallable(
        name,
        options: HttpsCallableOptions(
          timeout: timeout ?? const Duration(seconds: 70),
        ),
      );

  Future<Result<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } catch (e) {
      final f = mapFirebase(e);
      AppErrors.present(f);
      return Err(f);
    }
  }

  static Map<String, dynamic> _asMap(Object? data) =>
      Map<String, dynamic>.from((data as Map?) ?? const {});

  @override
  Future<Result<ChatResult>> chat(
    String message, {
    String? previousResponseId,
  }) =>
      _guard(() async {
        final res = await _fn('chat', timeout: const Duration(seconds: 120))
            .call<Object?>({
          'message': message,
          if (previousResponseId != null && previousResponseId.isNotEmpty)
            'previousResponseId': previousResponseId,
        });
        final data = _asMap(res.data);
        return (
          reply: (data['reply'] as String?) ?? '',
          responseId: (data['responseId'] as String?) ?? '',
        );
      });

  @override
  Future<Result<List<ClassificationItem>>> classifyMultiInput({
    required String text,
    List<String> images = const [],
    String fileText = '',
    List<AiAttachmentRef> attachments = const [],
    String? userSpecifiedCat,
  }) =>
      _guard(() async {
        final res = await _fn('classifyMultiInput').call<Object?>({
          'text': text,
          'images': images,
          'fileText': fileText,
          'attachments': attachments.map((a) => a.toJson()).toList(),
          'userSpecifiedCat': userSpecifiedCat ?? '',
        });
        final items = (_asMap(res.data)['items'] as List?) ?? const [];
        return items
            .map((e) =>
                ClassificationItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .whereType<ClassificationItem>()
            .toList();
      });

  @override
  Future<Result<List<AiResource>>> fetchRecommendations(
    List<String> ideaTexts,
  ) =>
      _guard(() async {
        final res = await _fn('fetchRecommendations')
            .call<Object?>({'ideaTexts': ideaTexts});
        final list = (_asMap(res.data)['resources'] as List?) ?? const [];
        return list
            .map((e) => AiResource.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      });

  @override
  Future<Result<String>> generateEraInsight({
    required String eraLabel,
    required String dataSummary,
  }) =>
      _guard(() async {
        final res = await _fn('generateEraInsight').call<Object?>({
          'eraLabel': eraLabel,
          'dataSummary': dataSummary,
        });
        return (_asMap(res.data)['text'] as String?) ?? '';
      });

  @override
  Future<Result<String>> transcribe({
    required Uint8List audioBytes,
    required String filename,
  }) =>
      _guard(() async {
        final res =
            await _fn('transcribe', timeout: const Duration(seconds: 120))
                .call<Object?>({
          'audioB64': base64Encode(audioBytes),
          'filename': filename,
        });
        return (_asMap(res.data)['transcript'] as String?) ?? '';
      });

  @override
  Future<Result<String>> exportRecap(String recapId) => _guard(() async {
        final res = await _fn('exportRecap', timeout: const Duration(seconds: 120))
            .call<Object?>({'recapId': recapId});
        return (_asMap(res.data)['storagePath'] as String?) ?? '';
      });

  @override
  Future<Result<String>> exportAchievement({
    required String achievementId,
    required String era,
  }) =>
      _guard(() async {
        final res =
            await _fn('exportAchievement', timeout: const Duration(seconds: 120))
                .call<Object?>({
          'achievementId': achievementId,
          'era': era,
        });
        return (_asMap(res.data)['storagePath'] as String?) ?? '';
      });
}
