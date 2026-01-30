import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// INK 앱 테마
class AppTheme {
  AppTheme._();

  /// 라이트 테마
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    
    // 색상 스키마
    colorScheme: const ColorScheme.light(
      primary: AppColors.ink,
      secondary: AppColors.gold,
      surface: AppColors.paper,
      onPrimary: AppColors.paper,
      onSecondary: AppColors.paper,
      onSurface: AppColors.ink,
    ),
    
    // 배경색
    scaffoldBackgroundColor: AppColors.paper,
    
    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    
    // BottomNavigationBar
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.paper,
      selectedItemColor: AppColors.ink,
      unselectedItemColor: AppColors.mutedGray,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    
    // ElevatedButton
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    
    // OutlinedButton
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    
    // Divider
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
    ),
  );

  /// 다크 테마
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    
    colorScheme: const ColorScheme.dark(
      primary: AppColors.darkText,
      secondary: AppColors.gold,
      surface: AppColors.darkBackground,
      onPrimary: AppColors.darkBackground,
      onSecondary: AppColors.darkBackground,
      onSurface: AppColors.darkText,
    ),
    
    scaffoldBackgroundColor: AppColors.darkBackground,
    
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBackground,
      foregroundColor: AppColors.darkText,
      elevation: 0,
      centerTitle: true,
    ),
    
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkBackground,
      selectedItemColor: AppColors.darkText,
      unselectedItemColor: AppColors.darkMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}
