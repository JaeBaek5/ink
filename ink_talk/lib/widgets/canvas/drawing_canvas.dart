import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/media_model.dart';
import '../../models/message_model.dart';
import '../../models/tag_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/room_provider.dart';
import '../../services/tag_service.dart';
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
  /// 방장 설정: false면 타임라인 로그 비공개
  final bool logPublic;
  /// 내보내기 캡처용 (RepaintBoundary에 연결)
  final GlobalKey? repaintBoundaryKey;
  /// 태그 원본 점프 시 하이라이트할 영역 (캔버스 좌표, null이면 미표시)
  final Rect? highlightTagArea;

  const DrawingCanvas({
    super.key,
    required this.controller,
    required this.userId,
    required this.roomId,
    this.logPublic = true,
    this.repaintBoundaryKey,
    this.highlightTagArea,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

/// 단일 제스처 라우터: 이번 제스처의 타겟 (캔버스 vs 미디어)
enum _GestureTarget { canvas, media, none }

/// 오버레이 리사이즈 핸들 (캔버스 제스처보다 먼저 터치 받기 위함)
enum _OverlayResizeHandle { topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right }

class _DrawingCanvasState extends State<DrawingCanvas> {
  // 입력 타입 (손가락 vs 스타일러스)
  PointerDeviceKind? _currentInputKind;

  // 작성자 툴팁
  String? _hoveredAuthorName;
  Offset? _hoveredPosition;
  /// 영역 벗어난 뒤 이 시간 지나야 툴팁 지움 (깜박임 방지)
  Timer? _authorTooltipLeaveTimer;
  /// 2초 후 자동 숨김 (취소 가능)
  Timer? _authorTooltipAutoHideTimer;
  static const _authorLeaveDelay = Duration(milliseconds: 320);
  static const _authorAutoHideAfter = Duration(seconds: 2);

  // 현재 이벤트 인덱스 (이벤트 단위 이동용)
  int _currentEventIndex = 0;

  // 롱프레스 위치 (손글씨 태그 메뉴용)
  Offset? _longPressPosition;

  /// 지우개 호버 시 미리보기 위치 (null이면 미표시)
  Offset? _eraserHoverPosition;
  /// 펜이 멀어져 호버가 끊기면 미리보기 숨기기 위한 타이머
  Timer? _eraserHoverHideTimer;
  static const _eraserHoverHideDelay = Duration(milliseconds: 250);

  /// 단일 제스처 라우터: onScaleStart에서 캔버스/미디어 중 타겟 락 (S노트 스타일, 경쟁 제거)
  _GestureTarget _gestureTarget = _GestureTarget.none;
  String? _activeMediaId;

  /// 리사이즈 오버레이: 드래그 중인 핸들 및 시작 값 (캔버스 제스처 선점용)
  _OverlayResizeHandle? _overlayResizeHandle;
  double _overlayResizeStartWidth = 0;
  double _overlayResizeStartHeight = 0;
  double _overlayResizeStartX = 0;
  double _overlayResizeStartY = 0;
  Offset _overlayResizeStartLocal = Offset.zero;
  static const double _minMediaSize = 48.0;

  /// 회전 오버레이: 드래그 시작 시 각도 (rad), 미디어 각도(도)
  double? _rotateOverlayStartAngleRad;
  double? _rotateOverlayStartMediaDegrees;
  static const double _rotationHandleOffset = 36.0;

  @override
  void dispose() {
    _eraserHoverHideTimer?.cancel();
    _authorTooltipLeaveTimer?.cancel();
    _authorTooltipAutoHideTimer?.cancel();
    super.dispose();
  }

  /// 펜/지우개 모드이고 해당 미디어가 크기 조정 중이 아니면 true (포인터 무시 → 캔버스로 통과)
  bool _mediaIgnorePointer(String mediaId) {
    final pen = widget.controller.currentPen;
    final isDrawingTool = pen == PenType.pen1 || pen == PenType.pen2 || pen == PenType.fountain || pen == PenType.brush || pen == PenType.highlighter || pen == PenType.eraser;
    return isDrawingTool && !widget.controller.isMediaInResizeMode(mediaId);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onExit: (_) {
        _eraserHoverHideTimer?.cancel();
        setState(() => _eraserHoverPosition = null);
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerHover: _onPointerHover,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
            widget.controller.setViewportSize(viewportSize);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onTapUp: _onTapUp,
                  onLongPressStart: (details) => _longPressPosition = details.localPosition,
                  onLongPress: () {
                    final pos = _longPressPosition;
                    _longPressPosition = null;
                    if (pos != null) _onCanvasLongPress(pos);
                  },
                  onLongPressEnd: (_) => _longPressPosition = null,
                  child: RepaintBoundary(
                    key: widget.repaintBoundaryKey,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
            // 캔버스 (배경·격자·도형)
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
                          highlightTagRect: widget.highlightTagArea,
                          strokesOnly: false,
                        ),
                        size: Size.infinite,
                      ),
            ),

            // 미디어 오브젝트 렌더링 (url 없는 항목 제외 → 이미지 추가 직후 스트림 지연 시 빈 화면 방지)
            ...widget.controller.serverMedia
                .where((media) => media.url.isNotEmpty)
                .map((media) => MediaWidget(
              key: ValueKey(media.id),
              media: media,
              isSelected: widget.controller.selectedMedia?.id == media.id,
              isResizeMode: widget.controller.isMediaInResizeMode(media.id),
              canvasOffset: widget.controller.canvasOffset,
              canvasScale: widget.controller.canvasScale,
              onTap: () {
                if (widget.controller.selectedMedia?.id == media.id &&
                    widget.controller.isMediaInResizeMode(media.id)) {
                  _showMediaOptions(context, media);
                }
                // 탭으로는 선택 안 함 — 길게 눌러야 선택됨
              },
              onLongPress: () {
                widget.controller.selectMedia(media);
                widget.controller.enterMediaResizeMode(media.id);
              },
              onMove: (delta) => widget.controller.moveMedia(media.id, delta),
              onResize: (width, height, {x, y}) => widget.controller.resizeMedia(media.id, width, height, x: x, y: y),
              onResizeEnd: () => widget.controller.clearMediaResizeMode(),
              onRotate: (angleDegrees) => widget.controller.rotateMedia(media.id, angleDegrees),
              onSkew: (skewX, skewY) => widget.controller.skewMedia(media.id, skewX, skewY),
              ignorePointer: _mediaIgnorePointer(media.id),
            )),

            // 손글씨 스트로크 레이어 (미디어 위에 그려서 사진 위에 글씨 쓰기)
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
                  highlightTagRect: widget.highlightTagArea,
                  strokesOnly: true,
                ),
                size: Size.infinite,
              ),
            ),

            // 텍스트 오브젝트 렌더링
            ...widget.controller.serverTexts.map((text) => _buildTextWidget(text)),

            // 지우개 호버 미리보기 (지우개 선택 시 + 배럴 버튼 사용 시 범위 표시)
            if (_eraserHoverPosition != null)
              Positioned(
                left: _eraserHoverPosition!.dx -
                    widget.controller.eraserSize * widget.controller.canvasScale,
                top: _eraserHoverPosition!.dy -
                    widget.controller.eraserSize * widget.controller.canvasScale,
                child: IgnorePointer(
                  child: Container(
                    width: widget.controller.eraserSize *
                        2 *
                        widget.controller.canvasScale,
                    height: widget.controller.eraserSize *
                        2 *
                        widget.controller.canvasScale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.7),
                        width: 2,
                      ),
                      color: AppColors.gold.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),

            // 작성자 툴팁 (지우개 선택 시에는 표시 안 함 → 지우개 미리보기만)
            // IgnorePointer: 툴팁이 이벤트를 먹지 않아서 이미지 길게 누르기·이동이 정상 동작
            if (_hoveredAuthorName != null &&
                _hoveredPosition != null &&
                widget.controller.currentPen != PenType.eraser)
              Positioned(
                left: _hoveredPosition!.dx + 10,
                top: _hoveredPosition!.dy - 30,
                child: IgnorePointer(
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
              ),

            // 시간순 네비게이션 바 (우측, 위·아래 버튼과 겹치지 않도록 bottom 여유)
            Positioned(
              right: 8,
              top: 60,
              bottom: 72,
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
                    logPublic: widget.logPublic,
                  );
                },
              ),
            ),

            // 이벤트 이동 화살표 (우측 하단, 네비게이션 바 왼쪽에 배치해 겹침 방지)
            Positioned(
              right: 48,
              bottom: 16,
              child: _buildEventNavigationButtons(),
            ),
                      ],
                    ),
                  ),
                ),

            // 크기 조정·회전·반전 핸들 오버레이 — GestureDetector 밖에 두어 터치 시 캔버스가 경쟁하지 않음
            if (widget.controller.selectedMedia != null &&
                widget.controller.isMediaInResizeMode(widget.controller.selectedMedia!.id))
              _buildMediaResizeOverlay(context, viewportSize),
              ],
            );
          },
        ),
      ),
  );
  }

  /// 미디어 로컬 좌표(뷰 기준)를 뷰 절대 좌표로 (회전 반영)
  Offset _mediaLocalToView(double viewX, double viewY, double x, double y, double w, double h, double cosA, double sinA) {
    final cx = w / 2;
    final cy = h / 2;
    final relX = viewX - cx;
    final relY = viewY - cy;
    return Offset(
      x + cx + (relX * cosA - relY * sinA),
      y + cy + (relX * sinA + relY * cosA),
    );
  }

  void _overlayResizeUpdate(Offset localPosition) {
    if (_overlayResizeHandle == null) return;
    final media = widget.controller.selectedMedia;
    if (media == null) return;
    final viewDelta = Offset(
      localPosition.dx - _overlayResizeStartLocal.dx,
      localPosition.dy - _overlayResizeStartLocal.dy,
    );
    final scale = widget.controller.canvasScale;
    final moveCanvas = Offset(viewDelta.dx / scale, viewDelta.dy / scale);
    final angleRad = media.angleDegrees * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    // 미디어 로컬 기준: 폭 방향 성분, 높이 방향 성분 (회전 시에도 한 축만 변경되도록)
    final widthDelta = moveCanvas.dx * cosA + moveCanvas.dy * sinA;
    final heightDelta = -moveCanvas.dx * sinA + moveCanvas.dy * cosA;

    double w = _overlayResizeStartWidth;
    double h = _overlayResizeStartHeight;
    double? newX;
    double? newY;
    switch (_overlayResizeHandle!) {
      case _OverlayResizeHandle.bottomRight:
      case _OverlayResizeHandle.bottomLeft:
      case _OverlayResizeHandle.topRight:
      case _OverlayResizeHandle.topLeft:
        // 모서리: 정 비율 유지 (scaleX·scaleY 중 작은 쪽으로 통일)
        final scaleX = _overlayResizeHandle == _OverlayResizeHandle.bottomRight || _overlayResizeHandle == _OverlayResizeHandle.topRight
            ? (_overlayResizeStartWidth + moveCanvas.dx) / _overlayResizeStartWidth
            : (_overlayResizeStartWidth - moveCanvas.dx) / _overlayResizeStartWidth;
        final scaleY = _overlayResizeHandle == _OverlayResizeHandle.bottomRight || _overlayResizeHandle == _OverlayResizeHandle.bottomLeft
            ? (_overlayResizeStartHeight + moveCanvas.dy) / _overlayResizeStartHeight
            : (_overlayResizeStartHeight - moveCanvas.dy) / _overlayResizeStartHeight;
        final rawScale = scaleX.abs() <= scaleY.abs() ? scaleX : scaleY;
        final minScale = _minMediaSize / _overlayResizeStartWidth > _minMediaSize / _overlayResizeStartHeight
            ? _minMediaSize / _overlayResizeStartWidth
            : _minMediaSize / _overlayResizeStartHeight;
        final s = rawScale.clamp(minScale, 10.0);
        w = _overlayResizeStartWidth * s;
        h = _overlayResizeStartHeight * s;
        if (_overlayResizeHandle == _OverlayResizeHandle.bottomLeft || _overlayResizeHandle == _OverlayResizeHandle.topLeft) {
          newX = _overlayResizeStartX + (_overlayResizeStartWidth - w);
        }
        if (_overlayResizeHandle == _OverlayResizeHandle.topLeft || _overlayResizeHandle == _OverlayResizeHandle.topRight) {
          newY = _overlayResizeStartY + (_overlayResizeStartHeight - h);
        }
        break;
      case _OverlayResizeHandle.right:
        // 우측 핸들: 폭만 변경 (높이 유지)
        w = (_overlayResizeStartWidth + widthDelta).clamp(_minMediaSize, double.infinity);
        break;
      case _OverlayResizeHandle.left:
        // 좌측 핸들: 폭만 변경 (높이 유지)
        w = (_overlayResizeStartWidth - widthDelta).clamp(_minMediaSize, double.infinity);
        newX = _overlayResizeStartX + (_overlayResizeStartWidth - w);
        break;
      case _OverlayResizeHandle.bottom:
        // 아래 핸들: 위아래(높이)만 변경 (폭 유지)
        h = (_overlayResizeStartHeight + heightDelta).clamp(_minMediaSize, double.infinity);
        break;
      case _OverlayResizeHandle.top:
        // 위 핸들: 위아래(높이)만 변경 (폭 유지)
        h = (_overlayResizeStartHeight - heightDelta).clamp(_minMediaSize, double.infinity);
        newY = _overlayResizeStartY + (_overlayResizeStartHeight - h);
        break;
    }
    widget.controller.resizeMedia(media.id, w, h, x: newX, y: newY);
  }

  Widget _buildMediaResizeOverlay(BuildContext context, Size viewportSize) {
    final media = widget.controller.selectedMedia!;
    if (media.isLocked) return const SizedBox.shrink();
    final o = widget.controller.canvasOffset;
    final s = widget.controller.canvasScale;
    final x = media.x * s + o.dx;
    final y = media.y * s + o.dy;
    final w = media.width * s;
    final h = media.height * s;
    final angleRad = media.angleDegrees * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final centerView = Offset(x + w / 2, y + h / 2);
    final box = context.findRenderObject() as RenderBox?;
    final centerGlobal = box != null ? box.localToGlobal(centerView) : centerView;
    const handleSize = 14.0;
    const oOut = 14.0;

    final resizePositions = [
      [_OverlayResizeHandle.topLeft, -oOut, -oOut],
      [_OverlayResizeHandle.topRight, w, -oOut],
      [_OverlayResizeHandle.bottomLeft, -oOut, h],
      [_OverlayResizeHandle.bottomRight, w, h],
      [_OverlayResizeHandle.top, w / 2 - handleSize / 2, -oOut],
      [_OverlayResizeHandle.bottom, w / 2 - handleSize / 2, h],
      [_OverlayResizeHandle.left, -oOut, h / 2 - handleSize / 2],
      [_OverlayResizeHandle.right, w, h / 2 - handleSize / 2],
    ];

    final resizeHandles = <Widget>[];
    for (final p in resizePositions) {
      final handle = p[0] as _OverlayResizeHandle;
      final pos = _mediaLocalToView((p[1] as double) + handleSize / 2, (p[2] as double) + handleSize / 2, x, y, w, h, cosA, sinA);
      resizeHandles.add(
        Positioned(
          left: pos.dx - handleSize / 2,
          top: pos.dy - handleSize / 2,
          child: GestureDetector(
            onPanStart: (d) {
              setState(() {
                _overlayResizeHandle = handle;
                _overlayResizeStartWidth = media.width;
                _overlayResizeStartHeight = media.height;
                _overlayResizeStartX = media.x;
                _overlayResizeStartY = media.y;
                _overlayResizeStartLocal = d.localPosition;
              });
            },
            onPanUpdate: (d) => _overlayResizeUpdate(d.localPosition),
            onPanEnd: (_) => setState(() => _overlayResizeHandle = null),
            child: Container(
              width: handleSize,
              height: handleSize,
              decoration: BoxDecoration(
                color: AppColors.paper,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.mediaActive, width: 1.5),
              ),
            ),
          ),
        ),
      );
    }

    // 위쪽 중앙: 회전 핸들
    final posRotate = _mediaLocalToView(w / 2, -_rotationHandleOffset, x, y, w, h, cosA, sinA);
    const flipHitHalf = 22.0;
    const flipHandleGap = 20.0;
    final posFlipV = _mediaLocalToView(-flipHandleGap, h / 5, x, y, w, h, cosA, sinA);
    final posFlipH = _mediaLocalToView(w / 5, h + flipHandleGap, x, y, w, h, cosA, sinA);

    // 메뉴 바: 화면 기준 아래쪽 고정, 회전과 무관. 사진 하단(뷰에서 최하단) + 높이 1배 이격
    const barHeight = 52.0;
    const barPadding = 12.0;
    final p0 = _mediaLocalToView(0, 0, x, y, w, h, cosA, sinA);
    final p1 = _mediaLocalToView(w, 0, x, y, w, h, cosA, sinA);
    final p2 = _mediaLocalToView(w, h, x, y, w, h, cosA, sinA);
    final p3 = _mediaLocalToView(0, h, x, y, w, h, cosA, sinA);
    final bottomView = math.max(math.max(p0.dy, p1.dy), math.max(p2.dy, p3.dy));
    final mediaCenterInView = _mediaLocalToView(w / 2, h / 2, x, y, w, h, cosA, sinA);
    final gap = h * 0.15; // 이격 = 이미지 높이 50%
    final barTop = bottomView + gap;
    const barItemWidth = 52.0;
    const barItemCount = 5;
    final barWidth = barItemWidth * barItemCount;
    var barLeft = mediaCenterInView.dx - barWidth / 2;
    barLeft = barLeft.clamp(barPadding, viewportSize.width - barWidth - barPadding);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ...resizeHandles,
        Positioned(
          left: posRotate.dx - flipHitHalf,
          top: posRotate.dy - flipHitHalf,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              setState(() {
                _rotateOverlayStartAngleRad = math.atan2(
                  d.globalPosition.dy - centerGlobal.dy,
                  d.globalPosition.dx - centerGlobal.dx,
                );
                _rotateOverlayStartMediaDegrees = media.angleDegrees;
              });
            },
            onPanUpdate: (d) {
              if (_rotateOverlayStartAngleRad == null || _rotateOverlayStartMediaDegrees == null) return;
              final currentRad = math.atan2(
                d.globalPosition.dy - centerGlobal.dy,
                d.globalPosition.dx - centerGlobal.dx,
              );
              final deltaDeg = (currentRad - _rotateOverlayStartAngleRad!) * 180 / math.pi;
              final newDeg = _rotateOverlayStartMediaDegrees! + deltaDeg;
              widget.controller.rotateMedia(media.id, newDeg);
            },
            onPanEnd: (_) => setState(() {
              _rotateOverlayStartAngleRad = null;
              _rotateOverlayStartMediaDegrees = null;
            }),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.mediaActive, width: 1.5),
                  ),
                  child: Icon(Icons.rotate_right, size: 10, color: AppColors.mediaActive),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: posFlipV.dx - flipHitHalf,
          top: posFlipV.dy - flipHitHalf,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.controller.setMediaFlip(media.id, flipV: !media.flipVertical),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.mediaActive, width: 1.5),
                  ),
                  child: Icon(Icons.swap_vert, size: 10, color: AppColors.mediaActive),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: posFlipH.dx - flipHitHalf,
          top: posFlipH.dy - flipHitHalf,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.controller.setMediaFlip(media.id, flipH: !media.flipHorizontal),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.mediaActive, width: 1.5),
                  ),
                  child: Icon(Icons.swap_horiz, size: 10, color: AppColors.mediaActive),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: barLeft,
          top: barTop,
          child: Material(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(8),
            elevation: 2,
            child: Container(
              width: barWidth,
              height: barHeight,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _mediaBarButton(context, Icons.copy, '복사', () => widget.controller.duplicateMedia(media.id)),
                  _mediaBarButton(context, Icons.delete_outline, '삭제', () => widget.controller.deleteMedia(media.id)),
                  _mediaBarButton(context, Icons.flip_to_front, '앞', () => widget.controller.bringMediaToFront(media.id)),
                  _mediaBarButton(context, Icons.flip_to_back, '뒤', () => widget.controller.sendMediaToBack(media.id)),
                  _mediaBarButton(context, Icons.crop, '자르기', () {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('자르기 기능은 준비 중입니다.')),
                      );
                    }
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mediaBarButton(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: 48,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppColors.mediaActive),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.ink),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
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
                        leading: const Icon(Icons.tag, color: AppColors.ink),
                        title: const Text('@친구 태그'),
                        onTap: () {
                          Navigator.pop(context);
                          _showTagFriendPicker(context, media);
                        },
                      ),
                      ListTile(
                        leading: Icon(
                          media.isLocked ? Icons.lock_open : Icons.lock,
                          color: AppColors.ink,
                        ),
                        title: Text(media.isLocked ? '잠금 해제' : '잠금'),
                        onTap: () {
                          Navigator.pop(context);
                          widget.controller.setMediaLocked(media.id, !media.isLocked);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.aspect_ratio, color: AppColors.ink),
                        title: const Text('크기 수정'),
                        onTap: () {
                          Navigator.pop(context);
                          widget.controller.enterMediaResizeMode(media.id);
                        },
                      ),
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

  /// 미디어에 @친구 태그: 친구 선택 피커 표시 후 태그 생성
  void _showTagFriendPicker(BuildContext context, MediaModel media) {
    final friendProvider = context.read<FriendProvider>();
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.uid;
    if (userId == null) return;

    final tagService = TagService();
    TagTargetType targetType;
    switch (media.type) {
      case MediaType.image:
        targetType = TagTargetType.image;
        break;
      case MediaType.video:
        targetType = TagTargetType.video;
        break;
      default:
        targetType = TagTargetType.text; // PDF 등
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('태그할 친구 선택', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: friendProvider.friends.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('친구가 없습니다. 친구 탭에서 추가해 보세요.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: friendProvider.friends.length,
                        itemBuilder: (_, i) {
                          final friend = friendProvider.friends[i];
                          final user = friendProvider.getFriendUser(friend.friendId);
                          final name = user?.displayName ?? user?.email ?? friend.friendId;
                          return ListTile(
                            leading: const Icon(Icons.person, color: AppColors.ink),
                            title: Text(name),
                            onTap: () async {
                              Navigator.pop(ctx);
                              try {
                                final tag = TagModel(
                                  id: '',
                                  roomId: widget.roomId,
                                  taggerId: userId,
                                  taggedUserId: friend.friendId,
                                  targetType: targetType,
                                  targetId: media.id,
                                  createdAt: DateTime.now(),
                                );
                                await tagService.createTag(tag);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$name 님을 태그했습니다.')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('태그 실패: $e')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// 캔버스 롱프레스: 미디어 위면 활성화(녹색 박스), 아니면 도형/손글씨 처리
  void _onCanvasLongPress(Offset localPosition) {
    final canvasPoint = _transformPoint(localPosition);
    final medias = List.of(widget.controller.serverMedia)
        .where((m) => m.url.isNotEmpty)
        .toList()
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    for (final media in medias) {
      final rect = Rect.fromLTWH(media.x, media.y, media.width, media.height);
      if (rect.contains(canvasPoint)) {
        widget.controller.selectMedia(media);
        widget.controller.enterMediaResizeMode(media.id);
        return;
      }
    }
    // 도형 길게 누르면 삭제 (손 터치)
    final shapeAt = widget.controller.getShapeAtPoint(canvasPoint);
    if (shapeAt != null) {
      widget.controller.deleteShape(shapeAt.id);
      return;
    }
    final hit = _getStrokeAtPoint(canvasPoint);
    if (hit == null) {
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.of(context).size.height * 0.35,
              child: Material(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(16),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.tag, color: AppColors.ink),
                        title: const Text('@친구 태그'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showTagStrokeFriendPicker(context, hit.strokeId, hit.areaX, hit.areaY, hit.areaWidth, hit.areaHeight);
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

  /// 해당 캔버스 좌표에 있는 스트로크 반환 (id + 영역). 없으면 null.
  ({String strokeId, double areaX, double areaY, double areaWidth, double areaHeight})? _getStrokeAtPoint(Offset canvasPoint) {
    const hitRadius = 24.0;

    // 서버 스트로크 (역순으로 → 위에 그려진 것 우선)
    for (final stroke in widget.controller.serverStrokes.reversed) {
      if (stroke.isDeleted) continue;
      for (final p in stroke.points) {
        final o = Offset(p.x, p.y);
        if ((o - canvasPoint).distance <= hitRadius) {
          final (minX, maxX, minY, maxY) = _strokeBounds(stroke.points.map((p) => Offset(p.x, p.y)));
          return (
            strokeId: stroke.id,
            areaX: minX,
            areaY: minY,
            areaWidth: (maxX - minX).clamp(1.0, double.infinity),
            areaHeight: (maxY - minY).clamp(1.0, double.infinity),
          );
        }
      }
    }

    // 로컬 스트로크
    for (final stroke in widget.controller.localStrokes.reversed) {
      final id = stroke.firestoreId ?? stroke.id;
      for (final p in stroke.points) {
        if ((p - canvasPoint).distance <= hitRadius) {
          final (minX, maxX, minY, maxY) = _strokeBounds(stroke.points);
          return (
            strokeId: id,
            areaX: minX,
            areaY: minY,
            areaWidth: (maxX - minX).clamp(1.0, double.infinity),
            areaHeight: (maxY - minY).clamp(1.0, double.infinity),
          );
        }
      }
    }

    return null;
  }

  (double, double, double, double) _strokeBounds(Iterable<Offset> points) {
    if (points.isEmpty) return (0, 0, 0, 0);
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return (minX, maxX, minY, maxY);
  }

  /// 손글씨(스트로크)에 @친구 태그: 친구 선택 후 태그 생성 (영역 포함)
  void _showTagStrokeFriendPicker(BuildContext context, String strokeId, double areaX, double areaY, double areaWidth, double areaHeight) {
    final friendProvider = context.read<FriendProvider>();
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.uid;
    if (userId == null) return;

    final tagService = TagService();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('태그할 친구 선택', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: friendProvider.friends.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('친구가 없습니다. 친구 탭에서 추가해 보세요.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: friendProvider.friends.length,
                        itemBuilder: (_, i) {
                          final friend = friendProvider.friends[i];
                          final user = friendProvider.getFriendUser(friend.friendId);
                          final name = user?.displayName ?? user?.email ?? friend.friendId;
                          return ListTile(
                            leading: const Icon(Icons.person, color: AppColors.ink),
                            title: Text(name),
                            onTap: () async {
                              Navigator.pop(ctx);
                              try {
                                final tag = TagModel(
                                  id: '',
                                  roomId: widget.roomId,
                                  taggerId: userId,
                                  taggedUserId: friend.friendId,
                                  targetType: TagTargetType.stroke,
                                  targetId: strokeId,
                                  areaX: areaX,
                                  areaY: areaY,
                                  areaWidth: areaWidth,
                                  areaHeight: areaHeight,
                                  createdAt: DateTime.now(),
                                );
                                await tagService.createTag(tag);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$name 님을 태그했습니다.')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('태그 실패: $e')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
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

    // 손글씨는 스타일러스·마우스만 (손 터치로는 손글씨 안 됨)
    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    if (isStylus || event.kind == PointerDeviceKind.mouse) {
      final localPoint = _transformPoint(event.localPosition);
      final forceEraser = event.kind == PointerDeviceKind.invertedStylus ||
          (event.buttons & kSecondaryStylusButton) != 0 ||
          (event.buttons & kSecondaryMouseButton) != 0;
      if (widget.controller.currentPen == PenType.eraser || forceEraser) {
        setState(() => _eraserHoverPosition = event.localPosition);
      }
      
      if (widget.controller.inputMode == InputMode.shape) {
        widget.controller.startShape(localPoint);
        return;
      }
      
      widget.controller.startStroke(localPoint, forceEraser: forceEraser);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentInputKind == null) return;

    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;

    if (isStylus || _currentInputKind == PointerDeviceKind.mouse) {
      final localPoint = _transformPoint(event.localPosition);
      final forceEraser = _currentInputKind == PointerDeviceKind.invertedStylus ||
          (event.buttons & kSecondaryStylusButton) != 0 ||
          (event.buttons & kSecondaryMouseButton) != 0;
      if (widget.controller.currentPen == PenType.eraser || forceEraser) {
        setState(() => _eraserHoverPosition = event.localPosition);
      }
      
      if (widget.controller.inputMode == InputMode.shape) {
        widget.controller.updateShape(localPoint);
        return;
      }
      
      widget.controller.updateStroke(localPoint, forceEraser: forceEraser);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;

    if (isStylus || _currentInputKind == PointerDeviceKind.mouse) {
      setState(() => _eraserHoverPosition = null);
      if (widget.controller.inputMode == InputMode.shape) {
        widget.controller.endShape();
        _currentInputKind = null;
        return;
      }
      
      widget.controller.endStroke();
    }

    _currentInputKind = null;
  }

  /// 펜 호버 (지우개 미리보기 또는 작성자 표시)
  void _onPointerHover(PointerHoverEvent event) {
    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final isMouse = event.kind == PointerDeviceKind.mouse;
    // 배럴 버튼 누름 또는 지우개 끝(invertedStylus) → 호버만 해도 지우개 미리보기
    final barrelOrEraserEnd = event.kind == PointerDeviceKind.invertedStylus ||
        (event.buttons & kSecondaryStylusButton) != 0 ||
        (event.buttons & kSecondaryMouseButton) != 0;

    // 지우개 선택 시 또는 배럴 버튼/지우개 끝 호버 시 → 지우개 미리보기만 (작성자 툴팁 숨김)
    if ((widget.controller.currentPen == PenType.eraser || barrelOrEraserEnd) &&
        (isStylus || isMouse)) {
      _eraserHoverHideTimer?.cancel();
      setState(() {
        _eraserHoverPosition = event.localPosition;
        _hoveredAuthorName = null;
        _hoveredPosition = null;
      });
      _eraserHoverHideTimer = Timer(_eraserHoverHideDelay, () {
        if (mounted) setState(() => _eraserHoverPosition = null);
      });
      return;
    }

    if (!isStylus) {
      _eraserHoverHideTimer?.cancel();
      setState(() => _eraserHoverPosition = null);
      return;
    }

    _eraserHoverHideTimer?.cancel();
    setState(() => _eraserHoverPosition = null);
    final localPoint = _transformPoint(event.localPosition);
    _checkAuthorAtPoint(localPoint, event.localPosition);
  }

  /// 뷰(캔버스 영역) 로컬 좌표 점이 미디어의 축정렬 사각형(AABB) 안에 있는지
  bool _isPointInsideMediaScreenAABB(Offset localPoint, MediaModel media) {
    final o = widget.controller.canvasOffset;
    final s = widget.controller.canvasScale;
    final left = media.x * s + o.dx;
    final top = media.y * s + o.dy;
    final w = media.width * s;
    final h = media.height * s;
    return localPoint.dx >= left &&
        localPoint.dx <= left + w &&
        localPoint.dy >= top &&
        localPoint.dy <= top + h;
  }

  /// 캔버스 좌표 점이 회전된 미디어 사각형 안에 있는지
  bool _isPointInsideRotatedMedia(Offset canvasPoint, MediaModel media, [double margin = 0]) {
    final cx = media.x + media.width / 2;
    final cy = media.y + media.height / 2;
    final angleRad = media.angleDegrees * math.pi / 180;
    final dx = canvasPoint.dx - cx;
    final dy = canvasPoint.dy - cy;
    final localX = dx * math.cos(angleRad) + dy * math.sin(angleRad);
    final localY = -dx * math.sin(angleRad) + dy * math.cos(angleRad);
    final halfW = media.width / 2 + margin;
    final halfH = media.height / 2 + margin;
    return localX.abs() <= halfW && localY.abs() <= halfH;
  }

  /// 짧은 탭 (폰에서 작성자 표시)
  void _onTapUp(TapUpDetails details) {
    final localPoint = _transformPoint(details.localPosition);

    // 미디어 위 탭으로는 선택 안 함 (선택은 길게 누를 때만). 이미 선택된 미디어 탭은 MediaWidget에서 메뉴 표시
    final medias = List.of(widget.controller.serverMedia)
        .where((m) => m.url.isNotEmpty)
        .toList()
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    for (final media in medias) {
      if (_isPointInsideRotatedMedia(localPoint, media)) {
        return;
      }
    }

    // 크기 조정 모드: 사진 밖(캔버스) 탭 시 선택 해제 + 녹색 박스 숨김
    if (widget.controller.isInMediaResizeMode || widget.controller.selectedMedia != null) {
      final media = widget.controller.selectedMedia;
      if (media != null && !_isPointInsideRotatedMedia(localPoint, media)) {
        widget.controller.selectMedia(null);
        return;
      }
    }

    // 텍스트 입력 모드
    if (widget.controller.inputMode == InputMode.text) {
      _showTextInputDialog(localPoint);
      return;
    }

    // 작성자 표시: 펜(스타일러스)일 때만 (손가락 탭에서는 표시 안 함)
    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;
    if (isStylus) {
      _checkAuthorAtPoint(localPoint, details.localPosition);
    }
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

  /// senderId → 표시 이름 (채팅방 멤버/현재 사용자 조회)
  String? _displayNameForSender(String senderId) {
    final auth = context.read<AuthProvider>();
    if (senderId == widget.userId) {
      return auth.user?.displayName;
    }
    final member = context.read<RoomProvider>().getMemberUser(senderId);
    return member?.displayName;
  }

  /// 손글씨 히트 반경: 두께의 절반 + 여백(5). 최소 15로 깜박임 방지.
  static const double _hoverMargin = 5.0;
  static const double _minStrokeHitRadius = 15.0;

  void _checkAuthorAtPoint(Offset canvasPoint, Offset screenPosition) {
    String? authorName;

    // 1) 이미지/영상/PDF: 위에 있는 미디어부터 (zIndex 높은 순)
    final medias = List.of(widget.controller.serverMedia)
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    for (final media in medias) {
      final rect = Rect.fromLTWH(media.x, media.y, media.width, media.height);
      if (rect.contains(canvasPoint)) {
        authorName = _displayNameForSender(media.senderId) ??
            '사용자 ${media.senderId.length >= 6 ? media.senderId.substring(0, 6) : media.senderId}';
        break;
      }
    }

    // 2) 키보드 입력 텍스트 (위치 지정/빠른 텍스트)
    if (authorName == null) {
      for (final text in widget.controller.serverTexts.reversed) {
        final x = text.positionX ?? 0;
        final y = text.positionY ?? 0;
        final w = (text.width != null && text.width! > 0)
            ? text.width!
            : math.max(40.0, math.min(400.0, (text.content?.length ?? 0) * 10.0));
        final h = (text.height != null && text.height! > 0)
            ? text.height!
            : 24.0;
        final rect = Rect.fromLTWH(x, y, w, h);
        if (rect.contains(canvasPoint)) {
          authorName = _displayNameForSender(text.senderId) ??
              '사용자 ${text.senderId.length >= 6 ? text.senderId.substring(0, 6) : text.senderId}';
          break;
        }
      }
    }

    // 3) 서버 스트로크 (두께+여백 반경으로 정확도·안정성 확보)
    if (authorName == null) {
      for (final stroke in widget.controller.serverStrokes.reversed) {
        final radius = math.max(
            _minStrokeHitRadius, stroke.style.width * 0.5 + _hoverMargin);
        for (final p in stroke.points) {
          final offset = Offset(p.x, p.y);
          if ((offset - canvasPoint).distance < radius) {
            authorName = _displayNameForSender(stroke.senderId) ??
                '사용자 ${stroke.senderId.length >= 6 ? stroke.senderId.substring(0, 6) : stroke.senderId}';
            break;
          }
        }
        if (authorName != null) break;
      }
    }

    // 4) 로컬 스트로크 (같은 방식)
    if (authorName == null) {
      for (final stroke in widget.controller.localStrokes.reversed) {
        final radius = math.max(
            _minStrokeHitRadius, stroke.strokeWidth * 0.5 + _hoverMargin);
        for (final p in stroke.points) {
          if ((p - canvasPoint).distance < radius) {
            authorName = stroke.senderName ??
                _displayNameForSender(stroke.senderId) ??
                '사용자 ${stroke.senderId.length >= 6 ? stroke.senderId.substring(0, 6) : stroke.senderId}';
            break;
          }
        }
        if (authorName != null) break;
      }
    }

    if (authorName != null) {
      _authorTooltipLeaveTimer?.cancel();
      _authorTooltipLeaveTimer = null;
      setState(() {
        _hoveredAuthorName = authorName;
        _hoveredPosition = screenPosition;
      });
      _authorTooltipAutoHideTimer?.cancel();
      _authorTooltipAutoHideTimer = Timer(_authorAutoHideAfter, () {
        if (mounted) {
          setState(() {
            _hoveredAuthorName = null;
            _hoveredPosition = null;
          });
        }
      });
    } else {
      _authorTooltipAutoHideTimer?.cancel();
      _authorTooltipLeaveTimer ??= Timer(_authorLeaveDelay, () {
        _authorTooltipLeaveTimer = null;
        if (!mounted) return;
        setState(() {
          _hoveredAuthorName = null;
          _hoveredPosition = null;
        });
      });
    }
  }

  void _clearTooltip() {
    _authorTooltipLeaveTimer?.cancel();
    _authorTooltipLeaveTimer = null;
    _authorTooltipAutoHideTimer?.cancel();
    _authorTooltipAutoHideTimer = null;
    if (_hoveredAuthorName != null) {
      setState(() {
        _hoveredAuthorName = null;
        _hoveredPosition = null;
      });
    }
  }

  // 핀치 줌: 제스처 시작 시 배율 고정 (두 번째 핀치에서 배율 리셋 방지)
  double _pinchStartCanvasScale = 1.0;

  /// 제스처 시작 위치로 타겟 결정. 이미 선택된 미디어 위면 media(이동), 아니면 canvas(스크롤만).
  /// 선택은 길게 누를 때만 되므로, 짧게 누르고 드래그하면 캔버스만 이동.
  void _resolveGestureTargetFromPoint(Offset localPoint) {
    final selected = widget.controller.selectedMedia;
    if (selected != null &&
        widget.controller.isMediaInResizeMode(selected.id) &&
        _isPointInsideMediaScreenAABB(localPoint, selected)) {
      _gestureTarget = _GestureTarget.media;
      _activeMediaId = selected.id;
      return;
    }
    // 미디어 위여도 선택되지 않았으면 캔버스로 처리 → 스크롤만 됨
    _gestureTarget = _GestureTarget.canvas;
    _activeMediaId = null;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _pinchStartCanvasScale = widget.controller.canvasScale;
    // AABB는 뷰(캔버스 영역) 로컬 좌표로 계산되므로 로컬 포인트 사용 (글로벌이면 아래쪽 터치가 박스 밖으로 잘못 판정됨)
    _resolveGestureTargetFromPoint(details.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_gestureTarget == _GestureTarget.media && _activeMediaId != null) {
      // 사진 이동은 1손가락만 (2손가락은 캔버스 줌으로만 쓰고 사진은 안 움직이게)
      if (details.pointerCount == 1) {
        final deltaCanvas = details.focalPointDelta / widget.controller.canvasScale;
        widget.controller.moveMedia(_activeMediaId!, deltaCanvas);
      }
      return;
    }
    if (_gestureTarget == _GestureTarget.canvas) {
      if (details.pointerCount == 1) {
        final isPenOrMouse = _currentInputKind == PointerDeviceKind.stylus ||
            _currentInputKind == PointerDeviceKind.invertedStylus ||
            _currentInputKind == PointerDeviceKind.mouse;
        if (isPenOrMouse) return;
        widget.controller.pan(details.focalPointDelta);
      } else if (details.pointerCount == 2) {
        final newScale = (_pinchStartCanvasScale * details.scale).clamp(0.1, 5.0);
        final factor = newScale / widget.controller.canvasScale;
        widget.controller.zoom(factor, details.localFocalPoint);
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureTarget = _GestureTarget.none;
    _activeMediaId = null;
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
  final Rect? highlightTagRect;
  final bool strokesOnly;

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
    this.highlightTagRect,
    this.strokesOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    if (!strokesOnly) {
      // 배경
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = AppColors.paper,
      );
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
      // 태그 영역 하이라이트 (모아보기 → 원본 점프 시)
      if (highlightTagRect != null) {
        final fillPaint = Paint()
          ..color = AppColors.gold.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;
        final strokePaint = Paint()
          ..color = AppColors.gold
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;
        final rrect = RRect.fromRectAndRadius(
          highlightTagRect!.inflate(4),
          const Radius.circular(4),
        );
        canvas.drawRRect(rrect, fillPaint);
        canvas.drawRRect(rrect, strokePaint);
      }
    }

    if (strokesOnly) {
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
    Color color = Color(colorValue | 0xFF000000);

    double opacity = stroke.isConfirmed ? 1.0 : 0.6;
    if (stroke.style.penType == 'highlighter') {
      opacity *= 0.4; // 형광펜 반투명
    }

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

    double alpha = opacity;
    if (stroke.penType == PenType.highlighter) {
      alpha *= 0.4; // 형광펜 반투명
    }
    final paint = Paint()
      ..color = stroke.color.withValues(alpha: alpha)
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
