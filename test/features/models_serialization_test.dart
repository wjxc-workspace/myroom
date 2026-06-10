// Model serialization round-trips (Test.md §2). Covers the map-based
// serializers that need no Firestore `DocumentSnapshot` — the embedded category
// refs, idea links, note attachments, and the AI resource DTO. The
// `fromFirestore` paths that require a live snapshot are exercised by the
// emulator-based repo tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myroom/features/ideas/domain/idea.dart';
import 'package:myroom/features/notes/domain/note.dart';
import 'package:myroom/features/todo/domain/todo.dart';
import 'package:myroom/shared/ai/domain/ai_resource.dart';

void main() {
  group('TodoCategoryRef', () {
    test('toMap → fromMap round-trips id/label/color', () {
      const ref = TodoCategoryRef(
          id: 'c1', label: '工作', color: Color(0xFF7B9E87));
      final back = TodoCategoryRef.fromMap(ref.toMap());
      expect(back.id, 'c1');
      expect(back.label, '工作');
      expect(back.color.toARGB32(), 0xFF7B9E87);
    });

    test('fromMap(null) falls back to the undefined sentinel', () {
      final back = TodoCategoryRef.fromMap(null);
      expect(back.id, 'undefined');
      expect(back.label, '無分類');
    });
  });

  group('NoteCategoryRef', () {
    test('toMap → fromMap round-trips incl. iconName', () {
      const ref = NoteCategoryRef(
          id: 'n1', label: '心情', color: Color(0xFFBFA97A), iconName: 'heart');
      final back = NoteCategoryRef.fromMap(ref.toMap());
      expect(back.id, 'n1');
      expect(back.label, '心情');
      expect(back.iconName, 'heart');
      expect(back.color.toARGB32(), 0xFFBFA97A);
    });

    test('fromMap(null) falls back to the undefined sentinel', () {
      final back = NoteCategoryRef.fromMap(null);
      expect(back.id, 'undefined');
      expect(back.iconName, 'tag');
    });
  });

  group('NoteAttachment', () {
    test('toMap → fromMap round-trips', () {
      const a = NoteAttachment(
          type: 'image', filename: 'p.png', storagePath: 'u/1/p', attId: 'h');
      final back = NoteAttachment.fromMap(a.toMap());
      expect(back.type, 'image');
      expect(back.filename, 'p.png');
      expect(back.storagePath, 'u/1/p');
      expect(back.attId, 'h');
    });

    test('fromMap defaults missing fields', () {
      final back = NoteAttachment.fromMap(const {});
      expect(back.type, 'file');
      expect(back.filename, '');
    });
  });

  group('IdeaLink', () {
    test('toMap → fromMap round-trips', () {
      const l = IdeaLink(title: '書', url: 'https://x');
      final back = IdeaLink.fromMap(l.toMap());
      expect(back.title, '書');
      expect(back.url, 'https://x');
    });
  });

  group('AiResource.fromJson', () {
    test('reads all fields', () {
      final r = AiResource.fromJson({
        'title': 'Clean Code',
        'type': '書籍',
        'description': '寫好程式',
        'url': 'https://x',
      });
      expect(r.title, 'Clean Code');
      expect(r.type, '書籍');
      expect(r.description, '寫好程式');
      expect(r.url, 'https://x');
    });

    test('defaults missing fields to empty', () {
      final r = AiResource.fromJson(const {});
      expect(r.title, '');
      expect(r.url, '');
    });
  });
}
