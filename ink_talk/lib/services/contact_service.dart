import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

/// 연락처 동기화 서비스
class ContactService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 연락처 권한 상태 확인
  Future<PermissionStatus> checkPermission() async {
    return await Permission.contacts.status;
  }

  /// 연락처 권한 요청
  Future<bool> requestPermission() async {
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  /// 연락처 목록 가져오기
  Future<List<Contact>> getContacts() async {
    final hasPermission = await FlutterContacts.requestPermission();
    if (!hasPermission) {
      return [];
    }

    return await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );
  }

  /// 연락처에서 전화번호 추출 및 정규화
  List<String> extractPhoneNumbers(List<Contact> contacts) {
    final phoneNumbers = <String>[];

    for (final contact in contacts) {
      for (final phone in contact.phones) {
        final normalized = _normalizePhoneNumber(phone.number);
        if (normalized.isNotEmpty) {
          phoneNumbers.add(normalized);
        }
      }
    }

    return phoneNumbers.toSet().toList(); // 중복 제거
  }

  /// 연락처 기반 친구 추천 (INK 가입자 찾기)
  Future<List<ContactRecommendation>> findRegisteredUsers(
    String currentUserId,
    List<String> phoneNumbers,
  ) async {
    if (phoneNumbers.isEmpty) return [];

    final recommendations = <ContactRecommendation>[];

    // Firestore는 in 쿼리에 30개 제한이 있으므로 분할
    const batchSize = 30;
    for (var i = 0; i < phoneNumbers.length; i += batchSize) {
      final batch = phoneNumbers.skip(i).take(batchSize).toList();

      final query = await _firestore
          .collection('users')
          .where('phoneNumber', whereIn: batch)
          .get();

      for (final doc in query.docs) {
        final user = UserModel.fromFirestore(doc);
        
        // 자기 자신 제외
        if (user.uid == currentUserId) continue;

        // 이미 친구인지 확인
        final isFriend = await _checkIfFriend(currentUserId, user.uid);
        if (isFriend) continue;

        recommendations.add(ContactRecommendation(
          user: user,
          matchedPhone: batch.firstWhere(
            (phone) => _matchesUserPhone(user, phone),
            orElse: () => '',
          ),
        ));
      }
    }

    return recommendations;
  }

  /// 사용자가 이미 친구인지 확인
  Future<bool> _checkIfFriend(String userId, String friendId) async {
    final query = await _firestore
        .collection('friends')
        .where('userId', isEqualTo: userId)
        .where('friendId', isEqualTo: friendId)
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  /// 전화번호 정규화
  String _normalizePhoneNumber(String phone) {
    // 숫자만 추출
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return '';

    // 한국 번호 처리
    if (digits.startsWith('82')) {
      return '+$digits';
    } else if (digits.startsWith('010')) {
      return '+82${digits.substring(1)}';
    } else if (digits.startsWith('01')) {
      // 011, 016, 017, 018, 019
      return '+82${digits.substring(1)}';
    }

    // 국제 번호
    if (digits.length >= 10) {
      return '+$digits';
    }

    return '';
  }

  /// 사용자 전화번호 매칭 확인
  bool _matchesUserPhone(UserModel user, String normalizedPhone) {
    // UserModel에 phoneNumber 필드가 있다고 가정
    // 실제 구현에서는 UserModel에 phoneNumber 추가 필요
    return true;
  }
}

/// 연락처 추천 모델
class ContactRecommendation {
  final UserModel user;
  final String matchedPhone;

  ContactRecommendation({
    required this.user,
    required this.matchedPhone,
  });
}
