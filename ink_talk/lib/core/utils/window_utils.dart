import 'package:flutter/material.dart';

/// 멀티 윈도우 / 분할 화면 유틸
///
/// - Android: resizeableActivity="true"로 분할 화면 시 창 크기 변경 수신
/// - iOS: iPad 분할 화면 시 단일 윈도우 크기만 변경됨 (MediaQuery 갱신)
/// - 레이아웃은 MediaQuery.size에 반응하므로 분할 시 자동으로 컴팩트 레이아웃 적용 가능
class WindowUtils {
  WindowUtils._();

  /// 분할 화면 등으로 창이 좁아졌을 때 true (폰 세로와 유사한 너비)
  static bool isCompactWindow(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width < 600;
  }

  /// 현재 창 크기 (분할/풀스크린 모두 반영)
  static Size windowSize(BuildContext context) {
    return MediaQuery.sizeOf(context);
  }

  /// 멀티 윈도우 환경에서 창 크기 변경 시 리빌드되도록 MediaQuery에 의존
  static bool get isMultiWindowCapable => true;
}
