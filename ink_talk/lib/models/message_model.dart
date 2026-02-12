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
  /// 텍스트 글자 크기(포인트). null이면 16 사용.
  final double? fontSize;
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
    this.fontSize,
    this.opacity = 1.0,
    required this.createdAt,
    this.isDeleted = false,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MessageModel.fromMap(data, id: doc.id);
  }

  /// RTDB 이벤트 payload용 (createdAt = millis)
  factory MessageModel.fromRtdbMap(Map<String, dynamic> data, {String? id}) {
    final createdAt = data['createdAt'];
    final createdAtDt = createdAt is int
        ? DateTime.fromMillisecondsSinceEpoch(createdAt)
        : (createdAt is Timestamp ? createdAt.toDate() : DateTime.now());
    return MessageModel(
      id: id ?? data['id']?.toString() ?? '',
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
      fontSize: (data['fontSize'] as num?)?.toDouble(),
      opacity: (data['opacity'] as num?)?.toDouble() ?? 1.0,
      createdAt: createdAtDt,
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  static MessageModel fromMap(Map<String, dynamic> data, {String? id}) {
    return MessageModel(
      id: id ?? data['id']?.toString() ?? '',
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
      fontSize: (data['fontSize'] as num?)?.toDouble(),
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
      if (fontSize != null) 'fontSize': fontSize,
      'opacity': opacity,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
    };
  }

  Map<String, dynamic> toRtdbPayload() {
    final m = toFirestore();
    m['id'] = id;
    m['createdAt'] = createdAt.millisecondsSinceEpoch;
    return m;
  }
}
