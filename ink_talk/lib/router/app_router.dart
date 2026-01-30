import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/splash/splash_screen.dart';

/// 앱 라우터
class AppRouter {
  final AuthProvider authProvider;

  AppRouter(this.authProvider);

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    refreshListenable: authProvider,
    
    // 리다이렉트 로직 (인증 상태에 따라)
    redirect: (context, state) {
      final status = authProvider.status;
      final isOnLogin = state.matchedLocation == '/login';
      final isOnSplash = state.matchedLocation == '/';

      // 초기 상태 (로딩 중)
      if (status == AuthStatus.initial) {
        return isOnSplash ? null : '/';
      }

      // 미인증 상태
      if (status == AuthStatus.unauthenticated) {
        return isOnLogin ? null : '/login';
      }

      // 인증 상태
      if (status == AuthStatus.authenticated) {
        if (isOnLogin || isOnSplash) {
          return '/home';
        }
      }

      return null;
    },

    routes: [
      // 스플래시 (로딩)
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),

      // 로그인
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // 홈 (메인)
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
}
