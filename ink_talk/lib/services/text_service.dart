import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import 'audit_log_service.dart';

/// 텍스트 서비스 (캔버스 텍스트 오브젝트)
class TextService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuditLogService _auditLog = AuditLogService();

  /// 텍스트 컬렉션 참조
  CollectionReference<Map<String, dynamic>> _textsCollection(String roomId) {
    return _firestore.collection('rooms').doc(roomId).collection('texts');
  }

  /// 차단 기간 중 해당 발신자가 보낸 텍스트 수 (친구 차단 관리 표시용)
  Future<int> countTextsFromSenderAfter(
      String roomId, String senderId, DateTime after) async {
    try {
      final snapshot = await _textsCollection(roomId)
          .where('senderId', isEqualTo: senderId)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(after))
          .where('isDeleted', isEqualTo: false)
          .get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// 텍스트 1회 로드 (캔버스 진입 시 Firestore Read 1회, 실시간은 RTDB로)
  Future<List<MessageModel>> getTexts(String roomId) async {
    final snapshot = await _textsCollection(roomId).get();
    final texts = snapshot.docs
        .map((doc) => MessageModel.fromFirestore(doc))
        .where((text) => !text.isDeleted)
        .toList();
    texts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return texts;
  }

  /// 텍스트 실시간 스트림 (레거시; 실시간은 RTDB 사용 권장)
  Stream<List<MessageModel>> getTextsStream(String roomId) {
    return _textsCollection(roomId)
        .snapshots()
        .map((snapshot) {
      final texts = snapshot.docs
          .map((doc) => MessageModel.fromFirestore(doc))
          .where((text) => !text.isDeleted)
          .toList();
      texts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return texts;
    });
  }

  /// 텍스트 저장
  Future<String> saveText(MessageModel text) async {
    try {
      final docRef = await _textsCollection(text.roomId).add(text.toFirestore());
      _auditLog.logTextCreated(text.senderId, text.roomId, docRef.id);
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

  /// 텍스트 삭제 (소프트 삭제). deletedAt, deletedBy 기록 → 운영자 복구 가능.
  Future<void> deleteText(String roomId, String textId, {String? userId}) async {
    try {
      final updates = <String, dynamic>{'isDeleted': true};
      if (userId != null) {
        updates['deletedAt'] = FieldValue.serverTimestamp();
        updates['deletedBy'] = userId;
      }
      await _textsCollection(roomId).doc(textId).update(updates);
      if (userId != null) _auditLog.logTextDeleted(userId, roomId, textId);
    } catch (e) {
      debugPrint('텍스트 삭제 실패: $e');
    }
  }
}
