import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/firestore_retry.dart';
import '../models/friend_model.dart';
import '../models/user_model.dart';
import 'audit_log_service.dart';

/// 친구 서비스
class FriendService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuditLogService _auditLog = AuditLogService();

  /// 컬렉션 참조
  CollectionReference<Map<String, dynamic>> get _friendsCollection =>
      _firestore.collection('friends');

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// 친구 목록 조회 (실시간 스트림). hidden된 항목은 제외(DB에는 보관).
  /// hidden 필드를 쿼리에 넣지 않고 메모리에서 필터링 (과거 문서에 hidden이 없을 수 있음)
  Stream<List<FriendModel>> getFriendsStream(String userId) {
    return _friendsCollection
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: FriendStatus.accepted.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .where((doc) => doc.data()['hidden'] != true)
            .map((doc) => FriendModel.fromFirestore(doc))
            .toList());
  }

  /// 받은 친구 요청 조회 (나에게 온 요청, status == pending)
  Stream<List<FriendModel>> getPendingRequestsStream(String userId) {
    return _friendsCollection
        .where('friendId', isEqualTo: userId)
        .where('status', isEqualTo: FriendStatus.pending.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => FriendModel.fromFirestore(doc)).toList());
  }

  /// 보낸 친구 요청 조회 (내가 보낸 요청, 대기중/거절됨. 승인된 건 친구 목록에 표시)
  Stream<List<FriendModel>> getSentRequestsStream(String userId) {
    return _friendsCollection
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: [FriendStatus.pending.name, FriendStatus.rejected.name])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => FriendModel.fromFirestore(doc)).toList());
  }

  /// 친구 추가 (ID로)
  Future<void> addFriendById(String userId, String friendVisibleId) async {
    await retryFirestore(() async {
      final friendQuery = await _usersCollection
          .where('visibleId', isEqualTo: friendVisibleId)
          .limit(1)
          .get();

      if (friendQuery.docs.isEmpty) {
        throw Exception('존재하지 않는 사용자입니다.');
      }

      final friendUser = UserModel.fromFirestore(friendQuery.docs.first);

      if (friendUser.uid == userId) {
        throw Exception('자기 자신은 친구로 추가할 수 없습니다.');
      }

      final myToFriend = await _friendsCollection
          .where('userId', isEqualTo: userId)
          .where('friendId', isEqualTo: friendUser.uid)
          .get();
      for (var doc in myToFriend.docs) {
        final d = doc.data();
        if (d['hidden'] == true) continue;
        final status = d['status'];
        if (status == FriendStatus.accepted.name) {
          throw Exception('이미 친구입니다.');
        } else if (status == FriendStatus.pending.name) {
          throw Exception('이미 친구 요청을 보냈습니다.');
        } else if (status == FriendStatus.blocked.name) {
          throw Exception('차단된 사용자입니다.');
        } else if (status == FriendStatus.rejected.name) {
          // 거절됐던 요청 → 대기중으로 다시 보내기 (문서 재사용)
          final now = DateTime.now();
          await doc.reference.update({
            'status': FriendStatus.pending.name,
            'createdAt': Timestamp.fromDate(now),
            'acceptedAt': null,
          });
          _auditLog.logFriendRequestSent(userId, doc.id, friendUser.uid);
          return;
        }
      }

      final friendToMe = await _friendsCollection
          .where('userId', isEqualTo: friendUser.uid)
          .where('friendId', isEqualTo: userId)
          .get();
      for (var doc in friendToMe.docs) {
        final d = doc.data();
        if (d['hidden'] == true) continue;
        final status = d['status'];
        if (status == FriendStatus.accepted.name) {
          throw Exception('이미 친구입니다.');
        } else if (status == FriendStatus.pending.name) {
          throw Exception('이 사용자가 이미 친구 요청을 보냈습니다. 받은 요청에서 수락해 주세요.');
        }
      }

      final now = DateTime.now();
      final docRef = await _friendsCollection.add({
        'userId': userId,
        'friendId': friendUser.uid,
        'status': FriendStatus.pending.name,
        'nickname': null,
        'createdAt': Timestamp.fromDate(now),
        'acceptedAt': null,
      });
      _auditLog.logFriendRequestSent(userId, docRef.id, friendUser.uid);
    });
  }

  /// 친구 요청 수락
  Future<void> acceptFriendRequest(String receiverId, String requestId) async {
    await retryFirestore(() async {
      final docRef = _friendsCollection.doc(requestId);
      final doc = await docRef.get();
      if (!doc.exists) {
        throw Exception('해당 친구 요청을 찾을 수 없습니다.');
      }
      final data = doc.data()!;
      final requesterId = data['userId'] as String;
      final friendId = data['friendId'] as String;
      if (friendId != receiverId) {
        throw Exception('본인의 요청만 수락할 수 있습니다.');
      }

      final now = DateTime.now();
      final batch = _firestore.batch();

      batch.update(docRef, {
        'status': FriendStatus.accepted.name,
        'acceptedAt': Timestamp.fromDate(now),
        'hidden': false,
      });

      // 수락한 사람 쪽 친구 목록용 문서 (userId=수락자, friendId=요청자). hidden 필드 명시해 쿼리/인덱스 일치.
      final reverseDocRef = _friendsCollection.doc();
      batch.set(reverseDocRef, {
        'userId': receiverId,
        'friendId': requesterId,
        'status': FriendStatus.accepted.name,
        'nickname': null,
        'createdAt': Timestamp.fromDate(now),
        'acceptedAt': Timestamp.fromDate(now),
        'hidden': false,
      });

      await batch.commit();
      _auditLog.logFriendRequestAccepted(receiverId, requestId);
    });
  }

  /// 친구 요청 거절 (문서는 유지, status=rejected로 변경해 보낸 사람이 거절 여부 확인 가능)
  Future<void> rejectFriendRequest(String receiverId, String requestId) async {
    await retryFirestore(() async {
      final docRef = _friendsCollection.doc(requestId);
      final doc = await docRef.get();
      if (!doc.exists) return;
      final data = doc.data()!;
      if (data['friendId'] != receiverId) return;
      _auditLog.logFriendRequestRejected(receiverId, requestId);
      await docRef.update({'status': FriendStatus.rejected.name});
    });
  }

  /// 친구 추가 (전화번호로)
  Future<void> addFriendByPhone(String userId, String phoneNumber) async {
    // 전화번호 정규화
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);

    // 전화번호로 사용자 조회
    final friendQuery = await _usersCollection
        .where('phoneNumber', isEqualTo: normalizedPhone)
        .limit(1)
        .get();

    if (friendQuery.docs.isEmpty) {
      throw Exception('해당 전화번호로 가입한 사용자가 없습니다.');
    }

    final friendUser = UserModel.fromFirestore(friendQuery.docs.first);

    // ID로 추가하는 것과 동일한 로직 사용
    await addFriendById(userId, friendUser.visibleId);
  }

  /// 친구 삭제. DB에는 남기고 hidden 처리(deleted/deletedAt/deletedBy). 목록에서는 안 보임.
  Future<void> removeFriend(String userId, String friendId) async {
    await retryFirestore(() async {
      final now = DateTime.now();
      final batch = _firestore.batch();

      final myFriendQuery = await _friendsCollection
          .where('userId', isEqualTo: userId)
          .where('friendId', isEqualTo: friendId)
          .get();
      String? firstDocId;
      for (var doc in myFriendQuery.docs) {
        firstDocId ??= doc.id;
        batch.update(doc.reference, {
          'hidden': true,
          'hiddenAt': Timestamp.fromDate(now),
          'hiddenBy': userId,
        });
      }

      final friendQuery = await _friendsCollection
          .where('userId', isEqualTo: friendId)
          .where('friendId', isEqualTo: userId)
          .get();
      for (var doc in friendQuery.docs) {
        batch.update(doc.reference, {
          'hidden': true,
          'hiddenAt': Timestamp.fromDate(now),
          'hiddenBy': userId,
        });
      }

      await batch.commit();
      if (firstDocId != null) {
        _auditLog.logFriendHidden(userId, firstDocId, friendId);
      }
    });
  }

  /// 친구 차단 (내 문서만 status=blocked로 변경. 상대 문서는 건드리지 않음 - 차단된 사용자는 차단 여부를 알 수 없음)
  Future<void> blockFriend(String userId, String friendId) async {
    await retryFirestore(() async {
      final myFriendQuery = await _friendsCollection
          .where('userId', isEqualTo: userId)
          .where('friendId', isEqualTo: friendId)
          .get();

      final now = DateTime.now();
      if (myFriendQuery.docs.isNotEmpty) {
        await myFriendQuery.docs.first.reference.update({
          'status': FriendStatus.blocked.name,
          'blockedAt': Timestamp.fromDate(now),
        });
      } else {
        await _friendsCollection.add({
          'userId': userId,
          'friendId': friendId,
          'status': FriendStatus.blocked.name,
          'nickname': null,
          'createdAt': Timestamp.fromDate(now),
          'acceptedAt': null,
          'blockedAt': Timestamp.fromDate(now),
        });
      }
    });
  }

  /// 차단 해제 (status를 accepted로 복구. 친구 목록으로 다시 이동)
  Future<void> unblockFriend(String userId, String friendId) async {
    await retryFirestore(() async {
      final myFriendQuery = await _friendsCollection
          .where('userId', isEqualTo: userId)
          .where('friendId', isEqualTo: friendId)
          .where('status', isEqualTo: FriendStatus.blocked.name)
          .get();

      for (var doc in myFriendQuery.docs) {
        await doc.reference.update({
          'status': FriendStatus.accepted.name,
          'acceptedAt': Timestamp.fromDate(DateTime.now()),
          'hidden': false,
        });
      }
    });
  }

  /// 차단 목록 조회
  Stream<List<FriendModel>> getBlockedUsersStream(String userId) {
    return _friendsCollection
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: FriendStatus.blocked.name)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => FriendModel.fromFirestore(doc)).toList());
  }

  /// 친구 별명 설정 (수락된 친구 문서만 업데이트)
  Future<void> updateFriendNickname(String userId, String friendId, String? nickname) async {
    await retryFirestore(() async {
      final query = await _friendsCollection
          .where('userId', isEqualTo: userId)
          .where('friendId', isEqualTo: friendId)
          .where('status', isEqualTo: FriendStatus.accepted.name)
          .get();
      if (query.docs.isEmpty) {
        throw Exception('친구 관계를 찾을 수 없습니다.');
      }
      final updates = <String, dynamic>{
        'nickname': nickname == null || nickname.isEmpty
            ? FieldValue.delete()
            : nickname,
      };
      await query.docs.first.reference.update(updates);
    });
  }

  /// 친구 정보 조회 (UserModel)
  Future<UserModel?> getFriendUserInfo(String friendId) async {
    final doc = await _usersCollection.doc(friendId).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  /// 전화번호 정규화
  String _normalizePhoneNumber(String phone) {
    // 숫자만 추출
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // 한국 번호 처리
    if (digits.startsWith('82')) {
      return '+$digits';
    } else if (digits.startsWith('010')) {
      return '+82${digits.substring(1)}';
    }
    return '+$digits';
  }
}
