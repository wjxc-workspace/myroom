import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/chat_message.dart';
import '../domain/chat_repo.dart';

class FirebaseChatRepo implements ChatRepo {
  FirebaseChatRepo(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  static const int _pageSize = 50;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(_uid).collection('chat_messages');

  @override
  Stream<List<ChatMessage>> watchMessages() => _col
      .orderBy('createdAt', descending: true)
      .limit(_pageSize)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromFirestore).toList().reversed.toList());

  @override
  Future<List<ChatMessage>> loadOlder(DateTime before) async {
    final snap = await _col
        .where('createdAt', isLessThan: Timestamp.fromDate(before))
        .orderBy('createdAt', descending: true)
        .limit(_pageSize)
        .get();
    return snap.docs.map(ChatMessage.fromFirestore).toList().reversed.toList();
  }
}
