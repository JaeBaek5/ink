import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/settings_service.dart';

/// 캔버스 확장 방식 설정 화면
class CanvasExpandScreen extends StatefulWidget {
  const CanvasExpandScreen({super.key});

  @override
  State<CanvasExpandScreen> createState() => _CanvasExpandScreenState();
}

class _CanvasExpandScreenState extends State<CanvasExpandScreen> {
  final _settings = SettingsService();
  CanvasExpandMode _mode = CanvasExpandMode.rectangular;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await _settings.getCanvasExpandMode();
    if (mounted) {
      setState(() {
        _mode = mode;
        _loading = false;
      });
    }
  }

  Future<void> _setMode(CanvasExpandMode mode) async {
    setState(() => _mode = mode);
    await _settings.setCanvasExpandMode(mode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${mode.displayName}(으)로 저장되었습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('캔버스 확장 방식')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('캔버스 확장 방식')),
      body: ListView(
        children: [
          RadioListTile<CanvasExpandMode>(
            title: const Text('사각 확장'),
            subtitle: const Text('캔버스를 사각형 영역 단위로 확장'),
            value: CanvasExpandMode.rectangular,
            groupValue: _mode,
            activeColor: AppColors.gold,
            onChanged: (v) => v != null ? _setMode(v) : null,
          ),
          RadioListTile<CanvasExpandMode>(
            title: const Text('자유 확장'),
            subtitle: const Text('무한 캔버스 방식으로 자유롭게 확장'),
            value: CanvasExpandMode.free,
            groupValue: _mode,
            activeColor: AppColors.gold,
            onChanged: (v) => v != null ? _setMode(v) : null,
          ),
        ],
      ),
    );
  }
}
