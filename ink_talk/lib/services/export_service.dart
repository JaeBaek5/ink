import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 내보내기 포맷
enum ExportFormat {
  png,
  jpg,
  pdf,
}

/// 내보내기 범위
enum ExportRange {
  full,    // 전체
  partial, // 부분 (선택 영역)
}

/// 내보내기 서비스
class ExportService {
  /// 캔버스를 이미지로 캡처
  Future<Uint8List?> captureCanvas(GlobalKey canvasKey) async {
    try {
      final boundary = canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('캔버스 캡처 실패: $e');
      return null;
    }
  }

  /// PNG로 내보내기
  Future<File?> exportToPng({
    required Uint8List imageData,
    required String fileName,
    String? watermarkText,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName.png';
      
      // 워터마크 추가 (선택적)
      final finalData = watermarkText != null
          ? await _addWatermark(imageData, watermarkText)
          : imageData;
      
      final file = File(filePath);
      await file.writeAsBytes(finalData);
      return file;
    } catch (e) {
      debugPrint('PNG 내보내기 실패: $e');
      return null;
    }
  }

  /// JPG로 내보내기
  Future<File?> exportToJpg({
    required Uint8List imageData,
    required String fileName,
    String? watermarkText,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName.jpg';
      
      final finalData = watermarkText != null
          ? await _addWatermark(imageData, watermarkText)
          : imageData;
      
      final file = File(filePath);
      await file.writeAsBytes(finalData);
      return file;
    } catch (e) {
      debugPrint('JPG 내보내기 실패: $e');
      return null;
    }
  }

  /// PDF로 내보내기
  Future<File?> exportToPdf({
    required Uint8List imageData,
    required String fileName,
    String? watermarkText,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName.pdf';

      final pdf = pw.Document();
      final image = pw.MemoryImage(imageData);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Stack(
              children: [
                pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
                if (watermarkText != null)
                  pw.Positioned(
                    bottom: 10,
                    right: 10,
                    child: pw.Text(
                      watermarkText,
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );

      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      return file;
    } catch (e) {
      debugPrint('PDF 내보내기 실패: $e');
      return null;
    }
  }

  /// 파일 공유
  Future<void> shareFile(File file, {String? subject}) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: subject ?? 'INK 캔버스',
      );
    } catch (e) {
      debugPrint('파일 공유 실패: $e');
    }
  }

  /// 링크 공유 (동적 링크 생성)
  Future<String?> createShareLink({
    required String roomId,
    required String userId,
  }) async {
    // TODO: Firebase Dynamic Links 또는 직접 URL 생성
    // 현재는 앱 딥링크 형태로 반환
    final link = 'https://ink.app/room/$roomId?ref=$userId';
    return link;
  }

  /// 링크 공유
  Future<void> shareLink(String link, {String? message}) async {
    try {
      await Share.share(
        message ?? '함께 그려요! $link',
        subject: 'INK 초대',
      );
    } catch (e) {
      debugPrint('링크 공유 실패: $e');
    }
  }

  /// 워터마크 추가 (간단 버전)
  Future<Uint8List> _addWatermark(Uint8List imageData, String text) async {
    // 실제 구현은 이미지 편집 라이브러리 필요
    // 현재는 원본 반환
    return imageData;
  }
}
