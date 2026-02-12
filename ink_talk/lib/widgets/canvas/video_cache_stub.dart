import 'package:video_player/video_player.dart';

/// 웹 등 dart:io 미지원 환경: 캐시 없이 null 반환 → 네트워크 재생 사용
Future<VideoPlayerController?> createVideoControllerFromCache(String url) async {
  return null;
}

/// 웹: no-op
void cacheVideoInBackground(String url) {}
