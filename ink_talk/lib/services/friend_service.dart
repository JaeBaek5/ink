import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/friend_model.dart';
import '../models/user_model.dart';

/// 친구 서비스
class FriendService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 컬렉션 참조
  CollectionReference<Map<String, dynamic>> get _friendsCollection =>
      _firestore.collection('friends');

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// 친구 목록 조회 (실시간 스트림)
  Stream<List<FriendModel>> getFriendsStream(String userId) {
    return _friendsCollection
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: FriendStatus.accepted.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => FriendModel.fromFirestore(doc)).toList());
  }

  /// 받은 친구 요청 조회
  Stream<List<FriendModel>> getPendingRequestsStream(String userId) {
    return _friendsCollection
        .where('friendId', isEqualTo: userId)
        .where('status', isEqualTo: FriendStatus.pending.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => FriendModel.fromFirestore(doc)).toList());
  }

  /// 친구 추가 (ID로)
  Future<void> addFriendById(String userId, String friendVisibleId) async {
    // 1. 친구 ID로 사용자 조회
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

    // 2. 이미 친구인지 확인
    final existingFriend = await _friendsCollection
        .where('userId', isEqualTo: userId)
        .where('friendId', isEqualTo: friendUser.uid)
        .get();

    if (existingFriend.docs.isNotEmpty) {
      final status = existingFriend.docs.first.data()['status'];
      if (status == FriendStatus.accepted.name) {
        throw Exception('이미 친구입니다.');
      } else if (status == FriendStatus.pending.name) {
        throw Exception('이미 친구 요청을 보냈습니다.');
      } else if (status == FriendStatus.blocked.name) {
        throw Exception('차단된 사용자입니다.');
      }
    }

    // 3. 친구 관계 생성 (양방향)
    final batch = _firestore.batch();
    final now = DateTime.now();

    // 내가 보낸 친구 요청
    final myFriendDoc = _friendsCollection.doc();
    batch.set(myFriendDoc, {
      'userId': userId,
      'friendId': friendUser.uid,
      'status': FriendStatus.accepted.name, // 바로 수락 (카카오톡 스타일)
      'nickname': null,
      'createdAt': Timestamp.fromDate(now),
      'acceptedAt': Timestamp.fromDate(now),
    });

    // 상대방에게도 친구 추가
    final friendDoc = _friendsCollection.doc();
    batch.set(friendDoc, {
      'userId': friendUser.uid,
      'friendId': userId,
      'status': FriendStatus.accepted.name,
      'nickname': null,
      'createdAt': Timestamp.fromDate(now),
      'acceptedAt': Timestamp.fromDate(now),
    });

    await batch.commit();
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

  /// 친구 삭제
  Future<void> removeFriend(String userId, String friendId) async {
    final batch = _firestore.batch();

    // 내 친구 목록에서 삭제
    final myFriendQuery = await _friendsCollection
        .where('userId', isEqualTo: userId)
        .where('friendId', isEqualTo: friendId)
        .get();

    for (var doc in myFriendQuery.docs) {
      batch.delete(doc.reference);
    }

    // 상대방 친구 목록에서도 삭제
    final friendQuery = await _friendsCollection
        .where('userId', isEqualTo: friendId)
        .where('friendId', isEqualTo: userId)
        .get();

    for (var doc in friendQuery.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  /// 친구 차단
  Future<void> blockFriend(String userId, String friendId) async {
    // 내 친구 관계 업데이트
    final myFriendQuery = await _friendsCollection
        .where('userId', isEqualTo: userId)
        .where('friendId', isEqualTo: friendId)
        .get();

    if (myFriendQuery.docs.isNotEmpty) {
      await myFriendQuery.docs.first.reference.update({
        'status': FriendStatus.blocked.name,
      });
    } else {
      // 차단 관계 새로 생성
      await _friendsCollection.add({
        'userId': userId,
        'friendId': friendId,
        'status': FriendStatus.blocked.name,
        'nickname': null,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'acceptedAt': null,
      });
    }

    // 상대방 친구 목록에서 삭제
    final friendQuery = await _friendsCollection
        .where('userId', isEqualTo: friendId)
        .where('friendId', isEqualTo: userId)
        .get();

    for (var doc in friendQuery.docs) {
      await doc.reference.delete();
    }
  }

  /// 차단 해제
  Future<void> unblockFriend(String userId, String friendId) async {
    final myFriendQuery = await _friendsCollection
        .where('userId', isEqualTo: userId)
        .where('friendId', isEqualTo: friendId)
        .where('status', isEqualTo: FriendStatus.blocked.name)
        .get();

    for (var doc in myFriendQuery.docs) {
      await doc.reference.delete();
    }
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
