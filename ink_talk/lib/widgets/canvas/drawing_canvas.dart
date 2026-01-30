import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/stroke_model.dart';
import '../../screens/canvas/canvas_controller.dart';

/// 드로잉 캔버스 위젯
class DrawingCanvas extends StatefulWidget {
  final CanvasController controller;
  final String userId;
  final String roomId;

  const DrawingCanvas({
    super.key,
    required this.controller,
    required this.userId,
    required this.roomId,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  // 입력 타입 (손가락 vs 스타일러스)
  PointerDeviceKind? _currentInputKind;

  // 작성자 툴팁
  String? _hoveredAuthorName;
  Offset? _hoveredPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerHover: _onPointerHover,
      child: GestureDetector(
        // 핀치 줌
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        // 짧은 탭 (작성자 표시)
        onTapUp: _onTapUp,
        child: Stack(
          children: [
            // 캔버스
            ClipRect(
              child: CustomPaint(
                painter: _CanvasPainter(
                  serverStrokes: widget.controller.serverStrokes,
                  localStrokes: widget.controller.localStrokes,
                  currentStroke: widget.controller.currentStroke,
                  ghostStrokes: widget.controller.ghostStrokes.values.toList(),
                  offset: widget.controller.canvasOffset,
                  scale: widget.controller.canvasScale,
                  currentUserId: widget.userId,
                ),
                size: Size.infinite,
              ),
            ),

            // 작성자 툴팁
            if (_hoveredAuthorName != null && _hoveredPosition != null)
              Positioned(
                left: _hoveredPosition!.dx + 10,
                top: _hoveredPosition!.dy - 30,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.ink.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _hoveredAuthorName!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _currentInputKind = event.kind;
    _clearTooltip();

    // 펜 전용 모드 확인
    final penOnlyMode = widget.controller.penOnlyMode;

    // 패드에서 손가락은 이동/선택, 펜은 그리기
    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    // penOnlyMode가 꺼져있으면 마우스/터치도 그리기 가능
    final canDraw = isStylus || 
        (!penOnlyMode && (event.kind == PointerDeviceKind.mouse || event.kind == PointerDeviceKind.touch));

    if (canDraw) {
      final localPoint = _transformPoint(event.localPosition);
      widget.controller.startStroke(localPoint);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentInputKind == null) return;

    final penOnlyMode = widget.controller.penOnlyMode;
    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;

    final canDraw = isStylus || 
        (!penOnlyMode && (_currentInputKind == PointerDeviceKind.mouse || _currentInputKind == PointerDeviceKind.touch));

    if (canDraw) {
      final localPoint = _transformPoint(event.localPosition);
      widget.controller.updateStroke(localPoint);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final penOnlyMode = widget.controller.penOnlyMode;
    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;

    final canDraw = isStylus || 
        (!penOnlyMode && (_currentInputKind == PointerDeviceKind.mouse || _currentInputKind == PointerDeviceKind.touch));

    if (canDraw) {
      widget.controller.endStroke();
    }

    _currentInputKind = null;
  }

  /// 펜 호버 (패드에서 작성자 표시)
  void _onPointerHover(PointerHoverEvent event) {
    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    if (!isStylus) return;

    final localPoint = _transformPoint(event.localPosition);
    _checkAuthorAtPoint(localPoint, event.localPosition);
  }

  /// 짧은 탭 (폰에서 작성자 표시)
  void _onTapUp(TapUpDetails details) {
    final localPoint = _transformPoint(details.localPosition);
    _checkAuthorAtPoint(localPoint, details.localPosition);
  }

  void _checkAuthorAtPoint(Offset canvasPoint, Offset screenPosition) {
    const hitRadius = 20.0;
    String? authorName;

    // 서버 스트로크에서 찾기
    for (final stroke in widget.controller.serverStrokes.reversed) {
      for (final p in stroke.points) {
        final offset = Offset(p.x, p.y);
        if ((offset - canvasPoint).distance < hitRadius) {
          // TODO: 실제 사용자 이름 조회
          authorName = '사용자 ${stroke.senderId.substring(0, 6)}';
          break;
        }
      }
      if (authorName != null) break;
    }

    // 로컬 스트로크에서 찾기
    if (authorName == null) {
      for (final stroke in widget.controller.localStrokes.reversed) {
        for (final p in stroke.points) {
          if ((p - canvasPoint).distance < hitRadius) {
            authorName = stroke.senderName ?? '사용자 ${stroke.senderId.substring(0, 6)}';
            break;
          }
        }
        if (authorName != null) break;
      }
    }

    setState(() {
      _hoveredAuthorName = authorName;
      _hoveredPosition = authorName != null ? screenPosition : null;
    });

    // 2초 후 툴팁 숨김
    if (authorName != null) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _hoveredAuthorName = null;
            _hoveredPosition = null;
          });
        }
      });
    }
  }

