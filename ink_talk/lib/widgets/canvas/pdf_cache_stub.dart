/// 웹 등 dart:io 미지원 환경: PDF 캐시 없음
Future<List<int>?> getPdfBytesFromCache(String url) async => null;

void cachePdfBytes(String url, List<int> bytes) {}
