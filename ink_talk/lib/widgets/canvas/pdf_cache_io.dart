import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 캐시에 있으면 PDF 바이트 반환(방 나갔다 와도 재다운로드 없음), 없으면 null
Future<Uint8List?> getPdfBytesFromCache(String url) async {
  try {
    final fileInfo = await DefaultCacheManager().getFileFromCache(url);
    if (fileInfo != null) return await fileInfo.file.readAsBytes();
    return null;
  } catch (_) {
    return null;
  }
}

/// 다운로드한 PDF 바이트를 캐시에 저장 → 다음 진입 시 즉시 로드
void cachePdfBytes(String url, List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  unawaited(
    DefaultCacheManager().putFile(url, data, fileExtension: 'pdf'),
  );
}
