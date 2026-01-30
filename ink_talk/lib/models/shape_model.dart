import 'package:cloud_firestore/cloud_firestore.dart';

/// 도형 타입
enum ShapeType {
  line,      // 선
  arrow,     // 화살표
  rectangle, // 사각형
  ellipse,   // 원/타원
}

/// 선 스타일
enum LineStyle {
  solid,  // 실선
  dashed, // 점선
  dotted, // 점점선
}

/// 도형 수정 권한
enum ShapePermission {
  all,       // 모두 수정 가능
  authorOnly, // 작성자만
  adminOnly,  // Owner/Admin만
}

/// 도형 모델
class ShapeModel {
  final String id;
  final String roomId;
  final String senderId;
  final ShapeType type;
  
  // 위치 (시작점, 끝점)
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  
  // 스타일
  final String strokeColor; // hex color
  final double strokeWidth;
  final String? fillColor;  // hex color (null = 투명)
  final double fillOpacity;
  final LineStyle lineStyle;
  
  // 편집
  final bool isLocked;
  final int zIndex; // 레이어 순서
  
  final DateTime createdAt;
  final bool isDeleted;

  ShapeModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.type,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    this.strokeColor = '#000000',
    this.strokeWidth = 2.0,
    this.fillColor,
    this.fillOpacity = 1.0,
    this.lineStyle = LineStyle.solid,
    this.isLocked = false,
    this.zIndex = 0,
    required this.createdAt,
    this.isDeleted = false,
  });

  factory ShapeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ShapeModel(
      id: doc.id,
      roomId: data['roomId'] ?? '',
      senderId: data['senderId'] ?? '',
      type: ShapeType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => ShapeType.rectangle,
      ),
      startX: (data['startX'] as num?)?.toDouble() ?? 0,
      startY: (data['startY'] as num?)?.toDouble() ?? 0,
      endX: (data['endX'] as num?)?.toDouble() ?? 0,
      endY: (data['endY'] as num?)?.toDouble() ?? 0,
      strokeColor: data['strokeColor'] ?? '#000000',
      strokeWidth: (data['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      fillColor: data['fillColor'],
      fillOpacity: (data['fillOpacity'] as num?)?.toDouble() ?? 1.0,
      lineStyle: LineStyle.values.firstWhere(
        (e) => e.name == data['lineStyle'],
        orElse: () => LineStyle.solid,
      ),
      isLocked: data['isLocked'] ?? false,
      zIndex: data['zIndex'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'roomId': roomId,
      'senderId': senderId,
      'type': type.name,
      'startX': startX,
      'startY': startY,
      'endX': endX,
      'endY': endY,
      'strokeColor': strokeColor,
      'strokeWidth': strokeWidth,
      'fillColor': fillColor,
      'fillOpacity': fillOpacity,
      'lineStyle': lineStyle.name,
      'isLocked': isLocked,
      'zIndex': zIndex,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
    };
  }

  ShapeModel copyWith({
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
  }) {
    return ShapeModel(
      id: id,
      roomId: roomId,
      senderId: senderId,
      type: type,
      startX: startX ?? this.startX,
      startY: startY ?? this.startY,
      endX: endX ?? this.endX,
      endY: endY ?? this.endY,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fillColor: fillColor ?? this.fillColor,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      lineStyle: lineStyle ?? this.lineStyle,
      isLocked: isLocked ?? this.isLocked,
      zIndex: zIndex ?? this.zIndex,
      createdAt: createdAt,
      isDeleted: isDeleted,
    );
  }
}
