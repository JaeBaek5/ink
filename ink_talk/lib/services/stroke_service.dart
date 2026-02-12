import 'dart:async';
import 'dart:math' show sqrt;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/stroke_model.dart';
import 'audit_log_service.dart';

/// 스트로크 서비스 (실시간 동기화)
class StrokeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuditLogService _auditLog = AuditLogService();

  /// 스트로크 컬렉션 참조
  CollectionReference<Map<String, dynamic>> _strokesCollection(String roomId) {
    return _firestore.collection('rooms').doc(roomId).collection('strokes');
  }

  /// 차단 기간 중 해당 발신자가 보낸 스트로크 수 (친구 차단 관리 표시용)
  Future<int> countStrokesFromSenderAfter(
      String roomId, String senderId, DateTime after) async {
    try {
      final snapshot = await _strokesCollection(roomId)
          .where('senderId', isEqualTo: senderId)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(after))
          .where('isDeleted', isEqualTo: false)
          .get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// 스트로크 1회 로드 (캔버스 진입 시 Firestore Read 1회, 실시간은 RTDB로)
  Future<List<StrokeModel>> getStrokes(String roomId) async {
    final snapshot = await _strokesCollection(roomId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: false)
        .get();
    return snapshot.docs.map((doc) => StrokeModel.fromFirestore(doc)).toList();
  }

  /// 스트로크 실시간 스트림 (레거시; 실시간은 RTDB 사용 권장)
  Stream<List<StrokeModel>> getStrokesStream(String roomId) {
    return _strokesCollection(roomId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => StrokeModel.fromFirestore(doc)).toList();
    });
  }

  /// 스트로크 저장 (새 스트로크)
  Future<String> saveStroke(StrokeModel stroke) async {
    try {
      final docRef = await _strokesCollection(stroke.roomId).add(stroke.toFirestore());
      _auditLog.logStrokeCreated(stroke.senderId, stroke.roomId, docRef.id);
      return docRef.id;
    } catch (e) {
      debugPrint('스트로크 저장 실패: $e');
      rethrow;
    }
  }

  /// 스트로크 업데이트 (확정)
  Future<void> confirmStroke(String roomId, String strokeId) async {
    try {
      await _strokesCollection(roomId).doc(strokeId).update({
        'isConfirmed': true,
      });
    } catch (e) {
      debugPrint('스트로크 확정 실패: $e');
    }
  }

  /// 스트로크 포인트 업데이트 (이동 시)
  Future<void> updateStrokePoints(String roomId, String strokeId, List<StrokePoint> points) async {
    try {
      await _strokesCollection(roomId).doc(strokeId).update({
        'points': points.map((p) => p.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('스트로크 포인트 업데이트 실패: $e');
      rethrow;
    }
  }

  /// 스트로크 삭제 (소프트 삭제). deletedAt, deletedBy 기록 → 운영자 복구 가능.
  Future<void> deleteStroke(String roomId, String strokeId, {String? userId}) async {
    try {
      final updates = <String, dynamic>{'isDeleted': true};
      if (userId != null) {
        updates['deletedAt'] = FieldValue.serverTimestamp();
        updates['deletedBy'] = userId;
      }
      await _strokesCollection(roomId).doc(strokeId).update(updates);
      if (userId != null) _auditLog.logStrokeDeleted(userId, roomId, strokeId);
    } catch (e) {
      debugPrint('스트로크 삭제 실패: $e');
    }
  }

  /// 여러 스트로크 삭제
  Future<void> deleteStrokes(String roomId, List<String> strokeIds, {String? userId}) async {
    if (strokeIds.isEmpty) return;
    final batch = _firestore.batch();
    final updates = <String, dynamic>{'isDeleted': true};
    if (userId != null) {
      updates['deletedAt'] = FieldValue.serverTimestamp();
      updates['deletedBy'] = userId;
    }
    for (final id in strokeIds) {
      batch.update(_strokesCollection(roomId).doc(id), updates);
    }
    await batch.commit();
    if (userId != null) {
      for (final id in strokeIds) {
        _auditLog.logStrokeDeleted(userId, roomId, id);
      }
    }
  }

  /// 스트로크 복구 (Undo/Redo용)
  Future<void> restoreStroke(String roomId, String strokeId) async {
    try {
      await _strokesCollection(roomId).doc(strokeId).update({
        'isDeleted': false,
      });
    } catch (e) {
      debugPrint('스트로크 복구 실패: $e');
    }
  }

  /// Douglas-Peucker 알고리즘 (좌표 압축)
  static List<StrokePoint> simplifyPoints(List<StrokePoint> points, double epsilon) {
    if (points.length < 3) return points;

    // 시작점과 끝점 사이의 가장 먼 점 찾기
    double maxDist = 0;
    int maxIndex = 0;

    final first = points.first;
    final last = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final dist = _perpendicularDistance(points[i], first, last);
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }

    // 임계값보다 크면 재귀적으로 분할
    if (maxDist > epsilon) {
      final left = simplifyPoints(points.sublist(0, maxIndex + 1), epsilon);
      final right = simplifyPoints(points.sublist(maxIndex), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  static double _perpendicularDistance(StrokePoint point, StrokePoint lineStart, StrokePoint lineEnd) {
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;

    if (dx == 0 && dy == 0) {
      return _distance(point, lineStart);
    }

    final t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (dx * dx + dy * dy);

    if (t < 0) {
      return _distance(point, lineStart);
    } else if (t > 1) {
      return _distance(point, lineEnd);
    }

    final projection = StrokePoint(
      x: lineStart.x + t * dx,
      y: lineStart.y + t * dy,
      timestamp: 0,
    );
    return _distance(point, projection);
  }

  static double _distance(StrokePoint a, StrokePoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }
}
