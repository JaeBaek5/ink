import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/utils/firestore_retry.dart';
import '../models/friend_model.dart';
import '../models/user_model.dart';
import '../services/friend_service.dart';

/// 친구 프로바이더
class FriendProvider extends ChangeNotifier {
  final FriendService _friendService = FriendService();

  List<FriendModel> _friends = [];
  List<FriendModel> _pendingRequests = [];
  List<FriendModel> _sentRequests = [];
  List<FriendModel> _blockedUsers = [];
  final Map<String, UserModel> _friendUserCache = {};

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _friendsSubscription;
  StreamSubscription? _pendingSubscription;
  StreamSubscription? _sentSubscription;
  StreamSubscription? _blockedSubscription;
  int _initVersion = 0;

  /// Getters
  List<FriendModel> get friends => _friends;
  List<FriendModel> get pendingRequests => _pendingRequests;
  List<FriendModel> get sentRequests => _sentRequests;
  List<FriendModel> get blockedUsers => _blockedUsers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get friendCount => _friends.length;
  int get pendingCount => _pendingRequests.length;
  int get sentCount => _sentRequests.length;

  /// 친구 사용자 정보 가져오기
  UserModel? getFriendUser(String friendId) => _friendUserCache[friendId];

  /// 초기화. stream 첫 데이터 수신 시 완료되는 Future 반환.
  /// 새로고침이 끝나지 않는 것을 방지하기 위해 데이터 반영 직후 completer 완료, 사용자 정보는 이후 비동기 로드.
  Future<void> initialize(String userId) async {
    _friendsSubscription?.cancel();
    _pendingSubscription?.cancel();
    _sentSubscription?.cancel();
    _blockedSubscription?.cancel();
    _initVersion++;
    final version = _initVersion;
    final completer = Completer<void>();

    void tryComplete() {
      if (!completer.isCompleted) completer.complete();
    }

    // 친구 목록 구독
    _friendsSubscription = streamWithRetry(() => _friendService.getFriendsStream(userId)).listen(
      (friends) async {
        if (version != _initVersion) return;
        _friends = friends;
        tryComplete();
        notifyListeners();
        // 사용자 정보는 새로고침 완료 후 백그라운드에서 로드 (콜백이 오래 블록되지 않도록)
        for (var friend in friends) {
          if (version != _initVersion) return;
          if (!_friendUserCache.containsKey(friend.friendId)) {
            final userInfo = await _friendService.getFriendUserInfo(friend.friendId);
            if (version != _initVersion) return;
            if (userInfo != null) {
              _friendUserCache[friend.friendId] = userInfo;
              notifyListeners();
            }
          }
        }
      },
      onError: (e) {
        if (version == _initVersion) {
          _errorMessage = e.toString();
          tryComplete();
          notifyListeners();
        }
      },
    );

    // 받은 요청 구독
    _pendingSubscription = streamWithRetry(() => _friendService.getPendingRequestsStream(userId)).listen(
      (requests) async {
        if (version != _initVersion) return;
        _pendingRequests = requests;
        notifyListeners();
        for (var req in requests) {
          if (version != _initVersion) return;
          if (!_friendUserCache.containsKey(req.userId)) {
            final userInfo = await _friendService.getFriendUserInfo(req.userId);
            if (version != _initVersion) return;
            if (userInfo != null) {
              _friendUserCache[req.userId] = userInfo;
              notifyListeners();
            }
          }
        }
      },
    );

    // 보낸 친구 요청 구독 (대기중/거절됨)
    _sentSubscription = streamWithRetry(() => _friendService.getSentRequestsStream(userId)).listen(
      (requests) async {
        if (version != _initVersion) return;
        _sentRequests = requests;
        notifyListeners();
        for (var req in requests) {
          if (version != _initVersion) return;
          if (!_friendUserCache.containsKey(req.friendId)) {
            final userInfo = await _friendService.getFriendUserInfo(req.friendId);
            if (version != _initVersion) return;
            if (userInfo != null) {
              _friendUserCache[req.friendId] = userInfo;
              notifyListeners();
            }
          }
        }
      },
    );

    // 차단 목록 구독
    _blockedSubscription = streamWithRetry(() => _friendService.getBlockedUsersStream(userId)).listen(
      (blocked) async {
        if (version != _initVersion) return;
        _blockedUsers = blocked;
        notifyListeners();
        for (var b in blocked) {
          if (version != _initVersion) return;
          if (!_friendUserCache.containsKey(b.friendId)) {
            final userInfo = await _friendService.getFriendUserInfo(b.friendId);
            if (version != _initVersion) return;
            if (userInfo != null) {
              _friendUserCache[b.friendId] = userInfo;
              notifyListeners();
            }
          }
        }
      },
    );

    // 15초 내에 스트림이 한 번도 오지 않으면 강제 완료 (앱 정지 방지)
    return Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 15), () {}),
    ]);
  }

  /// ID로 친구 추가
  Future<bool> addFriendById(String userId, String friendVisibleId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _friendService.addFriendById(userId, friendVisibleId);
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

  /// 전화번호로 친구 추가
  Future<bool> addFriendByPhone(String userId, String phoneNumber) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _friendService.addFriendByPhone(userId, phoneNumber);
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

  /// 친구 삭제
  Future<bool> removeFriend(String userId, String friendId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _friendService.removeFriend(userId, friendId);
      _friendUserCache.remove(friendId);
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

  /// 친구 차단
  Future<bool> blockFriend(String userId, String friendId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _friendService.blockFriend(userId, friendId);
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

  /// 차단 해제
  Future<bool> unblockFriend(String userId, String friendId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _friendService.unblockFriend(userId, friendId);
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

  /// 친구 요청 수락
  Future<bool> acceptFriendRequest(String userId, String requestId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _friendService.acceptFriendRequest(userId, requestId);
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

  /// 친구 요청 거절
  Future<bool> rejectFriendRequest(String userId, String requestId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _friendService.rejectFriendRequest(userId, requestId);
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

  /// 친구 별명 설정
  Future<bool> updateFriendNickname(String userId, String friendId, String? nickname) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _friendService.updateFriendNickname(userId, friendId, nickname);
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

  /// 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 정리
  @override
  void dispose() {
    _friendsSubscription?.cancel();
    _pendingSubscription?.cancel();
    _sentSubscription?.cancel();
    _blockedSubscription?.cancel();
    super.dispose();
  }
}
