import 'package:cloud_firestore/cloud_firestore.dart';

/// 친구 상태
enum FriendStatus {
  /// 친구 요청 대기 중
  pending,
  /// 친구 수락됨
  accepted,
  /// 차단됨
  blocked,
}

/// 친구 관계 모델
class FriendModel {
  final String id;
  final String userId;
  final String friendId;
  final FriendStatus status;
  final String? nickname; // 친구에게 설정한 별명
  final DateTime createdAt;
  final DateTime? acceptedAt;

  FriendModel({
    required this.id,
    required this.userId,
    required this.friendId,
    required this.status,
    this.nickname,
    required this.createdAt,
    this.acceptedAt,
  });

  factory FriendModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FriendModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      friendId: data['friendId'] ?? '',
      status: FriendStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => FriendStatus.pending,
      ),
      nickname: data['nickname'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'friendId': friendId,
      'status': status.name,
      'nickname': nickname,
      'createdAt': Timestamp.fromDate(createdAt),
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
    };
  }
}
