import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/settings_service.dart';

/// 호버 사용자 식별 설정 (친구만/전체/OFF)
class HoverVisibilityScreen extends StatefulWidget {
  const HoverVisibilityScreen({super.key});

  @override
  State<HoverVisibilityScreen> createState() => _HoverVisibilityScreenState();
}

class _HoverVisibilityScreenState extends State<HoverVisibilityScreen> {
  final _settings = SettingsService();
  HoverVisibility _visibility = HoverVisibility.all;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _settings.getHoverVisibility();
    if (mounted) setState(() {
      _visibility = v;
      _loading = false;
    });
  }

  Future<void> _set(HoverVisibility v) async {
    setState(() => _visibility = v);
    await _settings.setHoverVisibility(v);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${v.displayName}(으)로 저장되었습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('호버 표시')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('호버 표시')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '캔버스에서 다른 사용자 펜 근접 시 커서/닉네임 표시 범위',
              style: TextStyle(color: AppColors.mutedGray),
            ),
          ),
          RadioListTile<HoverVisibility>(
            title: const Text('전체'),
            subtitle: const Text('모든 참여자 표시'),
            value: HoverVisibility.all,
            groupValue: _visibility,
            activeColor: AppColors.gold,
            onChanged: (v) => v != null ? _set(v) : null,
          ),
          RadioListTile<HoverVisibility>(
            title: const Text('친구만'),
            subtitle: const Text('친구로 등록된 사용자만 표시'),
            value: HoverVisibility.friends,
            groupValue: _visibility,
            activeColor: AppColors.gold,
            onChanged: (v) => v != null ? _set(v) : null,
          ),
          RadioListTile<HoverVisibility>(
            title: const Text('끄기'),
            subtitle: const Text('호버 시 표시 안 함'),
            value: HoverVisibility.off,
            groupValue: _visibility,
            activeColor: AppColors.gold,
            onChanged: (v) => v != null ? _set(v) : null,
          ),
        ],
      ),
    );
  }
}
