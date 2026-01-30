import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/tag_model.dart';

/// 태그 서비스
class TagService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 태그 컬렉션 참조 (전역)
  CollectionReference<Map<String, dynamic>> get _tagsCollection =>
      _firestore.collection('tags');

  /// 내가 태그된 모든 태그 스트림
  Stream<List<TagModel>> getMyTagsStream(String userId) {
    return _tagsCollection
        .where('taggedUserId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final tags = snapshot.docs.map((doc) => TagModel.fromFirestore(doc)).toList();
      // 최신순 정렬
      tags.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tags;
    });
  }

  /// 특정 방의 태그 스트림
  Stream<List<TagModel>> getRoomTagsStream(String roomId, String userId) {
    return _tagsCollection
        .where('roomId', isEqualTo: roomId)
        .where('taggedUserId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final tags = snapshot.docs.map((doc) => TagModel.fromFirestore(doc)).toList();
      tags.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tags;
    });
  }

  /// 태그 생성
  Future<String> createTag(TagModel tag) async {
    try {
      final docRef = await _tagsCollection.add(tag.toFirestore());
      return docRef.id;
    } catch (e) {
      debugPrint('태그 생성 실패: $e');
      rethrow;
    }
  }

  /// 태그 읽음 처리
  Future<void> markAsRead(String tagId) async {
    try {
      await _tagsCollection.doc(tagId).update({'isRead': true});
    } catch (e) {
      debugPrint('태그 읽음 처리 실패: $e');
    }
  }

  /// 태그 삭제
  Future<void> deleteTag(String tagId) async {
    try {
      await _tagsCollection.doc(tagId).delete();
    } catch (e) {
      debugPrint('태그 삭제 실패: $e');
    }
  }

  /// 필터된 태그 가져오기
  Future<List<TagModel>> getFilteredTags({
    required String userId,
    TagTargetType? targetType,
    String? roomId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _tagsCollection
          .where('taggedUserId', isEqualTo: userId);

      if (roomId != null) {
        query = query.where('roomId', isEqualTo: roomId);
      }

      if (targetType != null) {
        query = query.where('targetType', isEqualTo: targetType.name);
      }

      final snapshot = await query.get();
      var tags = snapshot.docs.map((doc) => TagModel.fromFirestore(doc)).toList();

      // 날짜 필터 (클라이언트)
      if (startDate != null) {
        tags = tags.where((t) => t.createdAt.isAfter(startDate)).toList();
      }
      if (endDate != null) {
        tags = tags.where((t) => t.createdAt.isBefore(endDate)).toList();
      }

      // 최신순 정렬
      tags.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tags;
    } catch (e) {
      debugPrint('필터된 태그 가져오기 실패: $e');
      return [];
    }
  }
}
