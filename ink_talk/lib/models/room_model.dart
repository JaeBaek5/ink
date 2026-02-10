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
  /// 나가기 시각. 설정되면 해당 사용자에게는 채팅방이 안 보임. DB에는 보관.
  final DateTime? leftAt;

  RoomMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.unreadCount = 0,
    this.leftAt,
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
      leftAt: (map['leftAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'role': role.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'unreadCount': unreadCount,
      if (leftAt != null) 'leftAt': Timestamp.fromDate(leftAt!),
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
  /// 마지막 이벤트 미리보기용 URL (이미지/영상 썸네일 등)
  final String? lastEventUrl;
  /// 방장 설정: 멤버의 캔버스 내보내기 허용 여부
  final bool exportAllowed;
  /// 방장 설정: 내보내기 시 워터마크 필수 여부
  final bool watermarkForced;
  /// 방장 설정: 시간순 로그(타임라인) 공개 여부
  final bool logPublic;
  /// 방장 설정: 멤버의 도형 수정 허용 여부
  final bool canEditShapes;
  /// 방장 설정: 캔버스 확장 방식 ('rectangular' | 'free', null이면 사각 확장)
  final String? canvasExpandMode;

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
    this.lastEventUrl,
    this.exportAllowed = true,
    this.watermarkForced = false,
    this.logPublic = true,
    this.canEditShapes = true,
    this.canvasExpandMode,
  });

  static String? _safeString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

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
      lastEventUrl: _safeString(data['lastEventUrl']),
      exportAllowed: data['exportAllowed'] ?? true,
      watermarkForced: data['watermarkForced'] ?? false,
      logPublic: data['logPublic'] ?? true,
      canEditShapes: data['canEditShapes'] ?? true,
      canvasExpandMode: data['canvasExpandMode'] as String?,
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
      if (lastEventUrl != null) 'lastEventUrl': lastEventUrl,
      'exportAllowed': exportAllowed,
      'watermarkForced': watermarkForced,
      'logPublic': logPublic,
      'canEditShapes': canEditShapes,
      if (canvasExpandMode != null) 'canvasExpandMode': canvasExpandMode,
    };
  }

  /// 방장 또는 관리자만 설정 가능한 항목 수정용 복사
  RoomModel copyWithHostSettings({
    bool? exportAllowed,
    bool? watermarkForced,
    bool? logPublic,
    bool? canEditShapes,
    String? canvasExpandMode,
  }) {
    return RoomModel(
      id: id,
      type: type,
      name: name,
      imageUrl: imageUrl,
      memberIds: memberIds,
      members: members,
      createdAt: createdAt,
      lastActivityAt: lastActivityAt,
      lastEventType: lastEventType,
      lastEventPreview: lastEventPreview,
      lastEventUrl: this.lastEventUrl,
      exportAllowed: exportAllowed ?? this.exportAllowed,
      watermarkForced: watermarkForced ?? this.watermarkForced,
      logPublic: logPublic ?? this.logPublic,
      canEditShapes: canEditShapes ?? this.canEditShapes,
      canvasExpandMode: canvasExpandMode ?? this.canvasExpandMode,
    );
  }
}
