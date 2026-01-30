import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/friend_model.dart';
import '../models/user_model.dart';
import '../services/friend_service.dart';

/// 친구 프로바이더
class FriendProvider extends ChangeNotifier {
  final FriendService _friendService = FriendService();

  List<FriendModel> _friends = [];
  List<FriendModel> _pendingRequests = [];
  List<FriendModel> _blockedUsers = [];
  final Map<String, UserModel> _friendUserCache = {};

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _friendsSubscription;
  StreamSubscription? _pendingSubscription;
  StreamSubscription? _blockedSubscription;

  /// Getters
  List<FriendModel> get friends => _friends;
  List<FriendModel> get pendingRequests => _pendingRequests;
  List<FriendModel> get blockedUsers => _blockedUsers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get friendCount => _friends.length;
  int get pendingCount => _pendingRequests.length;

  /// 친구 사용자 정보 가져오기
  UserModel? getFriendUser(String friendId) => _friendUserCache[friendId];

  /// 초기화 (로그인 후 호출)
  void initialize(String userId) {
    _friendsSubscription?.cancel();
    _pendingSubscription?.cancel();
    _blockedSubscription?.cancel();

    // 친구 목록 구독
    _friendsSubscription = _friendService.getFriendsStream(userId).listen(
      (friends) async {
        _friends = friends;
        // 친구 사용자 정보 로드
        for (var friend in friends) {
          if (!_friendUserCache.containsKey(friend.friendId)) {
            final userInfo = await _friendService.getFriendUserInfo(friend.friendId);
            if (userInfo != null) {
              _friendUserCache[friend.friendId] = userInfo;
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

    // 받은 요청 구독
    _pendingSubscription = _friendService.getPendingRequestsStream(userId).listen(
      (requests) {
        _pendingRequests = requests;
        notifyListeners();
      },
    );

    // 차단 목록 구독
    _blockedSubscription = _friendService.getBlockedUsersStream(userId).listen(
      (blocked) {
        _blockedUsers = blocked;
        notifyListeners();
      },
    );
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
    _blockedSubscription?.cancel();
    super.dispose();
  }
}
