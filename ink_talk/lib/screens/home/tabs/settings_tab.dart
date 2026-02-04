import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/room_provider.dart';
import '../../../services/settings_service.dart';
import '../../canvas/canvas_screen.dart';
import '../../settings/profile_edit_screen.dart';
import '../../settings/notification_settings_screen.dart';
import '../../settings/canvas_expand_screen.dart';
import '../../settings/cache_screen.dart';
import '../../settings/hover_visibility_screen.dart';

/// 설정 탭
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _settings = SettingsService();
  CanvasExpandMode _canvasExpandMode = CanvasExpandMode.rectangular;

  @override
  void initState() {
    super.initState();
    _loadCanvasMode();
  }

  Future<void> _loadCanvasMode() async {
    final mode = await _settings.getCanvasExpandMode();
    if (mounted) setState(() => _canvasExpandMode = mode);
  }

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
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  color: AppColors.mutedGray,
                  onPressed: () async {
                    await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileEditScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          const Divider(),
          
          // 일반 설정
          _buildSectionHeader('일반'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('알림 설정'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('테마'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '시스템 설정',
                  style: TextStyle(
                    color: AppColors.mutedGray,
                    fontSize: 14,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () {},
          ),
          
          const Divider(),
          
          // 캔버스 설정
          _buildSectionHeader('캔버스'),
          ListTile(
            leading: const Icon(Icons.expand_outlined),
            title: const Text('캔버스 확장 방식'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _canvasExpandMode.displayName,
                  style: TextStyle(
                    color: AppColors.mutedGray,
                    fontSize: 14,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CanvasExpandScreen(),
                ),
              );
              if (mounted) _loadCanvasMode();
            },
          ),
          ListTile(
            leading: const Icon(Icons.brush_outlined),
            title: const Text('기본 펜 설정'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.person_pin_circle_outlined),
            title: const Text('호버 표시'),
            subtitle: const Text('다른 사용자 커서/닉네임 표시 범위'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HoverVisibilityScreen(),
                ),
              );
            },
          ),
          
          const Divider(),
          
          // 저장공간
          _buildSectionHeader('저장공간'),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('캐시 관리'),
            subtitle: const Text('이미지, PDF 캐시'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CacheScreen(),
                ),
              );
            },
          ),
          
          const Divider(),
          
          // 개발자 옵션
          _buildSectionHeader('개발자'),
          ListTile(
            leading: const Icon(Icons.science_outlined, color: AppColors.gold),
            title: const Text('테스트 채팅방 생성'),
            subtitle: const Text('캔버스 테스트용'),
            onTap: () => _createTestRoom(context),
          ),
          
          const Divider(),
          
          // 계정
          _buildSectionHeader('계정'),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              '로그아웃',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () => _handleSignOut(context),
          ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined, color: Colors.red),
            title: const Text(
              '계정 탈퇴',
              style: TextStyle(color: Colors.red, fontSize: 14),
            ),
            subtitle: const Text('모든 데이터가 삭제되며 복구할 수 없습니다.'),
            onTap: () => _handleDeleteAccount(context),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계정 탈퇴'),
        content: const Text(
          '정말 탈퇴하시겠습니까? 계정과 저장된 데이터가 모두 삭제되며 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final ok = await context.read<AuthProvider>().deleteAccount();
    if (context.mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('계정이 삭제되었습니다.')),
        );
      } else {
        final msg = context.read<AuthProvider>().errorMessage ?? '탈퇴에 실패했습니다.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.mutedGray,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _createTestRoom(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    final userId = authProvider.user?.uid;

    if (userId == null) return;

    // 테스트 채팅방 생성
    final room = await roomProvider.createTestRoom(userId);

    if (room != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('테스트 채팅방이 생성되었습니다!')),
      );
      
      // 캔버스 화면으로 이동
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CanvasScreen(room: room),
        ),
      );
    }
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
