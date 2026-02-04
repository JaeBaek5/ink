import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/friend_provider.dart';
import 'providers/room_provider.dart';
import 'providers/tag_provider.dart';
import 'router/app_router.dart';
import 'services/network_connectivity_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 예외 발생 시 호출 스택 출력 (디버그 콘솔에서 확인)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('--- FlutterError ---');
    debugPrint(details.exceptionAsString());
    if (details.stack != null) {
      debugPrint('--- Stack trace ---');
      debugPrint(details.stack.toString());
    }
  };

  // 비동기/존 밖 예외도 스택과 함께 캡처
  runZonedGuarded(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    runApp(const InkApp());
  }, (error, stackTrace) {
    debugPrint('--- Uncaught error ---');
    debugPrint(error.toString());
    debugPrint('--- Stack trace ---');
    debugPrint(stackTrace.toString());
  });
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
        // 태그 Provider
        ChangeNotifierProvider(create: (_) => TagProvider()),
        // 네트워크 연결 (재연결 배너·대기열)
        ChangeNotifierProvider(create: (_) => NetworkConnectivityService()),
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
