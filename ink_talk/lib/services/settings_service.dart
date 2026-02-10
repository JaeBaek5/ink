import 'package:shared_preferences/shared_preferences.dart';

/// 캔버스 확장 방식
enum CanvasExpandMode {
  /// 사각형 영역으로 확장
  rectangular,
  /// 자유 확장 (무한 캔버스)
  free,
}

extension CanvasExpandModeX on CanvasExpandMode {
  String get displayName {
    switch (this) {
      case CanvasExpandMode.rectangular:
        return '사각 확장';
      case CanvasExpandMode.free:
        return '자유 확장';
    }
  }
}

/// 호버 시 다른 사용자 커서/닉네임 표시 범위
enum HoverVisibility {
  all,    // 전체
  friends, // 친구만
  off,    // 표시 안 함
}

extension HoverVisibilityX on HoverVisibility {
  String get displayName {
    switch (this) {
      case HoverVisibility.all:
        return '전체';
      case HoverVisibility.friends:
        return '친구만';
      case HoverVisibility.off:
        return '끄기';
    }
  }
}

/// 앱 로컬 설정 서비스 (SharedPreferences)
class SettingsService {
  static const _keyNotificationsEnabled = 'notifications_enabled';
  static const _keyNotificationSound = 'notification_sound';
  static const _keyCanvasExpandMode = 'canvas_expand_mode';
  static const _keyHoverVisibility = 'hover_visibility';
  static const _keyThemeMode = 'theme_mode'; // 'light' | 'dark' | 'system'
  static const _keyDefaultPenColor = 'default_pen_color'; // int (Color.value)
  static const _keyDefaultPenWidth = 'default_pen_width'; // double

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _prefsAsync async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 알림 사용 여부
  Future<bool> getNotificationsEnabled() async {
    final prefs = await _prefsAsync;
    return prefs.getBool(_keyNotificationsEnabled) ?? true;
  }

  Future<void> setNotificationsEnabled(bool value) async {
    final prefs = await _prefsAsync;
    await prefs.setBool(_keyNotificationsEnabled, value);
  }

  /// 알림 소리 여부
  Future<bool> getNotificationSound() async {
    final prefs = await _prefsAsync;
    return prefs.getBool(_keyNotificationSound) ?? true;
  }

  Future<void> setNotificationSound(bool value) async {
    final prefs = await _prefsAsync;
    await prefs.setBool(_keyNotificationSound, value);
  }

  /// 캔버스 확장 방식
  Future<CanvasExpandMode> getCanvasExpandMode() async {
    final prefs = await _prefsAsync;
    final name = prefs.getString(_keyCanvasExpandMode);
    if (name == null) return CanvasExpandMode.rectangular;
    return CanvasExpandMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => CanvasExpandMode.rectangular,
    );
  }

  Future<void> setCanvasExpandMode(CanvasExpandMode value) async {
    final prefs = await _prefsAsync;
    await prefs.setString(_keyCanvasExpandMode, value.name);
  }

  /// 호버 시 다른 사용자 커서/닉네임 표시 (친구만/전체/OFF)
  Future<HoverVisibility> getHoverVisibility() async {
    final prefs = await _prefsAsync;
    final name = prefs.getString(_keyHoverVisibility);
    if (name == null) return HoverVisibility.all;
    return HoverVisibility.values.firstWhere(
      (e) => e.name == name,
      orElse: () => HoverVisibility.all,
    );
  }

  Future<void> setHoverVisibility(HoverVisibility value) async {
    final prefs = await _prefsAsync;
    await prefs.setString(_keyHoverVisibility, value.name);
  }

  /// 테마 모드 (light / dark / system)
  Future<String> getThemeMode() async {
    final prefs = await _prefsAsync;
    return prefs.getString(_keyThemeMode) ?? 'system';
  }

  Future<void> setThemeMode(String value) async {
    final prefs = await _prefsAsync;
    await prefs.setString(_keyThemeMode, value);
  }

  /// 기본 펜 색상 (캔버스 진입 시 펜1에 적용). null이면 앱 기본값(검정) 사용.
  Future<int?> getDefaultPenColorValue() async {
    final prefs = await _prefsAsync;
    return prefs.getInt(_keyDefaultPenColor);
  }

  Future<void> setDefaultPenColorValue(int value) async {
    final prefs = await _prefsAsync;
    await prefs.setInt(_keyDefaultPenColor, value);
  }

  /// 기본 펜 굵기 (1.0 ~ 24.0). null이면 앱 기본값(2.0) 사용.
  Future<double?> getDefaultPenWidth() async {
    final prefs = await _prefsAsync;
    return prefs.getDouble(_keyDefaultPenWidth);
  }

  Future<void> setDefaultPenWidth(double value) async {
    final prefs = await _prefsAsync;
    await prefs.setDouble(_keyDefaultPenWidth, value.clamp(1.0, 24.0));
  }
}
