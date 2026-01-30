import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/room_model.dart';
import '../models/user_model.dart';
import '../services/room_service.dart';

/// 채팅방 프로바이더
class RoomProvider extends ChangeNotifier {
  final RoomService _roomService = RoomService();

  List<RoomModel> _rooms = [];
  final Map<String, UserModel> _memberUserCache = {};
  RoomModel? _selectedRoom;

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _roomsSubscription;

  /// Getters
  List<RoomModel> get rooms => _rooms;
  RoomModel? get selectedRoom => _selectedRoom;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get roomCount => _rooms.length;

  /// 멤버 사용자 정보 가져오기
  UserModel? getMemberUser(String memberId) => _memberUserCache[memberId];

  /// 초기화
  void initialize(String userId) {
    _roomsSubscription?.cancel();

    _roomsSubscription = _roomService.getRoomsStream(userId).listen(
      (rooms) async {
        _rooms = rooms;

        // 멤버 정보 로드
        for (final room in rooms) {
          for (final memberId in room.memberIds) {
            if (!_memberUserCache.containsKey(memberId)) {
              final user = await _roomService.getMemberUserInfo(memberId);
              if (user != null) {
                _memberUserCache[memberId] = user;
              }
            }
          }
        }
        notifyListeners();
      },
      onError: (e) {
        _errorMessage = e.toString();
        notifyListeners();
      },
    );
  }

  /// 1:1 채팅 생성
  Future<RoomModel?> createDirectRoom(String userId, String friendId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final room = await _roomService.createOrGetDirectRoom(userId, friendId);
      _isLoading = false;
      notifyListeners();
      return room;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// 그룹 채팅 생성
  Future<RoomModel?> createGroupRoom({
    required String ownerId,
    required List<String> memberIds,
    required String name,
    String? imageUrl,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final room = await _roomService.createGroupRoom(
        ownerId: ownerId,
        memberIds: memberIds,
        name: name,
        imageUrl: imageUrl,
      );
      _isLoading = false;
      notifyListeners();
      return room;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// 채팅방 선택
  void selectRoom(RoomModel? room) {
    _selectedRoom = room;
    notifyListeners();
  }

  /// 채팅방 나가기
  Future<bool> leaveRoom(String roomId, String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _roomService.leaveRoom(roomId, userId);
      if (_selectedRoom?.id == roomId) {
        _selectedRoom = null;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 멤버 초대
  Future<bool> inviteMembers(String roomId, List<String> memberIds) async {
    try {
      await _roomService.inviteMembers(roomId, memberIds);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// 역할 변경
  Future<bool> updateMemberRole(
    String roomId,
    String memberId,
    MemberRole newRole,
  ) async {
    try {
      await _roomService.updateMemberRole(roomId, memberId, newRole);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// 채팅방 정보 수정
  Future<bool> updateRoom(
    String roomId, {
    String? name,
    String? imageUrl,
  }) async {
    try {
      await _roomService.updateRoom(roomId, name: name, imageUrl: imageUrl);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// 읽음 처리
  Future<void> markAsRead(String roomId, String userId) async {
    await _roomService.markAsRead(roomId, userId);
  }

  /// 에러 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 채팅방 이름 가져오기 (1:1의 경우 상대방 이름)
  String getRoomDisplayName(RoomModel room, String currentUserId) {
    if (room.name != null && room.name!.isNotEmpty) {
      return room.name!;
    }

    // 1:1 채팅의 경우 상대방 이름
    if (room.type == RoomType.direct) {
      final otherMemberId = room.memberIds.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );
      final otherUser = _memberUserCache[otherMemberId];
      return otherUser?.displayName ?? '알 수 없음';
    }

    return '채팅방';
  }

  /// 채팅방 이미지 가져오기
  String? getRoomDisplayImage(RoomModel room, String currentUserId) {
    if (room.imageUrl != null) {
      return room.imageUrl;
    }

    // 1:1 채팅의 경우 상대방 프로필
    if (room.type == RoomType.direct) {
      final otherMemberId = room.memberIds.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );
      return _memberUserCache[otherMemberId]?.photoUrl;
    }

    return null;
  }

  @override
  void dispose() {
    _roomsSubscription?.cancel();
    super.dispose();
  }
}
