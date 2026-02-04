import 'package:cloud_firestore/cloud_firestore.dart';

/// 미디어 타입
enum MediaType {
  image,  // 사진 (PNG/JPG)
  video,  // 영상
  pdf,    // PDF 문서
}

/// 미디어 모델 (캔버스에 첨부된 파일)
class MediaModel {
  final String id;
  final String roomId;
  final String senderId;
  final MediaType type;
  
  // 파일 정보
  final String url;          // Firebase Storage URL
  final String fileName;     // 원본 파일명
  final int fileSize;        // 바이트 단위
  final String? thumbnailUrl; // 썸네일 URL (영상/PDF)
  
  // 위치 및 크기
  final double x;
  final double y;
  final double width;
  final double height;
  
  // 스타일
  final double opacity;      // 투명도 (0.0 ~ 1.0)
  final int zIndex;          // 레이어 순서
  
  // PDF 전용
  final int? totalPages;     // 총 페이지 수
  final int? currentPage;    // 현재 페이지 (클라이언트용, 저장 안 함)
  
  // 메타
  final DateTime createdAt;
  final bool isDeleted;
  final bool isLocked; // 잠금 시 이동·크기 조정 불가

  MediaModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.type,
    required this.url,
    required this.fileName,
    this.fileSize = 0,
    this.thumbnailUrl,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.opacity = 1.0,
    this.zIndex = 0,
    this.totalPages,
    this.currentPage,
    required this.createdAt,
    this.isDeleted = false,
    this.isLocked = false,
  });

  factory MediaModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MediaModel(
      id: doc.id,
      roomId: data['roomId'] ?? '',
      senderId: data['senderId'] ?? '',
      type: MediaType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => MediaType.image,
      ),
      url: data['url'] ?? '',
      fileName: data['fileName'] ?? '',
      fileSize: data['fileSize'] ?? 0,
      thumbnailUrl: data['thumbnailUrl'],
      x: (data['x'] as num?)?.toDouble() ?? 0,
      y: (data['y'] as num?)?.toDouble() ?? 0,
      width: (data['width'] as num?)?.toDouble() ?? 200,
      height: (data['height'] as num?)?.toDouble() ?? 200,
      opacity: (data['opacity'] as num?)?.toDouble() ?? 1.0,
      zIndex: data['zIndex'] ?? 0,
      totalPages: data['totalPages'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
      isLocked: data['isLocked'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'roomId': roomId,
      'senderId': senderId,
      'type': type.name,
      'url': url,
      'fileName': fileName,
      'fileSize': fileSize,
      'thumbnailUrl': thumbnailUrl,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'opacity': opacity,
      'zIndex': zIndex,
      'totalPages': totalPages,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
      'isLocked': isLocked,
    };
  }

  MediaModel copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? opacity,
    int? zIndex,
    int? currentPage,
    bool? isLocked,
  }) {
    return MediaModel(
      id: id,
      roomId: roomId,
      senderId: senderId,
      type: type,
      url: url,
      fileName: fileName,
      fileSize: fileSize,
      thumbnailUrl: thumbnailUrl,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      opacity: opacity ?? this.opacity,
      zIndex: zIndex ?? this.zIndex,
      totalPages: totalPages,
      currentPage: currentPage ?? this.currentPage,
      createdAt: createdAt,
      isDeleted: isDeleted,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}
