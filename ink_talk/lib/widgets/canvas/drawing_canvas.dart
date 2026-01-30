import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/message_model.dart';
import '../../models/media_model.dart';
import '../../models/shape_model.dart';
import '../../models/stroke_model.dart';
import '../../screens/canvas/canvas_controller.dart';
import 'media_widget.dart';
import 'timeline_navigator.dart';

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

  // 현재 이벤트 인덱스 (이벤트 단위 이동용)
  int _currentEventIndex = 0;

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
        // 짧은 탭 (텍스트 입력 또는 작성자 표시)
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
                  serverShapes: widget.controller.serverShapes,
                  currentShapeStart: widget.controller.shapeStartPoint,
                  currentShapeEnd: widget.controller.shapeEndPoint,
                  currentShapeType: widget.controller.currentShapeType,
                  shapeStrokeColor: widget.controller.shapeStrokeColor,
                  shapeStrokeWidth: widget.controller.shapeStrokeWidth,
                  shapeFillColor: widget.controller.shapeFillColor,
                  shapeLineStyle: widget.controller.shapeLineStyle,
                  selectedShape: widget.controller.selectedShape,
                  offset: widget.controller.canvasOffset,
                  scale: widget.controller.canvasScale,
                  currentUserId: widget.userId,
                  snapEnabled: widget.controller.snapEnabled,
                  gridSize: CanvasController.gridSize,
                ),
                size: Size.infinite,
              ),
            ),

            // 미디어 오브젝트 렌더링
            ...widget.controller.serverMedia.map((media) => MediaWidget(
              key: ValueKey(media.id),
              media: media,
              isSelected: widget.controller.selectedMedia?.id == media.id,
              canvasOffset: widget.controller.canvasOffset,
              canvasScale: widget.controller.canvasScale,
              onTap: () => widget.controller.selectMedia(media),
              onLongPress: () => _showMediaOptions(context, media),
              onMove: (delta) => widget.controller.moveMedia(media.id, delta),
            )),

            // 텍스트 오브젝트 렌더링
            ...widget.controller.serverTexts.map((text) => _buildTextWidget(text)),

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

            // 시간순 네비게이션 바 (우측)
            Positioned(
              right: 8,
              top: 60,
              bottom: 100,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return TimelineNavigator(
                    strokes: widget.controller.serverStrokes,
                    texts: widget.controller.serverTexts,
                    media: widget.controller.serverMedia,
                    onJump: (position) {
                      final renderBox = context.findRenderObject() as RenderBox?;
                      final size = renderBox?.size ?? const Size(400, 600);
                      widget.controller.jumpToPosition(position, size);
                    },
                  );
                },
              ),
            ),

            // 이벤트 이동 화살표 (우측 하단)
            Positioned(
              right: 8,
              bottom: 16,
              child: _buildEventNavigationButtons(),
            ),
          ],
        ),
      ),
    );
  }

  /// 텍스트 위젯 빌드
  Widget _buildTextWidget(MessageModel text) {
    final offset = widget.controller.canvasOffset;
    final scale = widget.controller.canvasScale;
    
    final screenX = (text.positionX ?? 0) * scale + offset.dx;
    final screenY = (text.positionY ?? 0) * scale + offset.dy;

    return Positioned(
      left: screenX,
      top: screenY,
      child: GestureDetector(
        onLongPress: () => _showTextOptions(text),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text.content ?? '',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 16 * scale,
            ),
          ),
        ),
      ),
    );
  }

  /// 텍스트 옵션 메뉴
  void _showTextOptions(MessageModel text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('삭제', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  widget.controller.deleteText(text.id);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// 미디어 옵션 메뉴 (롱프레스)
  void _showMediaOptions(BuildContext context, MediaModel media) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Stack(
          children: [
            // Dim 배경
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
            // 옵션 메뉴
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // 투명도 조절
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.opacity, color: AppColors.ink),
                            const SizedBox(width: 12),
                            const Text('투명도'),
                            Expanded(
                              child: StatefulBuilder(
                                builder: (context, setState) {
                                  double opacity = media.opacity;
                                  return Slider(
                                    value: opacity,
                                    min: 0.1,
                                    max: 1.0,
                                    activeColor: AppColors.gold,
                                    onChanged: (value) {
                                      setState(() => opacity = value);
                                    },
                                    onChangeEnd: (value) {
                                      widget.controller.setMediaOpacity(media.id, value);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.flip_to_front, color: AppColors.ink),
                        title: const Text('앞으로'),
                        onTap: () {
                          Navigator.pop(context);
                          widget.controller.bringMediaToFront(media.id);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.flip_to_back, color: AppColors.ink),
                        title: const Text('뒤로'),
                        onTap: () {
                          Navigator.pop(context);
                          widget.controller.sendMediaToBack(media.id);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.delete_outline, color: Colors.red),
                        title: const Text('삭제', style: TextStyle(color: Colors.red)),
                        onTap: () {
                          Navigator.pop(context);
                          widget.controller.deleteMedia(media.id);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 이벤트 단위 이동 버튼
  Widget _buildEventNavigationButtons() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 이전 이벤트
          IconButton(
            onPressed: _goToPreviousEvent,
            icon: const Icon(Icons.keyboard_arrow_up),
            iconSize: 24,
            color: AppColors.ink,
            tooltip: '이전 이벤트',
          ),
          Container(
            width: 20,
            height: 1,
            color: AppColors.border,
          ),
          // 다음 이벤트
          IconButton(
            onPressed: _goToNextEvent,
            icon: const Icon(Icons.keyboard_arrow_down),
            iconSize: 24,
            color: AppColors.ink,
            tooltip: '다음 이벤트',
          ),
        ],
      ),
    );
  }

  /// 모든 이벤트 목록 가져오기
  List<_TimelineEvent> _getAllEvents() {
    final events = <_TimelineEvent>[];

    // 스트로크
    for (final stroke in widget.controller.serverStrokes) {
      if (stroke.points.isNotEmpty) {
        events.add(_TimelineEvent(
          x: stroke.points.first.x,
          y: stroke.points.first.y,
          timestamp: stroke.createdAt,
        ));
      }
    }

    // 텍스트
    for (final text in widget.controller.serverTexts) {
      events.add(_TimelineEvent(
        x: text.positionX ?? 0,
        y: text.positionY ?? 0,
        timestamp: text.createdAt,
      ));
    }

    // 미디어
    for (final m in widget.controller.serverMedia) {
      events.add(_TimelineEvent(
        x: m.x,
        y: m.y,
        timestamp: m.createdAt,
      ));
    }

    // 시간순 정렬
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return events;
  }

  /// 이전 이벤트로 이동
  void _goToPreviousEvent() {
    final events = _getAllEvents();
    if (events.isEmpty) return;

    setState(() {
      _currentEventIndex = (_currentEventIndex - 1).clamp(0, events.length - 1);
    });

    final event = events[_currentEventIndex];
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(400, 600);
    widget.controller.jumpToPosition(Offset(event.x, event.y), size);
  }

  /// 다음 이벤트로 이동
  void _goToNextEvent() {
    final events = _getAllEvents();
    if (events.isEmpty) return;

    setState(() {
      _currentEventIndex = (_currentEventIndex + 1).clamp(0, events.length - 1);
    });

    final event = events[_currentEventIndex];
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(400, 600);
    widget.controller.jumpToPosition(Offset(event.x, event.y), size);
  }

  void _onPointerDown(PointerDownEvent event) {
    _currentInputKind = event.kind;
    _clearTooltip();

    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    if (isStylus || event.kind == PointerDeviceKind.mouse) {
      final localPoint = _transformPoint(event.localPosition);
      
      // 도형 모드
      if (widget.controller.inputMode == InputMode.shape) {
        widget.controller.startShape(localPoint);
        return;
      }
      
      // 펜 모드
      widget.controller.startStroke(localPoint);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentInputKind == null) return;

    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;

    if (isStylus || _currentInputKind == PointerDeviceKind.mouse) {
      final localPoint = _transformPoint(event.localPosition);
      
      // 도형 모드
      if (widget.controller.inputMode == InputMode.shape) {
        widget.controller.updateShape(localPoint);
        return;
      }
      
      widget.controller.updateStroke(localPoint);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;

    if (isStylus || _currentInputKind == PointerDeviceKind.mouse) {
      // 도형 모드
      if (widget.controller.inputMode == InputMode.shape) {
        widget.controller.endShape();
        _currentInputKind = null;
        return;
      }
      
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
    
    // 텍스트 입력 모드
    if (widget.controller.inputMode == InputMode.text) {
      _showTextInputDialog(localPoint);
      return;
    }
    
    // 작성자 표시
    _checkAuthorAtPoint(localPoint, details.localPosition);
  }

  /// 텍스트 입력 다이얼로그
  void _showTextInputDialog(Offset position) {
    final textController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('텍스트 입력'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '텍스트를 입력하세요',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                widget.controller.addText(value, position);
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                if (textController.text.isNotEmpty) {
                  widget.controller.addText(textController.text, position);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
              ),
              child: const Text('추가'),
            ),
          ],
        );
      },
    );
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
  final List<ShapeModel> serverShapes;
  final Offset? currentShapeStart;
  final Offset? currentShapeEnd;
  final ShapeType currentShapeType;
  final String shapeStrokeColor;
  final double shapeStrokeWidth;
  final String? shapeFillColor;
  final LineStyle shapeLineStyle;
  final ShapeModel? selectedShape;
  final Offset offset;
  final double scale;
  final String currentUserId;
  final bool snapEnabled;
  final double gridSize;

  _CanvasPainter({
    required this.serverStrokes,
    required this.localStrokes,
    this.currentStroke,
    required this.ghostStrokes,
    required this.serverShapes,
    this.currentShapeStart,
    this.currentShapeEnd,
    required this.currentShapeType,
    required this.shapeStrokeColor,
    required this.shapeStrokeWidth,
    this.shapeFillColor,
    required this.shapeLineStyle,
    this.selectedShape,
    required this.offset,
    required this.scale,
    required this.currentUserId,
    required this.snapEnabled,
    required this.gridSize,
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

    // 서버 도형
    for (final shape in serverShapes) {
      _drawShape(canvas, shape, shape == selectedShape);
    }

    // 현재 그리는 중인 도형
    if (currentShapeStart != null && currentShapeEnd != null) {
      _drawCurrentShape(canvas);
    }

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

  void _drawShape(Canvas canvas, ShapeModel shape, bool isSelected) {
    final strokeColor = _parseColor(shape.strokeColor);
    final fillColor = shape.fillColor != null ? _parseColor(shape.fillColor!) : null;

    final strokePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = shape.strokeWidth
      ..style = PaintingStyle.stroke;

    // 선 스타일
    if (shape.lineStyle == LineStyle.dashed) {
      strokePaint.strokeWidth = shape.strokeWidth;
    }

    final fillPaint = fillColor != null
        ? (Paint()
          ..color = fillColor.withValues(alpha: shape.fillOpacity)
          ..style = PaintingStyle.fill)
        : null;

    final start = Offset(shape.startX, shape.startY);
    final end = Offset(shape.endX, shape.endY);

    switch (shape.type) {
      case ShapeType.line:
        canvas.drawLine(start, end, strokePaint);
        break;
      case ShapeType.arrow:
        _drawArrow(canvas, start, end, strokePaint);
        break;
      case ShapeType.rectangle:
        final rect = Rect.fromPoints(start, end);
        if (fillPaint != null) canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);
        break;
      case ShapeType.ellipse:
        final rect = Rect.fromPoints(start, end);
        if (fillPaint != null) canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, strokePaint);
        break;
    }

    // 선택된 도형 표시
    if (isSelected) {
      final selectionPaint = Paint()
        ..color = AppColors.gold
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final rect = Rect.fromPoints(start, end).inflate(5);
      canvas.drawRect(rect, selectionPaint);

      // 핸들
      _drawHandle(canvas, rect.topLeft);
      _drawHandle(canvas, rect.topRight);
      _drawHandle(canvas, rect.bottomLeft);
      _drawHandle(canvas, rect.bottomRight);
    }
  }

  void _drawCurrentShape(Canvas canvas) {
    final strokeColor = _parseColor(shapeStrokeColor);
    final fillColor = shapeFillColor != null ? _parseColor(shapeFillColor!) : null;

    final strokePaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.7)
      ..strokeWidth = shapeStrokeWidth
      ..style = PaintingStyle.stroke;

    final fillPaint = fillColor != null
        ? (Paint()
          ..color = fillColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill)
        : null;

    final start = currentShapeStart!;
    final end = currentShapeEnd!;

    switch (currentShapeType) {
      case ShapeType.line:
        canvas.drawLine(start, end, strokePaint);
        break;
      case ShapeType.arrow:
        _drawArrow(canvas, start, end, strokePaint);
        break;
      case ShapeType.rectangle:
        final rect = Rect.fromPoints(start, end);
        if (fillPaint != null) canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);
        break;
      case ShapeType.ellipse:
        final rect = Rect.fromPoints(start, end);
        if (fillPaint != null) canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, strokePaint);
        break;
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);

    // 화살표 머리
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    const arrowSize = 15.0;
    const arrowAngle = math.pi / 6;

    final path = Path();
    path.moveTo(end.dx, end.dy);
    path.lineTo(
      end.dx - arrowSize * math.cos(angle - arrowAngle),
      end.dy - arrowSize * math.sin(angle - arrowAngle),
    );
    path.moveTo(end.dx, end.dy);
    path.lineTo(
      end.dx - arrowSize * math.cos(angle + arrowAngle),
      end.dy - arrowSize * math.sin(angle + arrowAngle),
    );
    canvas.drawPath(path, paint);
  }

  void _drawHandle(Canvas canvas, Offset position) {
    final paint = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, 6, paint);
    
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(position, 6, borderPaint);
  }

  Color _parseColor(String hex) {
    final colorHex = hex.replaceAll('#', '');
    final colorValue = int.parse(colorHex, radix: 16);
    return Color(colorValue | 0xFF000000);
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

/// 이벤트 단위 이동용 간단한 이벤트 클래스
class _TimelineEvent {
  final double x;
  final double y;
  final DateTime timestamp;

  _TimelineEvent({
    required this.x,
    required this.y,
    required this.timestamp,
  });
}
