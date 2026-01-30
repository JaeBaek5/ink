import 'package:cloud_firestore/cloud_firestore.dart';

/// 스트로크 포인트
class StrokePoint {
  final double x;
  final double y;
  final double pressure;
  final int timestamp;

  StrokePoint({
    required this.x,
    required this.y,
    this.pressure = 1.0,
    required this.timestamp,
  });

  factory StrokePoint.fromMap(Map<String, dynamic> map) {
    return StrokePoint(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      pressure: (map['p'] as num?)?.toDouble() ?? 1.0,
      timestamp: map['t'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'p': pressure,
      't': timestamp,
    };
  }
}

/// 펜 스타일
class PenStyle {
  final String color; // hex color
  final double width;
  final String penType; // pen, pencil, highlighter

  PenStyle({
    required this.color,
    required this.width,
    this.penType = 'pen',
  });

  factory PenStyle.fromMap(Map<String, dynamic> map) {
    return PenStyle(
      color: map['color'] ?? '#000000',
      width: (map['width'] as num?)?.toDouble() ?? 2.0,
      penType: map['penType'] ?? 'pen',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'color': color,
      'width': width,
      'penType': penType,
    };
  }
}

/// 스트로크 모델 (손글씨)
class StrokeModel {
  final String id;
  final String roomId;
  final String senderId;
  final List<StrokePoint> points;
  final PenStyle style;
  final DateTime createdAt;
  final bool isConfirmed; // 고스트 라이팅 확정 여부
  final bool isDeleted;

  StrokeModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.points,
    required this.style,
    required this.createdAt,
    this.isConfirmed = false,
    this.isDeleted = false,
  });

  factory StrokeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    final pointsData = data['points'] as List<dynamic>? ?? [];
    final points = pointsData
        .map((p) => StrokePoint.fromMap(p as Map<String, dynamic>))
        .toList();

    return StrokeModel(
      id: doc.id,
      roomId: data['roomId'] ?? '',
      senderId: data['senderId'] ?? '',
      points: points,
      style: PenStyle.fromMap(data['style'] as Map<String, dynamic>? ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isConfirmed: data['isConfirmed'] ?? false,
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'roomId': roomId,
      'senderId': senderId,
      'points': points.map((p) => p.toMap()).toList(),
      'style': style.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
      'isConfirmed': isConfirmed,
      'isDeleted': isDeleted,
    };
  }
}
