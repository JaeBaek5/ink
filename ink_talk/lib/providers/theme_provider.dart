import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// 테마 모드 상태 (설정 저장·복원)
class ThemeProvider extends ChangeNotifier {
  final SettingsService _settings = SettingsService();
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final saved = await _settings.getThemeMode();
    ThemeMode mode = ThemeMode.system;
    if (saved == 'light') mode = ThemeMode.light;
    if (saved == 'dark') mode = ThemeMode.dark;
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    String value = 'system';
    if (mode == ThemeMode.light) value = 'light';
    if (mode == ThemeMode.dark) value = 'dark';
    await _settings.setThemeMode(value);
    _themeMode = mode;
    notifyListeners();
  }

  String get themeModeLabel {
    switch (_themeMode) {
      case ThemeMode.light:
        return '라이트';
      case ThemeMode.dark:
        return '다크';
      case ThemeMode.system:
        return '시스템 설정';
    }
  }
}
