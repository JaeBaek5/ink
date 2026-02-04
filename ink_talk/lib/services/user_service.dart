import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

/// 사용자 서비스
class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 컬렉션 참조
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// 현재 사용자 ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// 사용자 생성 또는 업데이트 (로그인 시 호출)
  Future<UserModel> createOrUpdateUser(User firebaseUser) async {
    final docRef = _usersCollection.doc(firebaseUser.uid);
    final doc = await docRef.get();

    if (doc.exists) {
      // 기존 사용자: lastActiveAt 업데이트
      await docRef.update({
        'lastActiveAt': FieldValue.serverTimestamp(),
        'displayName': firebaseUser.displayName,
        'photoUrl': firebaseUser.photoURL,
        'email': firebaseUser.email,
      });
    } else {
      // 신규 사용자 생성
      final newUser = UserModel(
        uid: firebaseUser.uid,
        visibleId: _generateVisibleId(),
        email: firebaseUser.email,
        displayName: firebaseUser.displayName,
        photoUrl: firebaseUser.photoURL,
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      );
      await docRef.set(newUser.toFirestore());
    }

    final updatedDoc = await docRef.get();
    return UserModel.fromFirestore(updatedDoc);
  }

  /// 사용자 조회 (UID)
  Future<UserModel?> getUserById(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  /// 사용자 조회 (visibleId)
  Future<UserModel?> getUserByVisibleId(String visibleId) async {
    final query = await _usersCollection
        .where('visibleId', isEqualTo: visibleId)
        .limit(1)
        .get();
    
    if (query.docs.isEmpty) return null;
    return UserModel.fromFirestore(query.docs.first);
  }

  /// 사용자 검색 (이름/ID)
  Future<List<UserModel>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    // visibleId로 검색
    final byId = await _usersCollection
        .where('visibleId', isGreaterThanOrEqualTo: query)
        .where('visibleId', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(20)
        .get();

    return byId.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
  }

  /// 프로필 업데이트
  Future<void> updateProfile({
    String? displayName,
    String? statusMessage,
    String? visibleId,
  }) async {
    if (currentUserId == null) return;

    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (statusMessage != null) updates['statusMessage'] = statusMessage;
    if (visibleId != null) {
      // visibleId 중복 확인
      final existing = await getUserByVisibleId(visibleId);
      if (existing != null && existing.uid != currentUserId) {
        throw Exception('이미 사용 중인 ID입니다.');
      }
      updates['visibleId'] = visibleId;
    }

    if (updates.isNotEmpty) {
      await _usersCollection.doc(currentUserId).update(updates);
    }

    if (displayName != null) {
      await _auth.currentUser?.updateDisplayName(displayName);
    }
  }

  /// 사용자 문서 삭제 (탈퇴 시 Firestore 정리)
  Future<void> deleteUserDocument(String uid) async {
    await _usersCollection.doc(uid).delete();
  }

  /// 랜덤 visibleId 생성
  String _generateVisibleId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    return 'ink_${List.generate(8, (i) => chars[(random + i * 7) % chars.length]).join()}';
  }
}
