import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';

/// 홈 화면 (하단 탭 네비게이션)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // 채팅 탭이 기본

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _FriendsTab(),
          _ChatTab(),
          _TagsTab(),
          _SettingsTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
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
          ],
        ),
      ),
    );
  }
}

/// 친구 탭
class _FriendsTab extends StatelessWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('친구'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () {
              // TODO: 친구 추가
            },
          ),
        ],
      ),
      body: const Center(
        child: Text(
          '친구 목록',
          style: TextStyle(color: AppColors.mutedGray),
        ),
      ),
    );
  }
}

/// 채팅 탭
class _ChatTab extends StatelessWidget {
  const _ChatTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            color: AppColors.gold,
            onPressed: () {
              // TODO: 새 채팅
            },
          ),
        ],
      ),
      body: const Center(
        child: Text(
          '채팅 목록',
          style: TextStyle(color: AppColors.mutedGray),
        ),
      ),
    );
  }
}

/// 모아보기 탭
class _TagsTab extends StatelessWidget {
  const _TagsTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('모아보기'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: 필터
            },
          ),
        ],
      ),
      body: const Center(
        child: Text(
          '태그된 항목',
          style: TextStyle(color: AppColors.mutedGray),
        ),
      ),
    );
  }
}

/// 설정 탭
class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        children: [
          // 프로필 섹션
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  backgroundColor: AppColors.gold,
                  child: user?.photoURL == null
                      ? const Icon(Icons.person, color: Colors.white, size: 30)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? '이름 없음',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.mutedGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(),
          
          // 메뉴 항목들
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('알림'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('테마'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('저장공간'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          
          const Divider(),
          
          // 로그아웃
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              '로그아웃',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () => _handleSignOut(context),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<AuthProvider>().signOut();
    }
  }
}
