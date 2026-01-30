import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/stroke_model.dart';

/// 스트로크 서비스 (실시간 동기화)
class StrokeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 스트로크 컬렉션 참조
  CollectionReference<Map<String, dynamic>> _strokesCollection(String roomId) {
    return _firestore.collection('rooms').doc(roomId).collection('strokes');
  }

  /// 스트로크 실시간 스트림
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

  /// 스트로크 삭제 (소프트 삭제)
  Future<void> deleteStroke(String roomId, String strokeId) async {
    try {
      await _strokesCollection(roomId).doc(strokeId).update({
        'isDeleted': true,
      });
    } catch (e) {
      debugPrint('스트로크 삭제 실패: $e');
    }
  }

  /// 여러 스트로크 삭제
  Future<void> deleteStrokes(String roomId, List<String> strokeIds) async {
    final batch = _firestore.batch();
    for (final id in strokeIds) {
      batch.update(_strokesCollection(roomId).doc(id), {'isDeleted': true});
    }
    await batch.commit();
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
    return (dx * dx + dy * dy);
  }
}
