import 'package:cloud_firestore/cloud_firestore.dart';

/// 태그 대상 타입
enum TagTargetType {
  stroke,
  image,
  video,
  text,
}

/// 태그 모델
class TagModel {
  final String id;
  final String roomId;
  final String taggerId; // 태그한 사람
  final String taggedUserId; // 태그된 사람
  final TagTargetType targetType;
  final String targetId; // 스트로크/메시지 ID
  final double? areaX; // 손글씨 영역 좌표
  final double? areaY;
  final double? areaWidth;
  final double? areaHeight;
  final DateTime createdAt;
  final bool isRead;

  TagModel({
    required this.id,
    required this.roomId,
    required this.taggerId,
    required this.taggedUserId,
    required this.targetType,
    required this.targetId,
    this.areaX,
    this.areaY,
    this.areaWidth,
    this.areaHeight,
    required this.createdAt,
    this.isRead = false,
  });

  factory TagModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TagModel(
      id: doc.id,
      roomId: data['roomId'] ?? '',
      taggerId: data['taggerId'] ?? '',
      taggedUserId: data['taggedUserId'] ?? '',
      targetType: TagTargetType.values.firstWhere(
        (e) => e.name == data['targetType'],
        orElse: () => TagTargetType.stroke,
      ),
      targetId: data['targetId'] ?? '',
      areaX: (data['areaX'] as num?)?.toDouble(),
      areaY: (data['areaY'] as num?)?.toDouble(),
      areaWidth: (data['areaWidth'] as num?)?.toDouble(),
      areaHeight: (data['areaHeight'] as num?)?.toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'roomId': roomId,
      'taggerId': taggerId,
      'taggedUserId': taggedUserId,
      'targetType': targetType.name,
      'targetId': targetId,
      'areaX': areaX,
      'areaY': areaY,
      'areaWidth': areaWidth,
      'areaHeight': areaHeight,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
    };
  }
}
