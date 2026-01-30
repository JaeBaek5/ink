import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/room_model.dart';
import '../models/user_model.dart';

/// 채팅방 서비스
class RoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _roomsCollection =>
      _firestore.collection('rooms');

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// 내 채팅방 목록 (실시간 스트림)
  Stream<List<RoomModel>> getRoomsStream(String userId) {
    return _roomsCollection
        .where('memberIds', arrayContains: userId)
        .orderBy('lastActivityAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => RoomModel.fromFirestore(doc)).toList());
  }

  /// 채팅방 단일 조회
  Future<RoomModel?> getRoom(String roomId) async {
    final doc = await _roomsCollection.doc(roomId).get();
    if (!doc.exists) return null;
    return RoomModel.fromFirestore(doc);
  }

  /// 채팅방 실시간 스트림
  Stream<RoomModel?> getRoomStream(String roomId) {
    return _roomsCollection.doc(roomId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return RoomModel.fromFirestore(doc);
    });
  }

  /// 1:1 채팅방 생성 또는 기존 방 반환
  Future<RoomModel> createOrGetDirectRoom(String userId, String friendId) async {
    // 기존 1:1 채팅방 확인
    final existingQuery = await _roomsCollection
        .where('type', isEqualTo: RoomType.direct.name)
        .where('memberIds', arrayContains: userId)
        .get();

    for (final doc in existingQuery.docs) {
      final room = RoomModel.fromFirestore(doc);
      if (room.memberIds.contains(friendId) && room.memberIds.length == 2) {
        return room;
      }
    }

    // 새 1:1 채팅방 생성
    final now = DateTime.now();
    final roomData = {
      'type': RoomType.direct.name,
      'name': null,
      'imageUrl': null,
      'memberIds': [userId, friendId],
      'members': {
        userId: {
          'userId': userId,
          'role': MemberRole.owner.name,
          'joinedAt': Timestamp.fromDate(now),
          'unreadCount': 0,
        },
        friendId: {
          'userId': friendId,
          'role': MemberRole.owner.name,
          'joinedAt': Timestamp.fromDate(now),
          'unreadCount': 0,
        },
      },
      'createdAt': Timestamp.fromDate(now),
      'lastActivityAt': Timestamp.fromDate(now),
      'lastEventType': null,
      'lastEventPreview': null,
    };

    final docRef = await _roomsCollection.add(roomData);
    final newDoc = await docRef.get();
    return RoomModel.fromFirestore(newDoc);
  }

  /// 그룹 채팅방 생성
  Future<RoomModel> createGroupRoom({
    required String ownerId,
    required List<String> memberIds,
    required String name,
    String? imageUrl,
  }) async {
    final allMemberIds = [ownerId, ...memberIds.where((id) => id != ownerId)];
    final now = DateTime.now();

    final members = <String, Map<String, dynamic>>{};
    
    // Owner 추가
    members[ownerId] = {
      'userId': ownerId,
      'role': MemberRole.owner.name,
      'joinedAt': Timestamp.fromDate(now),
      'unreadCount': 0,
    };

    // 다른 멤버 추가
    for (final memberId in memberIds) {
      if (memberId != ownerId) {
        members[memberId] = {
          'userId': memberId,
          'role': MemberRole.member.name,
          'joinedAt': Timestamp.fromDate(now),
          'unreadCount': 0,
        };
      }
    }

    final roomData = {
      'type': RoomType.group.name,
      'name': name,
      'imageUrl': imageUrl,
      'memberIds': allMemberIds,
      'members': members,
      'createdAt': Timestamp.fromDate(now),
      'lastActivityAt': Timestamp.fromDate(now),
      'lastEventType': 'system',
      'lastEventPreview': '채팅방이 생성되었습니다.',
    };

    final docRef = await _roomsCollection.add(roomData);
    final newDoc = await docRef.get();
    return RoomModel.fromFirestore(newDoc);
  }

  /// 채팅방 나가기
  Future<void> leaveRoom(String roomId, String userId) async {
    final room = await getRoom(roomId);
    if (room == null) return;

    if (room.type == RoomType.direct) {
      // 1:1 채팅방은 삭제
      await _roomsCollection.doc(roomId).delete();
    } else {
      // 그룹 채팅방은 멤버에서 제거
      final newMemberIds = room.memberIds.where((id) => id != userId).toList();

      if (newMemberIds.isEmpty) {
        // 멤버가 없으면 삭제
        await _roomsCollection.doc(roomId).delete();
      } else {
        // Owner가 나가면 다음 멤버가 Owner
        final newMembers = Map<String, dynamic>.from(
          room.members.map((k, v) => MapEntry(k, v.toMap())),
        );
        newMembers.remove(userId);

        // Owner 위임
        if (room.members[userId]?.role == MemberRole.owner && newMemberIds.isNotEmpty) {
          final newOwnerId = newMemberIds.first;
          newMembers[newOwnerId] = {
            ...newMembers[newOwnerId] as Map<String, dynamic>,
            'role': MemberRole.owner.name,
          };
        }

        await _roomsCollection.doc(roomId).update({
          'memberIds': newMemberIds,
          'members': newMembers,
        });
      }
    }
  }

  /// 멤버 초대
  Future<void> inviteMembers(String roomId, List<String> newMemberIds) async {
    final room = await getRoom(roomId);
    if (room == null || room.type != RoomType.group) return;

    final now = DateTime.now();
    final updatedMemberIds = [...room.memberIds];
    final updatedMembers = Map<String, dynamic>.from(
      room.members.map((k, v) => MapEntry(k, v.toMap())),
    );

    for (final memberId in newMemberIds) {
      if (!updatedMemberIds.contains(memberId)) {
        updatedMemberIds.add(memberId);
        updatedMembers[memberId] = {
          'userId': memberId,
          'role': MemberRole.member.name,
          'joinedAt': Timestamp.fromDate(now),
          'unreadCount': 0,
        };
      }
    }

    await _roomsCollection.doc(roomId).update({
      'memberIds': updatedMemberIds,
      'members': updatedMembers,
    });
  }

  /// 멤버 역할 변경
  Future<void> updateMemberRole(
    String roomId,
    String memberId,
    MemberRole newRole,
  ) async {
    await _roomsCollection.doc(roomId).update({
      'members.$memberId.role': newRole.name,
    });
  }

  /// 채팅방 정보 수정
  Future<void> updateRoom(
    String roomId, {
    String? name,
    String? imageUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (imageUrl != null) updates['imageUrl'] = imageUrl;

    if (updates.isNotEmpty) {
      await _roomsCollection.doc(roomId).update(updates);
    }
  }

  /// 읽음 처리
  Future<void> markAsRead(String roomId, String userId) async {
    await _roomsCollection.doc(roomId).update({
      'members.$userId.unreadCount': 0,
    });
  }

  /// 마지막 이벤트 업데이트
  Future<void> updateLastEvent(
    String roomId, {
    required String eventType,
    String? preview,
  }) async {
    await _roomsCollection.doc(roomId).update({
      'lastActivityAt': FieldValue.serverTimestamp(),
      'lastEventType': eventType,
      'lastEventPreview': preview,
    });
  }

  /// 멤버 사용자 정보 조회
  Future<UserModel?> getMemberUserInfo(String userId) async {
    final doc = await _usersCollection.doc(userId).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  /// 테스트용 채팅방 생성
  Future<RoomModel> createTestRoom(String userId) async {
    // 기존 테스트 채팅방 확인 (단순 쿼리 - 인덱스 불필요)
    try {
      final existingQuery = await _roomsCollection
          .where('memberIds', arrayContains: userId)
          .get();

      // 클라이언트에서 이름 필터링
      for (final doc in existingQuery.docs) {
        final data = doc.data();
        if (data['name'] == '테스트용 채팅방') {
          return RoomModel.fromFirestore(doc);
        }
      }
    } catch (e) {
      // 쿼리 실패 시 무시하고 새로 생성
      debugPrint('기존 테스트방 조회 실패: $e');
    }

    // 새 테스트 채팅방 생성
    final now = DateTime.now();
    final roomData = {
      'type': RoomType.group.name,
      'name': '테스트용 채팅방',
      'imageUrl': null,
      'memberIds': [userId],
      'members': {
        userId: {
          'userId': userId,
          'role': MemberRole.owner.name,
          'joinedAt': Timestamp.fromDate(now),
          'unreadCount': 0,
        },
      },
      'createdAt': Timestamp.fromDate(now),
      'lastActivityAt': Timestamp.fromDate(now),
      'lastEventType': 'system',
      'lastEventPreview': '캔버스 테스트를 시작해보세요!',
    };

    final docRef = await _roomsCollection.add(roomData);
    final newDoc = await docRef.get();
    return RoomModel.fromFirestore(newDoc);
  }
}
