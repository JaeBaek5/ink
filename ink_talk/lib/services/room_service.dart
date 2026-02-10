import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/firestore_retry.dart';
import '../models/room_model.dart';
import '../models/user_model.dart';
import 'audit_log_service.dart';

/// 채팅방 서비스
class RoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuditLogService _auditLog = AuditLogService();

  CollectionReference<Map<String, dynamic>> get _roomsCollection =>
      _firestore.collection('rooms');

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// 내 채팅방 목록 (실시간 스트림). 나간 방(leftAt 설정)은 제외. DB에는 보관.
  Stream<List<RoomModel>> getRoomsStream(String userId) {
    return _roomsCollection
        .where('memberIds', arrayContains: userId)
        .orderBy('lastActivityAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final rooms = snapshot.docs
              .map((doc) => RoomModel.fromFirestore(doc))
              .where((room) => room.members[userId]?.leftAt == null)
              .toList();
          return rooms;
        });
  }

  /// 채팅방 단일 조회
  /// [source]: 서버에서만 조회하려면 Source.server (캐시 무시, 삭제된 방 확인용)
  Future<RoomModel?> getRoom(String roomId, {Source? source}) async {
    return retryFirestore(() async {
      final doc = await _roomsCollection.doc(roomId).get(
        source == null ? null : GetOptions(source: source),
      );
      if (!doc.exists) return null;
      return RoomModel.fromFirestore(doc);
    });
  }

  /// 채팅방 실시간 스트림
  Stream<RoomModel?> getRoomStream(String roomId) {
    return _roomsCollection.doc(roomId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return RoomModel.fromFirestore(doc);
    });
  }

  /// 1:1 채팅방만 조회 (없으면 null, 생성하지 않음)
  Future<RoomModel?> getDirectRoom(String userId, String friendId) async {
    return retryFirestore(() async {
      final existingQuery = await _roomsCollection
          .where('type', isEqualTo: RoomType.direct.name)
          .where('memberIds', arrayContains: userId)
          .get();

      for (final doc in existingQuery.docs) {
        final room = RoomModel.fromFirestore(doc);
        if (room.memberIds.contains(friendId) &&
            room.memberIds.length == 2 &&
            room.members[userId]?.leftAt == null &&
            room.members[friendId]?.leftAt == null) {
          return room;
        }
      }
      return null;
    });
  }

  /// 1:1 채팅방 생성 또는 기존 방 반환
  Future<RoomModel> createOrGetDirectRoom(String userId, String friendId) async {
    return retryFirestore(() async {
      // 기존 1:1 채팅방 확인 (둘 다 나가지 않은 방만)
      final existingQuery = await _roomsCollection
          .where('type', isEqualTo: RoomType.direct.name)
          .where('memberIds', arrayContains: userId)
          .get();

      for (final doc in existingQuery.docs) {
        final room = RoomModel.fromFirestore(doc);
        if (room.memberIds.contains(friendId) &&
            room.memberIds.length == 2 &&
            room.members[userId]?.leftAt == null &&
            room.members[friendId]?.leftAt == null) {
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
        'exportAllowed': true,
        'watermarkForced': false,
        'logPublic': true,
        'canEditShapes': true,
      };

      final docRef = await _roomsCollection.add(roomData);
      final newDoc = await docRef.get();
      _auditLog.logRoomCreated(userId, docRef.id, RoomType.direct.name);
      return RoomModel.fromFirestore(newDoc);
    });
  }

  /// 그룹 채팅방 생성
  Future<RoomModel> createGroupRoom({
    required String ownerId,
    required List<String> memberIds,
    required String name,
    String? imageUrl,
  }) async {
    return retryFirestore(() async {
      final allMemberIds = [ownerId, ...memberIds.where((id) => id != ownerId)];
      final now = DateTime.now();

      final members = <String, Map<String, dynamic>>{};
      
      members[ownerId] = {
        'userId': ownerId,
        'role': MemberRole.owner.name,
        'joinedAt': Timestamp.fromDate(now),
        'unreadCount': 0,
      };

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
        'exportAllowed': true,
        'watermarkForced': false,
        'logPublic': true,
        'canEditShapes': true,
      };

      final docRef = await _roomsCollection.add(roomData);
      final newDoc = await docRef.get();
      _auditLog.logRoomCreated(ownerId, docRef.id, RoomType.group.name);
      return RoomModel.fromFirestore(newDoc);
    });
  }

  /// 채팅방 나가기. DB에는 남기고 members[userId].leftAt 설정(관리자 확인용). 목록에서는 안 보임.
  Future<void> leaveRoom(String roomId, String userId) async {
    await retryFirestore(() async {
      final room = await getRoom(roomId);
      if (room == null) return;

      final now = DateTime.now();
      final newMembers = Map<String, dynamic>.from(
        room.members.map((k, v) => MapEntry(k, v.toMap())),
      );
      final myMember = newMembers[userId] as Map<String, dynamic>?;
      if (myMember != null) {
        myMember['leftAt'] = Timestamp.fromDate(now);
        newMembers[userId] = myMember;
      }

      if (room.type == RoomType.group) {
        if (room.members[userId]?.role == MemberRole.owner) {
          final stillIn = room.memberIds
              .where((id) => id != userId && room.members[id]?.leftAt == null)
              .toList();
          if (stillIn.isNotEmpty) {
            final newOwnerId = stillIn.first;
            newMembers[newOwnerId] = {
              ...(newMembers[newOwnerId] as Map<String, dynamic>),
              'role': MemberRole.owner.name,
            };
          }
        }
      }

      try {
        await _roomsCollection.doc(roomId).update({'members': newMembers});
        _auditLog.logRoomLeave(userId, roomId);
      } on FirebaseException catch (e) {
        if (e.code == 'not-found') return;
        rethrow;
      }
    });
  }

  /// 멤버 초대
  Future<void> inviteMembers(String roomId, List<String> newMemberIds) async {
    await retryFirestore(() async {
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
    });
  }

  /// 멤버 역할 변경
  Future<void> updateMemberRole(
    String roomId,
    String memberId,
    MemberRole newRole,
  ) async {
    await retryFirestore(() async {
      await _roomsCollection.doc(roomId).update({
        'members.$memberId.role': newRole.name,
      });
    });
  }

  /// 채팅방 정보 수정
  Future<void> updateRoom(
    String roomId, {
    String? name,
    String? imageUrl,
    bool? exportAllowed,
    bool? watermarkForced,
    bool? logPublic,
    bool? canEditShapes,
    String? canvasExpandMode,
  }) async {
    await retryFirestore(() async {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;
      if (exportAllowed != null) updates['exportAllowed'] = exportAllowed;
      if (watermarkForced != null) updates['watermarkForced'] = watermarkForced;
      if (logPublic != null) updates['logPublic'] = logPublic;
      if (canEditShapes != null) updates['canEditShapes'] = canEditShapes;
      if (canvasExpandMode != null) updates['canvasExpandMode'] = canvasExpandMode;

      if (updates.isNotEmpty) {
        await _roomsCollection.doc(roomId).update(updates);
      }
    });
  }

  /// 읽음 처리 (방이 서버에서 삭제된 경우 not-found는 무시)
  Future<void> markAsRead(String roomId, String userId) async {
    try {
      await retryFirestore(() async {
        await _roomsCollection.doc(roomId).update({
          'members.$userId.unreadCount': 0,
        });
      });
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return;
      rethrow;
    }
  }

  /// 마지막 이벤트 업데이트 (방이 서버에서 삭제된 경우 not-found는 무시)
  /// [url] 이미지/영상 썸네일 등 미리보기용 URL (선택)
  Future<void> updateLastEvent(
    String roomId, {
    required String eventType,
    String? preview,
    String? url,
  }) async {
    try {
      await retryFirestore(() async {
        final updates = <String, dynamic>{
          'lastActivityAt': FieldValue.serverTimestamp(),
          'lastEventType': eventType,
          'lastEventPreview': preview,
        };
        if (url != null) updates['lastEventUrl'] = url;
        await _roomsCollection.doc(roomId).update(updates);
      });
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return;
      rethrow;
    }
  }

  /// 멤버 사용자 정보 조회
  Future<UserModel?> getMemberUserInfo(String userId) async {
    return retryFirestore(() async {
      final doc = await _usersCollection.doc(userId).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    });
  }

}
