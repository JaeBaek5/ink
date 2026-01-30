import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

/// 인증 상태
enum AuthStatus {
  /// 초기 상태 (확인 중)
  initial,
  /// 인증됨 (로그인 상태)
  authenticated,
  /// 미인증 (로그아웃 상태)
  unauthenticated,
}

/// 인증 Provider (상태관리)
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus _status = AuthStatus.initial;
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  /// 현재 인증 상태
  AuthStatus get status => _status;
  
  /// 현재 사용자
  User? get user => _user;
  
  /// 로딩 중 여부
  bool get isLoading => _isLoading;
  
  /// 에러 메시지
  String? get errorMessage => _errorMessage;
  
  /// 로그인 여부
  bool get isLoggedIn => _status == AuthStatus.authenticated;

  AuthProvider() {
    _init();
  }

  /// 초기화 (자동 로그인 확인)
  void _init() {
    _authService.authStateChanges.listen((User? user) {
      _user = user;
      if (user != null) {
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
      notifyListeners();
    });
  }

  /// Google 로그인
  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      _isLoading = false;
      notifyListeners();
      return user != null;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 로그아웃
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.signOut();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
