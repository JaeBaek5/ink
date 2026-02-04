import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/settings_service.dart';

/// 알림 설정 화면
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final _settings = SettingsService();
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _settings.getNotificationsEnabled();
    final sound = await _settings.getNotificationSound();
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _soundEnabled = sound;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('알림 설정')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('알림 설정')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('알림 사용'),
            subtitle: const Text('새 메시지, 친구 요청 등'),
            value: _notificationsEnabled,
            activeColor: AppColors.gold,
            onChanged: (v) async {
              setState(() => _notificationsEnabled = v);
              await _settings.setNotificationsEnabled(v);
            },
          ),
          SwitchListTile(
            title: const Text('알림 소리'),
            subtitle: const Text('알림 시 소리 재생'),
            value: _soundEnabled,
            activeColor: AppColors.gold,
            onChanged: (v) async {
              setState(() => _soundEnabled = v);
              await _settings.setNotificationSound(v);
            },
          ),
        ],
      ),
    );
  }
}
