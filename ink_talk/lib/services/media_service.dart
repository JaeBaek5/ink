import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/media_model.dart';

/// 미디어 서비스
class MediaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();

  /// 미디어 컬렉션 참조
  CollectionReference<Map<String, dynamic>> _mediaCollection(String roomId) {
    return _firestore.collection('rooms').doc(roomId).collection('media');
  }

  /// 미디어 실시간 스트림
  Stream<List<MediaModel>> getMediaStream(String roomId) {
    return _mediaCollection(roomId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('zIndex', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => MediaModel.fromFirestore(doc)).toList();
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

  /// PDF 선택
  Future<PlatformFile?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    return result?.files.firstOrNull;
  }

  /// 파일 업로드 (Firebase Storage)
  Future<String> uploadFile({
    required String roomId,
    required String filePath,
    required String fileName,
    required MediaType type,
  }) async {
    try {
      final ref = _storage.ref().child('rooms/$roomId/media/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final uploadTask = ref.putFile(File(filePath));
      
      // 업로드 진행률 (선택적 로깅)
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        debugPrint('업로드 진행률: ${(progress * 100).toStringAsFixed(1)}%');
      });

      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('파일 업로드 실패: $e');
      rethrow;
    }
  }

  /// 미디어 저장 (Firestore)
  Future<String> saveMedia(MediaModel media) async {
    try {
      final docRef = await _mediaCollection(media.roomId).add(media.toFirestore());
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
    double? opacity,
    int? zIndex,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (x != null) updates['x'] = x;
      if (y != null) updates['y'] = y;
      if (width != null) updates['width'] = width;
      if (height != null) updates['height'] = height;
      if (opacity != null) updates['opacity'] = opacity;
      if (zIndex != null) updates['zIndex'] = zIndex;

      if (updates.isNotEmpty) {
        await _mediaCollection(roomId).doc(mediaId).update(updates);
      }
    } catch (e) {
      debugPrint('미디어 업데이트 실패: $e');
    }
  }

  /// 미디어 삭제 (소프트 삭제)
  Future<void> deleteMedia(String roomId, String mediaId) async {
    try {
      await _mediaCollection(roomId).doc(mediaId).update({
        'isDeleted': true,
      });
    } catch (e) {
      debugPrint('미디어 삭제 실패: $e');
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
