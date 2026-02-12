import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dart:ui' show Rect;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/media_model.dart';
import 'audit_log_service.dart';

/// 미디어 서비스
class MediaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AuditLogService _auditLog = AuditLogService();
  final ImagePicker _imagePicker = ImagePicker();

  /// 미디어 컬렉션 참조
  CollectionReference<Map<String, dynamic>> _mediaCollection(String roomId) {
    return _firestore.collection('rooms').doc(roomId).collection('media');
  }

  /// 미디어 1회 로드 (캔버스 진입 시 Firestore Read 1회, 실시간은 RTDB로)
  Future<List<MediaModel>> getMedia(String roomId) async {
    final snapshot = await _mediaCollection(roomId).get();
    final media = snapshot.docs
        .map((doc) => MediaModel.fromFirestore(doc))
        .where((m) => !m.isDeleted)
        .toList();
    media.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return media;
  }

  /// 미디어 실시간 스트림 (레거시; 실시간은 RTDB 사용 권장)
  Stream<List<MediaModel>> getMediaStream(String roomId) {
    return _mediaCollection(roomId)
        .snapshots()
        .map((snapshot) {
      final media = snapshot.docs
          .map((doc) => MediaModel.fromFirestore(doc))
          .where((m) => !m.isDeleted)
          .toList();
      media.sort((a, b) => a.zIndex.compareTo(b.zIndex));
      return media;
    });
  }

  /// 이미지 선택 (갤러리)
  Future<XFile?> pickImage() async {
    return await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
  }

  /// 영상 선택 (갤러리)
  Future<XFile?> pickVideo() async {
    return await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
  }

  /// 영상 파일에서 썸네일 이미지 바이트 생성 (영상 확인용). 실패 시 null.
  static Future<Uint8List?> getVideoThumbnailBytes(
    String videoFilePath, {
    int timeMs = 500,
    int maxWidth = 512,
    int quality = 85,
  }) async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoFilePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxWidth,
        quality: quality,
        timeMs: timeMs,
      );
      return bytes;
    } catch (e) {
      debugPrint('영상 썸네일 생성 실패: $e');
      return null;
    }
  }

  /// PDF 선택
  Future<PlatformFile?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    return result?.files.firstOrNull;
  }

  /// 파일 업로드 (Firebase Storage) — 경로로 업로드
  Future<String> uploadFile({
    required String roomId,
    required String filePath,
    required String fileName,
    required MediaType type,
  }) async {
    try {
      final safeName = fileName.isNotEmpty ? fileName : 'image.jpg';
      final ref = _storage.ref().child('rooms/$roomId/media/${DateTime.now().millisecondsSinceEpoch}_$safeName');
      final uploadTask = ref.putFile(File(filePath));

      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('파일 업로드 실패: $e');
      rethrow;
    }
  }

  /// 이미지 바이트에서 너비·높이만 조회 (디코딩 없이)
  static Future<({int width, int height})> getImageDimensions(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return (width: descriptor.width, height: descriptor.height);
    } finally {
      descriptor.dispose();
    }
  }

  /// 이미지 파일 업로드 (XFile — path가 null이어도 바이트로 업로드)
  Future<String> uploadImageFile({
    required String roomId,
    required XFile imageFile,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final name = imageFile.name.isNotEmpty ? imageFile.name : 'image.jpg';
      return uploadImageBytes(roomId: roomId, bytes: bytes, fileName: name);
    } catch (e) {
      debugPrint('이미지 업로드 실패: $e');
      rethrow;
    }
  }

  /// 이미지 바이트 업로드 (한 번 읽은 바이트로 업로드·크기 조회 시 중복 읽기 방지)
  Future<String> uploadImageBytes({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final name = fileName.isNotEmpty ? fileName : 'image.jpg';
      final ref = _storage.ref().child('rooms/$roomId/media/${DateTime.now().millisecondsSinceEpoch}_$name');
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('이미지 업로드 실패: $e');
      rethrow;
    }
  }

  /// 미디어 저장 (Firestore)
  Future<String> saveMedia(MediaModel media) async {
    try {
      final docRef = await _mediaCollection(media.roomId).add(media.toFirestore());
      _auditLog.logMediaCreated(media.senderId, media.roomId, docRef.id);
      return docRef.id;
    } catch (e) {
      debugPrint('미디어 저장 실패: $e');
      rethrow;
    }
  }

  /// 미디어 업데이트
  Future<void> updateMedia(String roomId, String mediaId, {
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
    bool? isLocked,
    Rect? cropRect,
    bool clearCrop = false,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (x != null) updates['x'] = x;
      if (y != null) updates['y'] = y;
      if (width != null) updates['width'] = width;
      if (height != null) updates['height'] = height;
      if (angleDegrees != null) updates['angle'] = angleDegrees;
      if (skewXDegrees != null) updates['skewX'] = skewXDegrees;
      if (skewYDegrees != null) updates['skewY'] = skewYDegrees;
      if (flipHorizontal != null) updates['flipH'] = flipHorizontal;
      if (flipVertical != null) updates['flipV'] = flipVertical;
      if (opacity != null) updates['opacity'] = opacity;
      if (zIndex != null) updates['zIndex'] = zIndex;
      if (isLocked != null) updates['isLocked'] = isLocked;
      if (cropRect != null) {
        updates['cropL'] = cropRect.left;
        updates['cropT'] = cropRect.top;
        updates['cropR'] = cropRect.right;
        updates['cropB'] = cropRect.bottom;
      } else if (clearCrop) {
        updates['cropL'] = null;
        updates['cropT'] = null;
        updates['cropR'] = null;
        updates['cropB'] = null;
      }
      if (updates.isNotEmpty) {
        await _mediaCollection(roomId).doc(mediaId).update(updates);
      }
    } catch (e) {
      debugPrint('미디어 업데이트 실패: $e');
    }
  }

  /// 미디어 삭제 (소프트 삭제). deletedAt, deletedBy 기록 → 운영자 복구 가능.
  Future<void> deleteMedia(String roomId, String mediaId, {String? userId}) async {
    try {
      final updates = <String, dynamic>{'isDeleted': true};
      if (userId != null) {
        updates['deletedAt'] = FieldValue.serverTimestamp();
        updates['deletedBy'] = userId;
      }
      await _mediaCollection(roomId).doc(mediaId).update(updates);
      if (userId != null) _auditLog.logMediaDeleted(userId, roomId, mediaId);
    } catch (e) {
      debugPrint('미디어 삭제 실패: $e');
    }
  }

  /// 미디어 복구 (Undo/Redo용)
  Future<void> restoreMedia(String roomId, String mediaId) async {
    try {
      await _mediaCollection(roomId).doc(mediaId).update({
        'isDeleted': false,
      });
    } catch (e) {
      debugPrint('미디어 복구 실패: $e');
    }
  }

  /// 레이어 앞으로
  Future<void> bringToFront(String roomId, String mediaId, int maxZIndex) async {
    await updateMedia(roomId, mediaId, zIndex: maxZIndex + 1);
  }

  /// 레이어 뒤로
  Future<void> sendToBack(String roomId, String mediaId) async {
    await updateMedia(roomId, mediaId, zIndex: -1);
  }
}
