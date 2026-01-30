import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// 인증 서비스
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// 현재 사용자
  User? get currentUser => _auth.currentUser;

  /// 로그인 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Google 로그인
  Future<User?> signInWithGoogle() async {
    try {
      // Google 로그인 창 띄우기
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // 사용자가 취소함
        return null;
      }

      // Google 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      // Firebase 인증 정보 생성
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase로 로그인
      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      rethrow;
    }
  }

  /// 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
