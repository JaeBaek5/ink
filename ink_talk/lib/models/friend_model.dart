import 'package:cloud_firestore/cloud_firestore.dart';

/// 친구 상태
enum FriendStatus {
  /// 친구 요청 대기 중
  pending,
  /// 친구 수락됨
  accepted,
  /// 요청 거절됨 (보낸 사용자가 확인 가능)
  rejected,
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
  /// 삭제(숨김) 여부. true면 목록에 안 보임. DB에는 보관(관리자 확인용).
  final bool hidden;
  final DateTime? hiddenAt;
  /// 숨김 처리한 사용자 uid (관리자 확인/복구용)
  final String? hiddenBy;
  /// 차단한 시각 (차단 기간 중 받은 메시지 필터/카운트용)
  final DateTime? blockedAt;

  FriendModel({
    required this.id,
    required this.userId,
    required this.friendId,
    required this.status,
    this.nickname,
    required this.createdAt,
    this.acceptedAt,
    this.hidden = false,
    this.hiddenAt,
    this.hiddenBy,
    this.blockedAt,
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
      hidden: data['hidden'] == true,
      hiddenAt: (data['hiddenAt'] as Timestamp?)?.toDate(),
      hiddenBy: data['hiddenBy'] as String?,
      blockedAt: (data['blockedAt'] as Timestamp?)?.toDate(),
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
      if (hidden) 'hidden': true,
      if (hiddenAt != null) 'hiddenAt': Timestamp.fromDate(hiddenAt!),
      if (hiddenBy != null) 'hiddenBy': hiddenBy,
    };
  }
}
