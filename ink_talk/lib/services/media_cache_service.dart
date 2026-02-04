import 'package:flutter/foundation.dart';

/// 미디어 URL 캐시 (썸네일/원본 우선 로딩용 인메모리 캐시)
/// 키: mediaId 또는 url, 값: 로드 완료 여부만 기록해 중복 요청 완화
class MediaCacheService extends ChangeNotifier {
  final Set<String> _loadedThumbnails = {};
  final Set<String> _loadedFullUrls = {};

  bool hasLoadedThumbnail(String key) => _loadedThumbnails.contains(key);
  bool hasLoadedFull(String key) => _loadedFullUrls.contains(key);

  void markThumbnailLoaded(String key) {
    if (_loadedThumbnails.add(key)) notifyListeners();
  }

  void markFullLoaded(String key) {
    if (_loadedFullUrls.add(key)) notifyListeners();
  }

  void clear() {
    if (_loadedThumbnails.isNotEmpty || _loadedFullUrls.isNotEmpty) {
      _loadedThumbnails.clear();
      _loadedFullUrls.clear();
      notifyListeners();
    }
  }
}
