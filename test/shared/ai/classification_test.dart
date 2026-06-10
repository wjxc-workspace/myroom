// Pure-logic parsing tests for the `classifyMultiInput` contract
// (Test.md §2: discriminator + 5 item types). No Firebase needed — the server
// returns plain normalized maps that `ClassificationItem.fromJson` decodes.
import 'package:flutter_test/flutter_test.dart';
import 'package:myroom/shared/ai/domain/classification.dart';

void main() {
  group('ClassificationItem.fromJson', () {
    test('todo carries text + catId', () {
      final item = ClassificationItem.fromJson({
        'type': 'todo',
        'text': '買牛奶',
        'catId': 'cat123',
      });
      expect(item, isA<ClassifiedTodo>());
      final t = item as ClassifiedTodo;
      expect(t.text, '買牛奶');
      expect(t.catId, 'cat123');
    });

    test('todo defaults missing catId to the undefined sentinel', () {
      final item = ClassificationItem.fromJson({'type': 'todo', 'text': 'x'});
      expect((item as ClassifiedTodo).catId, 'undefined');
    });

    test('todo_with_time parses start/end into DateTime', () {
      final item = ClassificationItem.fromJson({
        'type': 'todo_with_time',
        'text': '開會',
        'catId': 'undefined',
        'start': {
          'year': 2026,
          'month': 6,
          'day': 10,
          'hour': 10,
          'minute': 0,
        },
        'end': {
          'year': 2026,
          'month': 6,
          'day': 10,
          'hour': 11,
          'minute': 30,
        },
      });
      expect(item, isA<ClassifiedTodoWithTime>());
      final tt = item as ClassifiedTodoWithTime;
      expect(tt.start, DateTime(2026, 6, 10, 10, 0));
      expect(tt.end, DateTime(2026, 6, 10, 11, 30));
    });

    test('idea carries text', () {
      final item = ClassificationItem.fromJson({'type': 'idea', 'text': '學插畫'});
      expect((item as ClassifiedIdea).text, '學插畫');
    });

    test('note carries dateKey, noteCatId, content, attachmentIndices', () {
      final item = ClassificationItem.fromJson({
        'type': 'note',
        'dateKey': '2026-06-10',
        'noteCatId': 'n1',
        'content': '今天心情很好',
        'attachmentIndices': [0, 2],
      });
      expect(item, isA<ClassifiedNote>());
      final n = item as ClassifiedNote;
      expect(n.dateKey, '2026-06-10');
      expect(n.noteCatId, 'n1');
      expect(n.content, '今天心情很好');
      expect(n.attachmentIndices, [0, 2]);
    });

    test('note defaults missing attachmentIndices to empty', () {
      final item = ClassificationItem.fromJson({
        'type': 'note',
        'content': 'hi',
      });
      expect((item as ClassifiedNote).attachmentIndices, isEmpty);
    });

    test('recap carries title + description', () {
      final item = ClassificationItem.fromJson({
        'type': 'recap',
        'title': '六月回顧',
        'description': '充實的一個月',
      });
      expect(item, isA<ClassifiedRecap>());
      final r = item as ClassifiedRecap;
      expect(r.title, '六月回顧');
      expect(r.description, '充實的一個月');
    });

    test('unknown discriminator returns null', () {
      expect(ClassificationItem.fromJson({'type': 'mystery'}), isNull);
      expect(ClassificationItem.fromJson(const {}), isNull);
    });
  });
}
