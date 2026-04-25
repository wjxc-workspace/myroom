import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/recap_item.dart' show Era;
import '../models/idea.dart' show IdeaLink;
import '../models/ai_resource.dart';
export '../models/recap_item.dart' show Era;

// ─── Classification result types ─────────────────────────────────────────────

sealed class ClassificationResult {}

class ClassifiedTodo extends ClassificationResult {
  final String text;
  final String cat;
  ClassifiedTodo({required this.text, required this.cat});
}

class ClassifiedTodoWithTime extends ClassificationResult {
  final String text;
  final String cat;
  final int startDay, startHour, startMin;
  final int endDay, endHour, endMin;
  ClassifiedTodoWithTime({
    required this.text,
    required this.cat,
    required this.startDay,
    required this.startHour,
    required this.startMin,
    required this.endDay,
    required this.endHour,
    required this.endMin,
  });
}

class ClassifiedIdea extends ClassificationResult {
  final String text;
  ClassifiedIdea({required this.text});
}

class ClassifiedNote extends ClassificationResult {
  final String dateKey; // YYYY-MM-DD
  final String content;
  ClassifiedNote({required this.dateKey, required this.content});
}

class ClassifiedRecap extends ClassificationResult {
  final Era era;
  final String title;
  final String desc;
  final String date;
  ClassifiedRecap({
    required this.era,
    required this.title,
    required this.desc,
    required this.date,
  });
}

class ClassificationError extends ClassificationResult {
  final String message;
  final String? rawText; // original user input, for fallback
  ClassificationError({required this.message, this.rawText});
}

// ─── Idea enrichment types ────────────────────────────────────────────────────

class IdeaEnrichment {
  final String summary;
  final List<IdeaLink> links;
  const IdeaEnrichment({required this.summary, required this.links});
}

// ─── OpenAI service ───────────────────────────────────────────────────────────

class OpenAIService {
  OpenAIService._();
  static final OpenAIService instance = OpenAIService._();

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  // ── Classification ──────────────────────────────────────────────────────────

  static const _classificationSystemPrompt = '''
你是一個個人生產力助理的資料分類引擎。
使用者輸入任意文字，你必須判斷它屬於哪一種類型，並回傳 JSON。

可能的類型：
1. "todo"：一件需要完成的事（沒有明確時間）
   → { "type":"todo", "text":"任務描述", "cat":"工作|學習|個人|健康" }

2. "todo_with_time"：有明確時間的行程或任務
   → { "type":"todo_with_time", "text":"標題", "cat":"工作|學習|個人|健康",
       "start_day":24, "start_hour":9, "start_min":0,
       "end_day":24, "end_hour":10, "end_min":0 }
   （日期只用月份中的「日」數字，例如 4月24日 → 24）

3. "idea"：靈感、想法、創意
   → { "type":"idea", "text":"靈感內容" }

4. "note"：日記、心情、反思、隨筆
   → { "type":"note", "date_key":"YYYY-MM-DD", "content":"完整內容" }
   （date_key 用今天日期，除非使用者明確指定其他日期）

5. "recap"：成就、目標、里程碑
   → { "type":"recap", "era":"past|now|future", "title":"標題", "desc":"描述", "date":"日期字串" }

規則：
- 只回傳 JSON，不要其他文字
- 若無法確定，優先選 "note"
- cat 只能是：工作、學習、個人、健康
- era 只能是：past、now、future
- 今天日期由系統提供''';

