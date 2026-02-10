import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' show Source;
import 'package:flutter/foundation.dart';
import '../core/utils/firestore_retry.dart';
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
  int _initVersion = 0;

  /// Getters
  List<RoomModel> get rooms => _rooms;
  RoomModel? get selectedRoom => _selectedRoom;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get roomCount => _rooms.length;

  /// 멤버 사용자 정보 가져오기
  UserModel? getMemberUser(String memberId) => _memberUserCache[memberId];

  /// 초기화. stream 첫 데이터 수신 시 완료되는 Future 반환.
  Future<void> initialize(String userId) async {
    _roomsSubscription?.cancel();
    _initVersion++;
    final version = _initVersion;
    final completer = Completer<void>();

    _roomsSubscription = streamWithRetry(() => _roomService.getRoomsStream(userId)).listen(
      (rooms) async {
        if (version != _initVersion) return; // 취소된 구독 무시
        _rooms = rooms;

        // 멤버 정보 로드
        for (final room in rooms) {
          for (final memberId in room.memberIds) {
            if (version != _initVersion) return;
            if (!_memberUserCache.containsKey(memberId)) {
              final user = await _roomService.getMemberUserInfo(memberId);
              if (user != null) {
                _memberUserCache[memberId] = user;
              }
            }
          }
        }
        if (version == _initVersion && !completer.isCompleted) {
          completer.complete();
        }
        notifyListeners();
      },
      onError: (e) {
        if (version == _initVersion) {
          _errorMessage = e.toString();
          if (!completer.isCompleted) completer.complete();
          notifyListeners();
        }
      },
    );

    return completer.future;
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

  /// 채팅방 실시간 스트림 (단일 방)
  Stream<RoomModel?> getRoomStream(String roomId) {
    return streamWithRetry(() => _roomService.getRoomStream(roomId));
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
    bool? exportAllowed,
    bool? watermarkForced,
    bool? logPublic,
    bool? canEditShapes,
    String? canvasExpandMode,
  }) async {
    try {
      await _roomService.updateRoom(
        roomId,
        name: name,
        imageUrl: imageUrl,
        exportAllowed: exportAllowed,
        watermarkForced: watermarkForced,
        logPublic: logPublic,
        canEditShapes: canEditShapes,
        canvasExpandMode: canvasExpandMode,
      );
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// 1:1 채팅방 조회 (없으면 null, 생성하지 않음)
  Future<RoomModel?> getDirectRoom(String userId, String friendId) async {
    return _roomService.getDirectRoom(userId, friendId);
  }

  /// 서버에서 채팅방 존재 여부 확인 (캐시 무시). 삭제된 방이면 null.
  Future<RoomModel?> getRoomFromServer(String roomId) async {
    return _roomService.getRoom(roomId, source: Source.server);
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
