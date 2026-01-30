import 'package:cloud_firestore/cloud_firestore.dart';

/// 메시지 타입
enum MessageType {
  text,
  image,
  video,
  pdf,
  system, // 시스템 메시지 (입장, 퇴장 등)
}

/// 메시지 모델 (텍스트/첨부 파일)
class MessageModel {
  final String id;
  final String roomId;
  final String senderId;
  final MessageType type;
  final String? content; // 텍스트 내용
  final String? fileUrl; // 파일 URL
  final String? fileName;
  final int? fileSize;
  final String? thumbnailUrl;
  final double? positionX; // 캔버스 상 X 좌표
  final double? positionY; // 캔버스 상 Y 좌표
  final double? width;
  final double? height;
  final double opacity;
  final DateTime createdAt;
  final bool isDeleted;

  MessageModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.type,
    this.content,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.thumbnailUrl,
    this.positionX,
    this.positionY,
    this.width,
    this.height,
    this.opacity = 1.0,
    required this.createdAt,
    this.isDeleted = false,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MessageModel(
      id: doc.id,
      roomId: data['roomId'] ?? '',
      senderId: data['senderId'] ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => MessageType.text,
      ),
      content: data['content'],
      fileUrl: data['fileUrl'],
      fileName: data['fileName'],
      fileSize: data['fileSize'],
      thumbnailUrl: data['thumbnailUrl'],
      positionX: (data['positionX'] as num?)?.toDouble(),
      positionY: (data['positionY'] as num?)?.toDouble(),
      width: (data['width'] as num?)?.toDouble(),
      height: (data['height'] as num?)?.toDouble(),
      opacity: (data['opacity'] as num?)?.toDouble() ?? 1.0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'roomId': roomId,
      'senderId': senderId,
      'type': type.name,
      'content': content,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'thumbnailUrl': thumbnailUrl,
      'positionX': positionX,
      'positionY': positionY,
      'width': width,
      'height': height,
      'opacity': opacity,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
    };
  }
}
