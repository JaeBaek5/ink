import 'package:flutter/material.dart';

/// INK 앱 색상 팔레트 (종이 + 만년필 잉크 컨셉)
class AppColors {
  AppColors._();

  // ========== 기본 팔레트 ==========
  
  /// 배경 (Paper)
  static const Color paper = Color(0xFFFAF7F0);
  
  /// 메뉴/텍스트 기본 (Ink)
  static const Color ink = Color(0xFF0F172A);
  
  /// 선택/강조 (펜촉 Gold)
  static const Color gold = Color(0xFFB08D57);
  
  /// 비활성/보조 (Muted Gray)
  static const Color mutedGray = Color(0xFF94A3B8);
  
  /// 구분선/테두리 (연한 선)
  static const Color border = Color(0xFFE5E7EB);

  // ========== 다크 모드 ==========
  
  /// 다크 배경
  static const Color darkBackground = Color(0xFF0B1220);
  
  /// 다크 텍스트
  static const Color darkText = Color(0xFFE5E7EB);
  
  /// 다크 비활성
  static const Color darkMuted = Color(0xFF64748B);
}
