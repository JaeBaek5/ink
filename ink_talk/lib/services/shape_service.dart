import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/shape_model.dart';

/// 도형 서비스
class ShapeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 도형 컬렉션 참조
  CollectionReference<Map<String, dynamic>> _shapesCollection(String roomId) {
    return _firestore.collection('rooms').doc(roomId).collection('shapes');
  }

  /// 도형 실시간 스트림
  Stream<List<ShapeModel>> getShapesStream(String roomId) {
    return _shapesCollection(roomId)
        .snapshots()
        .map((snapshot) {
      final shapes = snapshot.docs
          .map((doc) => ShapeModel.fromFirestore(doc))
          .where((shape) => !shape.isDeleted)
          .toList();
      // zIndex 순 정렬 (클라이언트)
      shapes.sort((a, b) => a.zIndex.compareTo(b.zIndex));
      return shapes;
    });
  }

  /// 도형 저장
  Future<String> saveShape(ShapeModel shape) async {
    try {
      final docRef = await _shapesCollection(shape.roomId).add(shape.toFirestore());
      return docRef.id;
    } catch (e) {
      debugPrint('도형 저장 실패: $e');
      rethrow;
    }
  }

  /// 도형 업데이트
  Future<void> updateShape(String roomId, String shapeId, {
    double? startX,
    double? startY,
    double? endX,
    double? endY,
    String? strokeColor,
    double? strokeWidth,
    String? fillColor,
    double? fillOpacity,
    LineStyle? lineStyle,
    bool? isLocked,
    int? zIndex,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (startX != null) updates['startX'] = startX;
      if (startY != null) updates['startY'] = startY;
      if (endX != null) updates['endX'] = endX;
      if (endY != null) updates['endY'] = endY;
      if (strokeColor != null) updates['strokeColor'] = strokeColor;
      if (strokeWidth != null) updates['strokeWidth'] = strokeWidth;
      if (fillColor != null) updates['fillColor'] = fillColor;
      if (fillOpacity != null) updates['fillOpacity'] = fillOpacity;
      if (lineStyle != null) updates['lineStyle'] = lineStyle.name;
      if (isLocked != null) updates['isLocked'] = isLocked;
      if (zIndex != null) updates['zIndex'] = zIndex;

      if (updates.isNotEmpty) {
        await _shapesCollection(roomId).doc(shapeId).update(updates);
      }
    } catch (e) {
      debugPrint('도형 업데이트 실패: $e');
    }
  }

  /// 도형 삭제 (소프트 삭제)
  Future<void> deleteShape(String roomId, String shapeId) async {
    try {
      await _shapesCollection(roomId).doc(shapeId).update({
        'isDeleted': true,
      });
    } catch (e) {
      debugPrint('도형 삭제 실패: $e');
    }
  }

  /// 레이어 순서 변경 (앞으로)
  Future<void> bringToFront(String roomId, String shapeId, int maxZIndex) async {
    await updateShape(roomId, shapeId, zIndex: maxZIndex + 1);
  }

  /// 레이어 순서 변경 (뒤로)
  Future<void> sendToBack(String roomId, String shapeId) async {
    await updateShape(roomId, shapeId, zIndex: -1);
  }
}
