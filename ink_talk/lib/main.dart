import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'INK',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB08D57)),
        scaffoldBackgroundColor: const Color(0xFFFAF7F0),
      ),
      home: const LoginTestPage(),
    );
  }
}

class LoginTestPage extends StatefulWidget {
  const LoginTestPage({super.key});

  @override
  State<LoginTestPage> createState() => _LoginTestPageState();
}

class _LoginTestPageState extends State<LoginTestPage> {
  User? _user;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 로그인 상태 변화 감지
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      setState(() {
        _user = user;
      });
    });
  }

  // Google 로그인
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      // Google 로그인 창 띄우기
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        // 사용자가 취소함
        setState(() => _isLoading = false);
        return;
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
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('로그인 실패: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 로그아웃
  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'INK 로그인 테스트',
          style: TextStyle(color: Color(0xFF0F172A)),
        ),
        backgroundColor: const Color(0xFFFAF7F0),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child:
              _user == null ? _buildLoginView() : _buildUserInfoView(_user!),
        ),
      ),
    );
  }

  Widget _buildLoginView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.edit, size: 80, color: Color(0xFFB08D57)),
        const SizedBox(height: 24),
        const Text(
          'INK',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '손글씨 기반 실시간 메신저',
          style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _signInWithGoogle,
            icon:
                _isLoading
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.login),
            label: Text(_isLoading ? '로그인 중...' : 'Google로 로그인'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: const Color(0xFFFAF7F0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserInfoView(User user) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 50,
          backgroundImage:
              user.photoURL != null ? NetworkImage(user.photoURL!) : null,
          backgroundColor: const Color(0xFFB08D57),
          child:
              user.photoURL == null
                  ? const Icon(Icons.person, size: 50, color: Colors.white)
                  : null,
        ),
        const SizedBox(height: 24),
        const Text(
          '로그인 성공!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user.displayName ?? '이름 없음',
          style: const TextStyle(fontSize: 20, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        Text(
          user.email ?? '이메일 없음',
          style: const TextStyle(fontSize: 16, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 8),
        Text(
          'UID: ${user.uid}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('로그아웃'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F172A),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
