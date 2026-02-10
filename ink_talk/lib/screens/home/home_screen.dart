import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/layouts/adaptive_scaffold.dart';

// 탭 화면들
import 'tabs/friends_tab.dart';
import 'tabs/chat_tab.dart';
import 'tabs/tags_tab.dart';
import 'tabs/settings_tab.dart';

/// 홈 화면 (하단 탭 네비게이션)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // 채팅 탭이 기본

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.user?.uid;
      if (userId != null) {
        context.read<RoomProvider>().initialize(userId);
        context.read<FriendProvider>().initialize(userId);
      }
    });
  }

  final List<Widget> _screens = const [
    FriendsTab(),
    ChatTab(),
    TagsTab(),
    SettingsTab(),
  ];

  final List<BottomNavigationBarItem> _tabItems = const [
    BottomNavigationBarItem(
      icon: Icon(Icons.people_outline),
      activeIcon: Icon(Icons.people),
      label: '친구',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.chat_bubble_outline),
      activeIcon: Icon(Icons.chat_bubble),
      label: '채팅',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.bookmark_outline),
      activeIcon: Icon(Icons.bookmark),
      label: '모아보기',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.settings_outlined),
      activeIcon: Icon(Icons.settings),
      label: '설정',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      currentIndex: _currentIndex,
      onTabChanged: (index) => setState(() => _currentIndex = index),
      screens: _screens,
      tabItems: _tabItems,
      // 상세 뷰는 나중에 채팅방 선택 시 표시
      detailView: _buildDetailPlaceholder(),
    );
  }

  /// 상세 뷰 플레이스홀더 (패드 우측 패널)
  Widget _buildDetailPlaceholder() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: AppColors.mutedGray,
            ),
            SizedBox(height: 16),
            Text(
              '채팅방을 선택하세요',
              style: TextStyle(
                color: AppColors.mutedGray,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
