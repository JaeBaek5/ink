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
import 'providers/theme_provider.dart';
import 'router/app_router.dart';
import 'services/network_connectivity_service.dart';

void main() async {
  // ensureInitialized와 runApp을 같은 zone에서 호출해야 Zone mismatch 방지
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('--- FlutterError ---');
      debugPrint(details.exceptionAsString());
      if (details.stack != null) {
        debugPrint('--- Stack trace ---');
        debugPrint(details.stack.toString());
      }
    };

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
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        ChangeNotifierProvider(create: (_) => RoomProvider()),
        ChangeNotifierProvider(create: (_) => TagProvider()),
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
    final themeProvider = context.watch<ThemeProvider>();
    final appRouter = AppRouter(authProvider);

    return MaterialApp.router(
      title: 'INK',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeProvider.themeMode,
      routerConfig: appRouter.router,
    );
  }
}
