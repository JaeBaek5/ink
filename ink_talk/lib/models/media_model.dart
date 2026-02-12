import 'dart:ui';

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
  /// 회전 각도 (도 단위, 0 = 없음, 오브젝트 중심 기준)
  final double angleDegrees;
  /// 기울이기 X (도 단위, 수평 전단)
  final double skewXDegrees;
  /// 기울이기 Y (도 단위, 수직 전단)
  final double skewYDegrees;
  /// 좌/우 180° 반전
  final bool flipHorizontal;
  /// 상/하 180° 반전
  final bool flipVertical;

  // 스타일
  final double opacity;      // 투명도 (0.0 ~ 1.0)
  final int zIndex;          // 레이어 순서
  
  // PDF 전용
  final int? totalPages;     // 총 페이지 수
  final int? currentPage;    // 현재 페이지 (클라이언트용, 저장 안 함)

  /// 이미지 자르기 영역 (정규화 0~1). null이면 전체 표시. 이미지 타입만 사용.
  final Rect? cropRect;

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
    this.angleDegrees = 0.0,
    this.skewXDegrees = 0.0,
    this.skewYDegrees = 0.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.opacity = 1.0,
    this.zIndex = 0,
    this.totalPages,
    this.currentPage,
    this.cropRect,
    required this.createdAt,
    this.isDeleted = false,
    this.isLocked = false,
  });

  factory MediaModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MediaModel.fromMap(data, id: doc.id);
  }

  /// RTDB 이벤트 payload용 (createdAt = millis)
  factory MediaModel.fromRtdbMap(Map<String, dynamic> data, {String? id}) {
    final createdAt = data['createdAt'];
    final createdAtDt = createdAt is int
        ? DateTime.fromMillisecondsSinceEpoch(createdAt)
        : (createdAt is Timestamp ? createdAt.toDate() : DateTime.now());
    return MediaModel(
      id: id ?? data['id']?.toString() ?? '',
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
      angleDegrees: (data['angle'] as num?)?.toDouble() ?? 0.0,
      skewXDegrees: (data['skewX'] as num?)?.toDouble() ?? 0.0,
      skewYDegrees: (data['skewY'] as num?)?.toDouble() ?? 0.0,
      flipHorizontal: data['flipH'] == true,
      flipVertical: data['flipV'] == true,
      opacity: (data['opacity'] as num?)?.toDouble() ?? 1.0,
      zIndex: (data['zIndex'] as num?)?.toInt() ?? 0,
      totalPages: data['totalPages'],
      cropRect: _parseCropRect(data),
      createdAt: createdAtDt,
      isDeleted: data['isDeleted'] ?? false,
      isLocked: data['isLocked'] ?? false,
    );
  }

  static MediaModel fromMap(Map<String, dynamic> data, {String? id}) {
    return MediaModel(
      id: id ?? data['id']?.toString() ?? '',
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
      angleDegrees: (data['angle'] as num?)?.toDouble() ?? 0.0,
      skewXDegrees: (data['skewX'] as num?)?.toDouble() ?? 0.0,
      skewYDegrees: (data['skewY'] as num?)?.toDouble() ?? 0.0,
      flipHorizontal: data['flipH'] == true,
      flipVertical: data['flipV'] == true,
      opacity: (data['opacity'] as num?)?.toDouble() ?? 1.0,
      zIndex: (data['zIndex'] as num?)?.toInt() ?? 0,
      totalPages: data['totalPages'],
      cropRect: _parseCropRect(data),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
      isLocked: data['isLocked'] ?? false,
    );
  }

  static Rect? _parseCropRect(Map<String, dynamic> data) {
    final l = data['cropL'] as num?;
    final t = data['cropT'] as num?;
    final r = data['cropR'] as num?;
    final b = data['cropB'] as num?;
    if (l == null || t == null || r == null || b == null) return null;
    return Rect.fromLTRB(l.toDouble(), t.toDouble(), r.toDouble(), b.toDouble());
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
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
      'angle': angleDegrees,
      'skewX': skewXDegrees,
      'skewY': skewYDegrees,
      'flipH': flipHorizontal,
      'flipV': flipVertical,
      'opacity': opacity,
      'zIndex': zIndex,
      'totalPages': totalPages,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
      'isLocked': isLocked,
    };
    if (cropRect != null) {
      map['cropL'] = cropRect!.left;
      map['cropT'] = cropRect!.top;
      map['cropR'] = cropRect!.right;
      map['cropB'] = cropRect!.bottom;
    }
    return map;
  }

  Map<String, dynamic> toRtdbPayload() {
    final m = toFirestore();
    m['id'] = id;
    m['createdAt'] = createdAt.millisecondsSinceEpoch;
    return m;
  }

  MediaModel copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? angleDegrees,
    double? skewXDegrees,
    double? skewYDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
    double? opacity,
    int? zIndex,
    int? currentPage,
    Rect? cropRect,
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
      angleDegrees: angleDegrees ?? this.angleDegrees,
      skewXDegrees: skewXDegrees ?? this.skewXDegrees,
      skewYDegrees: skewYDegrees ?? this.skewYDegrees,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      opacity: opacity ?? this.opacity,
      zIndex: zIndex ?? this.zIndex,
      totalPages: totalPages,
      currentPage: currentPage ?? this.currentPage,
      cropRect: cropRect ?? this.cropRect,
      createdAt: createdAt,
      isDeleted: isDeleted,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}
