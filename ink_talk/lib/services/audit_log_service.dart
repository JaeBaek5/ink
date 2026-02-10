import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// 감사 로그 서비스. append-only: 생성만 허용, 수정/삭제 불가.
/// 메시지·스트로크·방·친구 등 생성·수정·삭제 이벤트를 audit_logs에 기록.
class AuditLogService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _auditLogs =>
      _firestore.collection('audit_logs');

  /// 이벤트 기록 (실패해도 메인 플로우는 유지하도록 catch)
  Future<void> log({
    required String eventType,
    required String collection,
    required String documentId,
    required String userId,
    String? roomId,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _auditLogs.add({
        'eventType': eventType,
        'collection': collection,
        'documentId': documentId,
        'userId': userId,
        if (roomId != null) 'roomId': roomId,
        'timestamp': FieldValue.serverTimestamp(),
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      });
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
      // 감사 로그 실패해도 메인 플로우는 유지 (rethrow 하지 않음)
      // assert 제거: Debug 모드에서도 앱이 멈추지 않도록
    }
  }

  // --- 편의 메서드 (이벤트 타입 상수화) ---

  Future<void> logFriendRequestSent(String userId, String documentId, String friendId) =>
      log(eventType: 'friend_request_sent', collection: 'friends', documentId: documentId, userId: userId, payload: {'friendId': friendId});

  Future<void> logFriendRequestAccepted(String userId, String documentId) =>
      log(eventType: 'friend_request_accepted', collection: 'friends', documentId: documentId, userId: userId);

  Future<void> logFriendRequestRejected(String userId, String documentId) =>
      log(eventType: 'friend_request_rejected', collection: 'friends', documentId: documentId, userId: userId);

  Future<void> logFriendHidden(String userId, String documentId, String friendId) =>
      log(eventType: 'friend_hidden', collection: 'friends', documentId: documentId, userId: userId, payload: {'friendId': friendId});

  Future<void> logRoomCreated(String userId, String roomId, String type) =>
      log(eventType: 'room_created', collection: 'rooms', documentId: roomId, userId: userId, roomId: roomId, payload: {'type': type});

  Future<void> logRoomLeave(String userId, String roomId) =>
      log(eventType: 'room_leave', collection: 'rooms', documentId: roomId, userId: userId, roomId: roomId);

  Future<void> logStrokeCreated(String userId, String roomId, String strokeId) =>
      log(eventType: 'stroke_created', collection: 'strokes', documentId: strokeId, userId: userId, roomId: roomId);

  Future<void> logStrokeDeleted(String userId, String roomId, String strokeId) =>
      log(eventType: 'stroke_deleted', collection: 'strokes', documentId: strokeId, userId: userId, roomId: roomId);

  Future<void> logTextCreated(String userId, String roomId, String textId) =>
      log(eventType: 'text_created', collection: 'texts', documentId: textId, userId: userId, roomId: roomId);

  Future<void> logTextDeleted(String userId, String roomId, String textId) =>
      log(eventType: 'text_deleted', collection: 'texts', documentId: textId, userId: userId, roomId: roomId);

  Future<void> logShapeCreated(String userId, String roomId, String shapeId) =>
      log(eventType: 'shape_created', collection: 'shapes', documentId: shapeId, userId: userId, roomId: roomId);

  Future<void> logShapeDeleted(String userId, String roomId, String shapeId) =>
      log(eventType: 'shape_deleted', collection: 'shapes', documentId: shapeId, userId: userId, roomId: roomId);

  Future<void> logMediaCreated(String userId, String roomId, String mediaId) =>
      log(eventType: 'media_created', collection: 'media', documentId: mediaId, userId: userId, roomId: roomId);

  Future<void> logMediaDeleted(String userId, String roomId, String mediaId) =>
      log(eventType: 'media_deleted', collection: 'media', documentId: mediaId, userId: userId, roomId: roomId);
}
