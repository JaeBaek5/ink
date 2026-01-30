import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: GestureDetector(
        // 핀치 줌
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: ClipRect(
          child: CustomPaint(
            painter: _CanvasPainter(
              strokes: widget.controller.strokes,
              currentStroke: widget.controller.currentStroke,
              offset: widget.controller.canvasOffset,
              scale: widget.controller.canvasScale,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _currentInputKind = event.kind;

    // 패드에서 손가락은 이동/선택, 펜은 그리기
    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    if (isStylus || event.kind == PointerDeviceKind.mouse) {
      // 펜 또는 마우스: 그리기
      final localPoint = _transformPoint(event.localPosition);
      widget.controller.startStroke(localPoint, widget.userId);
    }
    // 터치는 제스처로 처리 (이동/줌)
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentInputKind == null) return;

    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;

    if (isStylus || _currentInputKind == PointerDeviceKind.mouse) {
      final localPoint = _transformPoint(event.localPosition);
      widget.controller.updateStroke(localPoint);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;

    if (isStylus || _currentInputKind == PointerDeviceKind.mouse) {
      widget.controller.endStroke();
    }

    _currentInputKind = null;
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
  final List<StrokeData> strokes;
  final StrokeData? currentStroke;
  final Offset offset;
  final double scale;

  _CanvasPainter({
    required this.strokes,
    this.currentStroke,
    required this.offset,
    required this.scale,
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

    // 격자 그리기 (선택적)
    _drawGrid(canvas, size);

    // 완료된 스트로크 그리기
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, stroke.isConfirmed ? 1.0 : 0.5);
    }

    // 현재 그리는 중인 스트로크
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!, 0.7);
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

  void _drawStroke(Canvas canvas, StrokeData stroke, double opacity) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color.withValues(alpha: opacity)
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      // 점
      canvas.drawCircle(
        stroke.points.first,
        stroke.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
    } else {
      // 선
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
    return true; // 항상 다시 그리기 (최적화 필요 시 수정)
  }
}