  Future<ClassificationResult> classifyInput(String text) async {
    assert(
      AppConfig.openAiApiKey != 'sk-YOUR_KEY_HERE',
      'Please set your OpenAI API key in lib/config.dart',
    );

    final today = _todayStr();

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer ${AppConfig.openAiApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': AppConfig.openAiModel,
              'messages': [
                {
                  'role': 'system',
                  'content': '$_classificationSystemPrompt\n今天日期：$today',
                },
                {'role': 'user', 'content': text},
              ],
              'response_format': {'type': 'json_object'},
              'temperature': 0.2,
              'max_tokens': 200,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('OpenAI error ${response.statusCode}: ${response.body}');
        return ClassificationError(
          message: 'API 回應錯誤（${response.statusCode}）',
          rawText: text,
        );
      }

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final content = body['choices'][0]['message']['content'] as String;
      return _parseClassification(content, text);
    } on SocketException {
      return ClassificationError(message: '無法連線，請確認網路', rawText: text);
    } on TimeoutException {
      return ClassificationError(message: '請求逾時', rawText: text);
    } catch (e) {
      debugPrint('classifyInput error: $e');
      return ClassificationError(message: '未知錯誤', rawText: text);
    }
  }

  ClassificationResult _parseClassification(String content, String rawText) {
    try {
      final j = jsonDecode(content) as Map<String, dynamic>;
      final type = j['type'] as String? ?? '';

      switch (type) {
        case 'todo':
          return ClassifiedTodo(
            text: j['text'] as String? ?? rawText,
            cat: _safecat(j['cat']),
          );

        case 'todo_with_time':
          return ClassifiedTodoWithTime(
            text: j['text'] as String? ?? rawText,
            cat: _safecat(j['cat']),
            startDay: (j['start_day'] as num?)?.toInt() ?? 24,
            startHour: (j['start_hour'] as num?)?.toInt() ?? 9,
            startMin: (j['start_min'] as num?)?.toInt() ?? 0,
            endDay: (j['end_day'] as num?)?.toInt() ?? 24,
            endHour: (j['end_hour'] as num?)?.toInt() ?? 10,
            endMin: (j['end_min'] as num?)?.toInt() ?? 0,
          );

        case 'idea':
          return ClassifiedIdea(text: j['text'] as String? ?? rawText);

        case 'note':
          return ClassifiedNote(
            dateKey: j['date_key'] as String? ?? _todayStr(),
            content: j['content'] as String? ?? rawText,
          );

        case 'recap':
          final eraStr = j['era'] as String? ?? 'now';
          final era = Era.values.firstWhere(
            (e) => e.name == eraStr,
            orElse: () => Era.now,
          );
          return ClassifiedRecap(
            era: era,
            title: j['title'] as String? ?? rawText,
            desc: j['desc'] as String? ?? '',
            date: j['date'] as String? ?? _todayStr(),
          );

        default:
          // Fallback: save as note
          return ClassifiedNote(dateKey: _todayStr(), content: rawText);
      }
    } on FormatException {
      return ClassificationError(message: 'JSON 解析失敗', rawText: rawText);
    }
  }

  String _safecat(dynamic v) {
    const valid = ['工作', '學習', '個人', '健康'];
    final s = v as String? ?? '';
    return valid.contains(s) ? s : '個人';
  }

  // ── Chat ────────────────────────────────────────────────────────────────────

  Future<String> chat(
    List<Map<String, String>> history,
    String contextSummary,
  ) async {
    assert(
      AppConfig.openAiApiKey != 'sk-YOUR_KEY_HERE',
      'Please set your OpenAI API key in lib/config.dart',
    );

    final systemMsg = '你是 MyRoom 個人助理。以下是使用者的完整資料：\n\n$contextSummary\n\n'
        '請用繁體中文回答，語氣簡潔友善。回答盡量不超過 150 字，除非需要列表。';

    final messages = [
      {'role': 'system', 'content': systemMsg},
      ...history,
    ];

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer ${AppConfig.openAiApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': AppConfig.openAiModel,
              'messages': messages,
              'temperature': 0.7,
              'max_tokens': 600,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('OpenAI chat error ${response.statusCode}: ${response.body}');
        return 'AI 服務暫時無法使用（${response.statusCode}），請稍後再試。';
      }

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body['choices'][0]['message']['content'] as String? ?? '（無回應）';
    } on SocketException {
      return '無法連線，請確認網路連線後再試。';
    } on TimeoutException {
      return '請求逾時，請稍後再試。';
    } catch (e) {
      debugPrint('chat error: $e');
      return '發生未知錯誤，請再試一次。';
    }
  }

  // ── Idea enrichment ─────────────────────────────────────────────────────────

  static const _enrichSystemPrompt =
      '你是一個知識整理助理。使用者輸入一個靈感或想法，你需要：\n'
      '1. 用一句話（繁體中文，20-40字）概括這個靈感的核心洞察\n'
      '2. 提供 2-3 個與此靈感相關的知名資源（書籍、論文、網站或工具）\n\n'
      '回傳嚴格 JSON（不含其他文字）：\n'
      '{ "summary": "...", "links": [{"title":"...","url":"https://..."}] }\n\n'
      '規則：summary 必須是繁體中文，簡潔有力；links 最多 3 個；url 使用真實知名網址；只回傳 JSON';

  Future<IdeaEnrichment?> enrichIdea(String ideaText) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer ${AppConfig.openAiApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': AppConfig.openAiModel,
              'messages': [
                {'role': 'system', 'content': _enrichSystemPrompt},
                {'role': 'user', 'content': ideaText},
              ],
              'response_format': {'type': 'json_object'},
              'temperature': 0.5,
              'max_tokens': 300,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final content = body['choices'][0]['message']['content'] as String;
      final json = jsonDecode(content) as Map<String, dynamic>;

      final summary = json['summary'] as String? ?? '';
      final rawLinks = json['links'] as List? ?? [];
      final links = rawLinks
          .map((l) => IdeaLink(
                title: l['title'] as String? ?? '',
                url: l['url'] as String? ?? '',
              ))
          .where((l) => l.title.isNotEmpty && l.url.isNotEmpty)
          .toList();

      return IdeaEnrichment(summary: summary, links: links);
    } catch (e) {
      debugPrint('enrichIdea error: $e');
      return null;
    }
  }

  // ── Resource recommendations ─────────────────────────────────────────────────

  static const _recommendSystemPrompt =
      '你是一個知識推薦助理。根據使用者的靈感清單，推薦 4-6 個最相關的學習資源。\n\n'
      '回傳嚴格 JSON（不含其他文字）：\n'
      '{"resources":[{"title":"...","type":"書籍|文章|工具|課程|網站","desc":"一句話說明（繁體中文，20字以內）","url":"https://..."}]}\n\n'
      '規則：url 使用真實知名網址；只回傳 JSON';

  Future<List<AiResource>> fetchRecommendations(List<String> ideaTexts) async {
    if (ideaTexts.isEmpty) return [];
    try {
      final numbered = ideaTexts
          .take(5)
          .toList()
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      final prompt = '我的靈感清單：\n$numbered';

      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer ${AppConfig.openAiApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': AppConfig.openAiModel,
              'messages': [
                {'role': 'system', 'content': _recommendSystemPrompt},
                {'role': 'user', 'content': prompt},
              ],
              'response_format': {'type': 'json_object'},
              'temperature': 0.6,
              'max_tokens': 600,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return [];

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final content = body['choices'][0]['message']['content'] as String;
      final rawList = (jsonDecode(content)['resources'] as List?) ?? [];

      return rawList
          .map((r) => AiResource(
                title: r['title'] as String? ?? '',
                type: r['type'] as String? ?? '資源',
                desc: r['desc'] as String? ?? '',
                url: r['url'] as String? ?? '',
              ))
          .where((r) => r.title.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('fetchRecommendations error: $e');
      return [];
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }
}
