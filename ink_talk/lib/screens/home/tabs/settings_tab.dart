import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/settings_service.dart';
import '../../settings/profile_edit_screen.dart';
import '../../settings/notification_settings_screen.dart';
import '../../settings/theme_screen.dart';
import '../../settings/canvas_expand_screen.dart';
import '../../settings/cache_screen.dart';
import '../../settings/hover_visibility_screen.dart';
import '../../settings/blocked_users_screen.dart';
import '../../settings/default_pen_screen.dart';

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
    final themeProvider = context.watch<ThemeProvider>();
    final user = authProvider.user;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        children: [
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
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
          _buildSectionHeader(context, '일반'),
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
                  themeProvider.themeModeLabel,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ThemeScreen(),
                ),
              );
            },
          ),
          
          const Divider(),
          _buildSectionHeader(context, '친구'),
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: const Text('친구 차단 관리'),
            subtitle: const Text('차단한 사용자 목록 및 차단 해제'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BlockedUsersScreen(),
                ),
              );
            },
          ),
          
          const Divider(),
          _buildSectionHeader(context, '캔버스'),
          ListTile(
            leading: const Icon(Icons.expand_outlined),
            title: const Text('캔버스 확장 방식'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _canvasExpandMode.displayName,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DefaultPenScreen(),
                ),
              );
            },
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
          _buildSectionHeader(context, '저장공간'),
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
          _buildSectionHeader(context, '계정'),
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

    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.deleteAccount();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정이 삭제되었습니다.')),
      );
    } else {
      String msg = authProvider.errorMessage ?? '탈퇴에 실패했습니다.';
      msg = msg.replaceAll('Exception: ', '');
      if (msg.contains('requires-recent-login') || msg.contains('재인증')) {
        msg = '보안을 위해 다시 로그인한 뒤 탈퇴를 시도해 주세요.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
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
