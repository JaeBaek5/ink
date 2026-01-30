import 'package:cloud_firestore/cloud_firestore.dart';

/// 채팅방 타입
enum RoomType {
  /// 1:1 채팅
  direct,
  /// 그룹 채팅
  group,
}

/// 멤버 역할
enum MemberRole {
  owner,
  admin,
  member,
  viewer,
}

/// 채팅방 멤버
class RoomMember {
  final String userId;
  final MemberRole role;
  final DateTime joinedAt;
  final int unreadCount;

  RoomMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.unreadCount = 0,
  });

  factory RoomMember.fromMap(Map<String, dynamic> map) {
    return RoomMember(
      userId: map['userId'] ?? '',
      role: MemberRole.values.firstWhere(
        (e) => e.name == map['role'],
        orElse: () => MemberRole.member,
      ),
      joinedAt: (map['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      unreadCount: map['unreadCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'role': role.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'unreadCount': unreadCount,
    };
  }
}

/// 채팅방 모델
class RoomModel {
  final String id;
  final RoomType type;
  final String? name;
  final String? imageUrl;
  final List<String> memberIds;
  final Map<String, RoomMember> members;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final String? lastEventType; // stroke, text, image, video, pdf
  final String? lastEventPreview;

  RoomModel({
    required this.id,
    required this.type,
    this.name,
    this.imageUrl,
    required this.memberIds,
    required this.members,
    required this.createdAt,
    required this.lastActivityAt,
    this.lastEventType,
    this.lastEventPreview,
  });

  factory RoomModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    final membersData = data['members'] as Map<String, dynamic>? ?? {};
    final members = membersData.map(
      (key, value) => MapEntry(key, RoomMember.fromMap(value as Map<String, dynamic>)),
    );

    return RoomModel(
      id: doc.id,
      type: RoomType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => RoomType.direct,
      ),
      name: data['name'],
      imageUrl: data['imageUrl'],
      memberIds: List<String>.from(data['memberIds'] ?? []),
      members: members,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastActivityAt: (data['lastActivityAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastEventType: data['lastEventType'],
      lastEventPreview: data['lastEventPreview'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type.name,
      'name': name,
      'imageUrl': imageUrl,
      'memberIds': memberIds,
      'members': members.map((key, value) => MapEntry(key, value.toMap())),
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActivityAt': Timestamp.fromDate(lastActivityAt),
      'lastEventType': lastEventType,
      'lastEventPreview': lastEventPreview,
    };
  }
}