  void _clearTooltip() {
    if (_hoveredAuthorName != null) {
      setState(() {
        _hoveredAuthorName = null;
        _hoveredPosition = null;
      });
    }
  }

  // 핀치 줌 상태
  double _baseScale = 1.0;

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = widget.controller.canvasScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 1) {
      // 한 손가락: 이동
      widget.controller.pan(details.focalPointDelta);
    } else if (details.pointerCount == 2) {
      // 두 손가락: 줌
      widget.controller.zoom(
        details.scale / _baseScale * widget.controller.canvasScale / widget.controller.canvasScale,
        details.localFocalPoint,
      );
      _baseScale = details.scale;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // 줌 종료
  }

  /// 화면 좌표를 캔버스 좌표로 변환
  Offset _transformPoint(Offset screenPoint) {
    return (screenPoint - widget.controller.canvasOffset) / widget.controller.canvasScale;
  }
}

/// 캔버스 페인터
class _CanvasPainter extends CustomPainter {
  final List<StrokeModel> serverStrokes;
  final List<LocalStrokeData> localStrokes;
  final LocalStrokeData? currentStroke;
  final List<LocalStrokeData> ghostStrokes;
  final Offset offset;
  final double scale;
  final String currentUserId;

  _CanvasPainter({
    required this.serverStrokes,
    required this.localStrokes,
    this.currentStroke,
    required this.ghostStrokes,
    required this.offset,
    required this.scale,
    required this.currentUserId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 배경
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.paper,
    );

    // 변환 적용
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    // 격자 그리기
    _drawGrid(canvas, size);

    // 서버 스트로크 (확정된 것)
    for (final stroke in serverStrokes) {
      _drawServerStroke(canvas, stroke);
    }

    // 로컬 스트로크 (아직 확정 안 된 것 - 고스트)
    for (final stroke in localStrokes) {
      final opacity = stroke.isConfirmed ? 1.0 : 0.6;
      _drawLocalStroke(canvas, stroke, opacity);
    }

    // 다른 사용자의 고스트 스트로크
    for (final stroke in ghostStrokes) {
      _drawLocalStroke(canvas, stroke, 0.4);
    }

    // 현재 그리는 중인 스트로크
    if (currentStroke != null) {
      _drawLocalStroke(canvas, currentStroke!, 0.7);
    }

    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    const gridSize = 50.0;
    final visibleRect = Rect.fromLTWH(
      -offset.dx / scale,
      -offset.dy / scale,
      size.width / scale,
      size.height / scale,
    );

    // 세로선
    for (double x = (visibleRect.left / gridSize).floor() * gridSize;
        x < visibleRect.right;
        x += gridSize) {
      canvas.drawLine(
        Offset(x, visibleRect.top),
        Offset(x, visibleRect.bottom),
        gridPaint,
      );
    }

    // 가로선
    for (double y = (visibleRect.top / gridSize).floor() * gridSize;
        y < visibleRect.bottom;
        y += gridSize) {
      canvas.drawLine(
        Offset(visibleRect.left, y),
        Offset(visibleRect.right, y),
        gridPaint,
      );
    }
  }

  void _drawServerStroke(Canvas canvas, StrokeModel stroke) {
    if (stroke.points.isEmpty) return;

    // HEX 색상 파싱
    final colorHex = stroke.style.color.replaceAll('#', '');
    final colorValue = int.parse(colorHex, radix: 16);
    final color = Color(colorValue | 0xFF000000);

    final opacity = stroke.isConfirmed ? 1.0 : 0.6;

    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = stroke.style.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        Offset(stroke.points.first.x, stroke.points.first.y),
        stroke.style.width / 2,
        paint..style = PaintingStyle.fill,
      );
    } else {
      final path = Path();
      path.moveTo(stroke.points.first.x, stroke.points.first.y);

      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].x, stroke.points[i].y);
      }

      canvas.drawPath(path, paint);
    }
  }

  void _drawLocalStroke(Canvas canvas, LocalStrokeData stroke, double opacity) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color.withValues(alpha: opacity)
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first,
        stroke.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
    } else {
      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return true;
  }
}
