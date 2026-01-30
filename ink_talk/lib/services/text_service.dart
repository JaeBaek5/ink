import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';

/// 텍스트 서비스 (캔버스 텍스트 오브젝트)
class TextService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 텍스트 컬렉션 참조
  CollectionReference<Map<String, dynamic>> _textsCollection(String roomId) {
    return _firestore.collection('rooms').doc(roomId).collection('texts');
  }

  /// 텍스트 실시간 스트림
  Stream<List<MessageModel>> getTextsStream(String roomId) {
    return _textsCollection(roomId)
        .snapshots()
        .map((snapshot) {
      final texts = snapshot.docs
          .map((doc) => MessageModel.fromFirestore(doc))
          .where((text) => !text.isDeleted)
          .toList();
      // 시간순 정렬 (클라이언트)
      texts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return texts;
    });
  }

  /// 텍스트 저장
  Future<String> saveText(MessageModel text) async {
    try {
      final docRef = await _textsCollection(text.roomId).add(text.toFirestore());
      return docRef.id;
    } catch (e) {
      debugPrint('텍스트 저장 실패: $e');
      rethrow;
    }
  }

  /// 텍스트 업데이트
  Future<void> updateText(String roomId, String textId, {
    String? content,
    double? positionX,
    double? positionY,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (content != null) updates['content'] = content;
      if (positionX != null) updates['positionX'] = positionX;
      if (positionY != null) updates['positionY'] = positionY;
      
      if (updates.isNotEmpty) {
        await _textsCollection(roomId).doc(textId).update(updates);
      }
    } catch (e) {
      debugPrint('텍스트 업데이트 실패: $e');
    }
  }

  /// 텍스트 삭제 (소프트 삭제)
  Future<void> deleteText(String roomId, String textId) async {
    try {
      await _textsCollection(roomId).doc(textId).update({
        'isDeleted': true,
      });
    } catch (e) {
      debugPrint('텍스트 삭제 실패: $e');
    }
  }
}
