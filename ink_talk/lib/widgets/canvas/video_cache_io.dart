import 'dart:async';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

/// 캐시에 이미 있으면 로컬 파일로 재생(즉시), 없으면 null → 네트워크 스트리밍(첫 재생 빠름)
Future<VideoPlayerController?> createVideoControllerFromCache(String url) async {
  try {
    final fileInfo = await DefaultCacheManager().getFileFromCache(url);
    if (fileInfo != null) return VideoPlayerController.file(fileInfo.file);
    return null;
  } catch (_) {
    return null;
  }
}

/// 네트워크 재생 중 백그라운드로 캐시 저장 → 다음 재생 시 로컬 재생
void cacheVideoInBackground(String url) {
  unawaited(DefaultCacheManager().getSingleFile(url));
}
