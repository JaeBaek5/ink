import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/friend_provider.dart';
import 'providers/room_provider.dart';
import 'router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase 초기화
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  runApp(const InkApp());
}

class InkApp extends StatelessWidget {
  const InkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 인증 Provider
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // 친구 Provider
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        // 채팅방 Provider
        ChangeNotifierProvider(create: (_) => RoomProvider()),
      ],
      child: const _AppWithRouter(),
    );
  }
}

class _AppWithRouter extends StatelessWidget {
  const _AppWithRouter();

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final appRouter = AppRouter(authProvider);

    return MaterialApp.router(
      title: 'INK',
      debugShowCheckedModeBanner: false,
      
      // 테마
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      
      // 라우터
      routerConfig: appRouter.router,
    );
  }
}
