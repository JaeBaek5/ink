import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
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
import 'image_crop_screen.dart';
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

  /// 펜/지우개 모드이고 해당 미디어가 크기 조정 중이 아니면 true (포인터 무시 → 캔버스로 통과).
  /// 크기 조정(resize) 모드일 때는 true로 해서 상위 GestureDetector가 pan을 받아 PDF/영상/사진 이동이 되도록 함.
  /// 영상은 선택 안 했을 때만 터치 받음 (재생 버튼).
  bool _mediaIgnorePointer(MediaModel media) {
    if (widget.controller.isMediaInResizeMode(media.id)) return true;
    if (media.type == MediaType.video) return false;
    final pen = widget.controller.currentPen;
    final isDrawingTool = pen == PenType.pen1 || pen == PenType.pen2 || pen == PenType.fountain || pen == PenType.brush || pen == PenType.highlighter || pen == PenType.eraser;
    return isDrawingTool;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onExit: (_) {
        _eraserHoverHideTimer?.cancel();
        setState(() => _eraserHoverPosition = null);
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
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
            // 캔버스 (배경·격자·도형) — 미디어는 아래 별도 레이어로 올려 터치가 재생 버튼 등에 전달되게 함
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
                          selectionPath: widget.controller.selectionPath,
                          selectionRect: widget.controller.selectionRect,
                          selectedStrokeIds: widget.controller.selectedStrokeIds,
                        ),
                        size: Size.infinite,
                      ),
            ),

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
                  selectionPath: widget.controller.selectionPath,
                  selectionRect: widget.controller.selectionRect,
                  selectedStrokeIds: widget.controller.selectedStrokeIds,
                  selectedMediaIds: widget.controller.selectedMediaIds,
                  selectedTextIds: widget.controller.selectedTextIds,
                  serverMedia: widget.controller.serverMedia,
                  serverTexts: widget.controller.serverTexts,
                ),
                size: Size.infinite,
              ),
            ),

            // 텍스트 오브젝트 렌더링
            ...widget.controller.serverTexts.map((text) => _buildTextWidget(text)),

            // 위치 지정 텍스트 모드: 손가락으로 누른 위치에 깜빡이는 커서
            if (widget.controller.inputMode == InputMode.text &&
                widget.controller.textCursorPosition != null)
              Positioned(
                left: (widget.controller.textCursorPosition!.dx * widget.controller.canvasScale +
                        widget.controller.canvasOffset.dx) -
                    1,
                top: widget.controller.textCursorPosition!.dy * widget.controller.canvasScale +
                    widget.controller.canvasOffset.dy,
                child: IgnorePointer(
                  child: _BlinkingCursor(
                    child: Container(
                      width: 2,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            // 빠른 텍스트: 탭한 위치(또는 전송 후 아랫줄)에 깜빡이는 커서 (캔버스 좌표 → 화면 좌표)
            if (widget.controller.inputMode == InputMode.quickText &&
                widget.controller.quickTextCursorPosition != null)
              Positioned(
                left: widget.controller.quickTextCursorPosition!.dx * widget.controller.canvasScale +
                    widget.controller.canvasOffset.dx -
                    1,
                top: widget.controller.quickTextCursorPosition!.dy * widget.controller.canvasScale +
                    widget.controller.canvasOffset.dy,
                child: IgnorePointer(
                  child: _BlinkingCursor(
                    child: Container(
                      width: 2,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),

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

            // 작성자 툴팁 (지우개 선택 시·글씨 쓰는 중에는 표시 안 함)
            // IgnorePointer: 툴팁이 이벤트를 먹지 않아서 이미지 길게 누르기·이동이 정상 동작
            if (_hoveredAuthorName != null &&
                _hoveredPosition != null &&
                widget.controller.currentPen != PenType.eraser &&
                widget.controller.currentStroke == null &&
                _currentInputKind == null)
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

                      ],
                    ),
                  ),
                ),

            // 업로드 중: 업로드될 위치에 아이콘 + 글씨만 표시 (박스 없음)
            ...widget.controller.uploadingPlaceholders.map((p) => Positioned(
                  left: p.x,
                  top: p.y,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '업로드 중…',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )),

            // 미디어 오브젝트 (GestureDetector 밖에 두어 재생 버튼 등 터치가 미디어에 전달되도록)
            ...widget.controller.serverMedia
                .where((media) => media.url.isNotEmpty)
                .map((media) => MediaWidget(
              key: ValueKey(media.id),
              media: media,
              isSelected: widget.controller.selectedMedia?.id == media.id,
              isResizeMode: widget.controller.isMediaInResizeMode(media.id),
              pdfViewMode: media.type == MediaType.pdf ? widget.controller.getPdfViewMode(media.id) : null,
              pdfCurrentPage: media.type == MediaType.pdf ? widget.controller.getPdfPage(media.id) : 1,
              onPdfPageChanged: media.type == MediaType.pdf ? (page) => widget.controller.setPdfPage(media.id, page) : null,
              onPdfPageCountLoaded: media.type == MediaType.pdf ? (count) => widget.controller.setPdfPageCount(media.id, count) : null,
              cropRect: media.type == MediaType.image ? widget.controller.getMediaCropRect(media.id) : null,
              canvasOffset: widget.controller.canvasOffset,
              canvasScale: widget.controller.canvasScale,
              onTap: () {
                // 1번 터치 시 바텀시트 없음 — 친구 태그·잠금은 액션 바 '...' 메뉴에서 사용
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
              ignorePointer: _mediaIgnorePointer(media),
            )),

            // 크기 조정·회전·반전 핸들 오버레이 — GestureDetector 밖에 두어 터치 시 캔버스가 경쟁하지 않음
            if (widget.controller.selectedMedia != null &&
                widget.controller.isMediaInResizeMode(widget.controller.selectedMedia!.id))
              _buildMediaResizeOverlay(context, viewportSize),

            // 시간순 네비게이션 바 + 위/아래 버튼 (같은 너비 24, 바 바로 아래 배치)
            Positioned(
              right: 8,
              top: 60,
              bottom: 24,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    children: [
                      Expanded(
                        child: TimelineNavigator(
                          strokes: widget.controller.serverStrokes,
                          texts: widget.controller.serverTexts,
                          media: widget.controller.serverMedia,
                          onJump: (position) {
                            widget.controller.jumpToPosition(position, viewportSize);
                          },
                          logPublic: widget.logPublic,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 24,
                        child: _buildEventNavigationButtons(),
                      ),
                    ],
                  );
                },
              ),
            ),
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
    const barItemCount = 6; // 복사·삭제·앞·뒤·자르기·...
    final barWidth = barItemWidth * barItemCount;
    var barLeft = mediaCenterInView.dx - barWidth / 2;
    barLeft = barLeft.clamp(barPadding, viewportSize.width - barWidth - barPadding);

    // PDF 한 페이지 모드: 박스 밖 좌/우 화살표
    const arrowBtnSize = 56.0;
    final pdfArrowHalf = arrowBtnSize / 2;
    final isPdfSingle = media.type == MediaType.pdf &&
        widget.controller.getPdfViewMode(media.id) == PdfViewMode.singlePage;
    final pdfPage = widget.controller.getPdfPage(media.id);
    final pdfTotal = widget.controller.getPdfPageCount(media.id) ?? media.totalPages ?? 1;
    final hasPrevPdf = pdfPage > 1;
    final hasNextPdf = pdfPage < pdfTotal;
    const pdfArrowGap = 25.0; // 박스와 화살표 버튼 사이 공백
    final posPdfLeft = _mediaLocalToView(-pdfArrowHalf - pdfArrowGap, h / 2, x, y, w, h, cosA, sinA);
    final posPdfRight = _mediaLocalToView(w + pdfArrowHalf + pdfArrowGap, h / 2, x, y, w, h, cosA, sinA);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ...resizeHandles,
        if (isPdfSingle) ...[
          Positioned(
            left: posPdfLeft.dx - pdfArrowHalf,
            top: posPdfLeft.dy - pdfArrowHalf,
            width: arrowBtnSize,
            height: arrowBtnSize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasPrevPdf ? () => widget.controller.setPdfPage(media.id, pdfPage - 1) : null,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.paper.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.mediaActive, width: 1.5),
                  ),
                  child: Icon(
                    Icons.chevron_left,
                    size: 32,
                    color: hasPrevPdf ? AppColors.ink : AppColors.ink.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: posPdfRight.dx - pdfArrowHalf,
            top: posPdfRight.dy - pdfArrowHalf,
            width: arrowBtnSize,
            height: arrowBtnSize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasNextPdf ? () => widget.controller.setPdfPage(media.id, pdfPage + 1) : null,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.paper.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.mediaActive, width: 1.5),
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 32,
                    color: hasNextPdf ? AppColors.ink : AppColors.ink.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
        ],
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
                  _mediaBarButton(
                    context,
                    Icons.crop,
                    '자르기',
                    media.type == MediaType.pdf
                        ? () {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('PDF는 자르기를 지원하지 않습니다.')),
                              );
                            }
                          }
                        : () {
                            if (!context.mounted) return;
                            if (media.type == MediaType.video) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('영상은 자르기를 지원하지 않습니다.')),
                              );
                              return;
                            }
                            Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (context) => ImageCropScreen(
                                  media: media,
                                  initialCropRect: widget.controller.getMediaCropRect(media.id),
                                  onConfirm: (rect) => widget.controller.setMediaCropRect(media.id, rect),
                                  onCancel: () {},
                                ),
                              ),
                            );
                          },
                    enabled: media.type == MediaType.image,
                  ),
                  _mediaBarButton(context, Icons.more_horiz, '...', () => _showMediaMoreMenu(context, media, barLeft, barTop, barWidth)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 액션 바 '...' 메뉴 — 친구 태그·잠금 (사진/영상/PDF 공통), PDF일 때 정렬 방식 포함
  void _showMediaMoreMenu(BuildContext context, MediaModel media, double barLeft, double barTop, double barWidth) {
    const barItemWidth = 52.0;
    final buttonRight = barLeft + barWidth;
    final buttonLeft = buttonRight - barItemWidth;

    // 메뉴 항목: 'tag' | 'lock' | 'pdf_single' | 'pdf_grid'
    final items = <PopupMenuItem<String>>[
      PopupMenuItem<String>(
        value: 'tag',
        child: Row(
          children: [
            const Icon(Icons.tag, size: 20, color: AppColors.ink),
            const SizedBox(width: 12),
            const Text('@친구 태그'),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'lock',
        child: Row(
          children: [
            Icon(
              media.isLocked ? Icons.lock_open : Icons.lock,
              size: 20,
              color: AppColors.ink,
            ),
            const SizedBox(width: 12),
            Text(media.isLocked ? '잠금 해제' : '잠금'),
          ],
        ),
      ),
      if (media.type == MediaType.pdf) ...[
        PopupMenuItem<String>(
          value: 'pdf_single',
          child: Row(
            children: [
              Icon(
                Icons.view_agenda,
                size: 20,
                color: widget.controller.getPdfViewMode(media.id) == PdfViewMode.singlePage
                    ? AppColors.gold
                    : AppColors.ink,
              ),
              const SizedBox(width: 12),
              const Text('한 페이지 (화살표)'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'pdf_grid',
          child: Row(
            children: [
              Icon(
                Icons.grid_view,
                size: 20,
                color: widget.controller.getPdfViewMode(media.id) == PdfViewMode.grid
                    ? AppColors.gold
                    : AppColors.ink,
              ),
              const SizedBox(width: 12),
              const Text('여러 페이지 (그리드)'),
            ],
          ),
        ),
      ],
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(buttonLeft, barTop - 220, buttonRight + 8, barTop + 8),
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'tag':
          _showTagFriendPicker(context, media);
          break;
        case 'lock':
          widget.controller.setMediaLocked(media.id, !media.isLocked);
          break;
        case 'pdf_single':
          widget.controller.setPdfViewMode(media.id, PdfViewMode.singlePage);
          break;
        case 'pdf_grid':
          widget.controller.setPdfViewMode(media.id, PdfViewMode.grid);
          break;
      }
    });
  }

  Widget _mediaBarButton(BuildContext context, IconData icon, String label, VoidCallback onTap, {bool enabled = true}) {
    final color = enabled ? AppColors.mediaActive : AppColors.mutedGray;
    final textColor = enabled ? AppColors.ink : AppColors.mutedGray;
    return SizedBox(
      width: 48,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: textColor),
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
              fontSize: (text.fontSize ?? 16) * scale,
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
        if ((p.offset - canvasPoint).distance <= hitRadius) {
          final (minX, maxX, minY, maxY) = _strokeBounds(stroke.points.map((p) => p.offset));
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

  /// 이벤트 단위 이동 버튼 (네비게이션 바와 같은 너비 24)
  Widget _buildEventNavigationButtons() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(12),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 32,
            child: IconButton(
              onPressed: _goToPreviousEvent,
              icon: const Icon(Icons.keyboard_arrow_up),
              iconSize: 20,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              color: AppColors.ink,
              tooltip: '이전 이벤트',
            ),
          ),
          Container(width: 24, height: 1, color: AppColors.border),
          SizedBox(
            width: 24,
            height: 32,
            child: IconButton(
              onPressed: _goToNextEvent,
              icon: const Icon(Icons.keyboard_arrow_down),
              iconSize: 20,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              color: AppColors.ink,
              tooltip: '다음 이벤트',
            ),
          ),
        ],
      ),
    );
  }

  /// 문장 단위(3초 휴식 기준) 세그먼트 목록
  List<TimelineSegment> _getAllSegments() {
    return TimelineNavigator.buildSegments(
      strokes: widget.controller.serverStrokes,
      texts: widget.controller.serverTexts,
      media: widget.controller.serverMedia,
    );
  }

  /// 이전 세그먼트(문장)로 이동
  void _goToPreviousEvent() {
    final segments = _getAllSegments();
    if (segments.isEmpty) return;

    setState(() {
      _currentEventIndex = (_currentEventIndex - 1).clamp(0, segments.length - 1);
    });

    final seg = segments[_currentEventIndex];
    final size = widget.controller.viewportSize ?? const Size(400, 600);
    final cx = seg.centerX ?? seg.x;
    final cy = seg.centerY ?? seg.y;
    widget.controller.jumpToPosition(Offset(cx, cy), size);
  }

  /// 다음 세그먼트(문장)로 이동
  void _goToNextEvent() {
    final segments = _getAllSegments();
    if (segments.isEmpty) return;

    setState(() {
      _currentEventIndex = (_currentEventIndex + 1).clamp(0, segments.length - 1);
    });

    final seg = segments[_currentEventIndex];
    final size = widget.controller.viewportSize ?? const Size(400, 600);
    final cx = seg.centerX ?? seg.x;
    final cy = seg.centerY ?? seg.y;
    widget.controller.jumpToPosition(Offset(cx, cy), size);
  }

  void _onPointerDown(PointerDownEvent event) {
    _currentInputKind = event.kind;
    _clearTooltip();

    // 선택 도구: 스타일러스·마우스·손가락 모두 허용. 도형: 손가락으로 그리기 허용.
    final isSelectionMode = widget.controller.selectionTool != SelectionTool.none;
    final isShapeMode = widget.controller.inputMode == InputMode.shape;
    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final isPointerForInput = isStylus || event.kind == PointerDeviceKind.mouse ||
        (isSelectionMode && event.kind == PointerDeviceKind.touch) ||
        (isShapeMode && event.kind == PointerDeviceKind.touch);

    if (isPointerForInput) {
      final localPoint = _transformPoint(event.localPosition);
      final forceEraser = event.kind == PointerDeviceKind.invertedStylus ||
          (event.buttons & kSecondaryStylusButton) != 0 ||
          (event.buttons & kSecondaryMouseButton) != 0;
      if (widget.controller.currentPen == PenType.eraser || forceEraser) {
        setState(() => _eraserHoverPosition = event.localPosition);
      }

      // 선택 도구: 선택 영역 그리기 또는 선택된 항목(손글씨·미디어·텍스트) 이동
      if (widget.controller.selectionTool != SelectionTool.none) {
        if (widget.controller.hasSelectedStrokesOrMediaOrText &&
            widget.controller.isPointOnSelectedSelection(localPoint)) {
          widget.controller.startMovingSelection(localPoint);
        } else {
          widget.controller.startSelection(localPoint);
        }
        return;
      }
      
      if (widget.controller.inputMode == InputMode.shape) {
        widget.controller.startShape(localPoint);
        return;
      }
      
      widget.controller.startStroke(
        localPoint,
        forceEraser: forceEraser,
        pressure: event.pressure,
        timestamp: event.timeStamp.inMilliseconds,
      );
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentInputKind == null) return;

    // 글씨 쓰는 중에는 닉네임 툴팁 즉시 숨김
    if (_hoveredAuthorName != null) _clearTooltip();

    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;
    final isSelectionMode = widget.controller.selectionTool != SelectionTool.none;
    final isShapeMode = widget.controller.inputMode == InputMode.shape;
    final isPointerForInput = isStylus || _currentInputKind == PointerDeviceKind.mouse ||
        (isSelectionMode && _currentInputKind == PointerDeviceKind.touch) ||
        (isShapeMode && _currentInputKind == PointerDeviceKind.touch);

    if (isPointerForInput) {
      final localPoint = _transformPoint(event.localPosition);
      final forceEraser = _currentInputKind == PointerDeviceKind.invertedStylus ||
          (event.buttons & kSecondaryStylusButton) != 0 ||
          (event.buttons & kSecondaryMouseButton) != 0;
      if (widget.controller.currentPen == PenType.eraser || forceEraser) {
        setState(() => _eraserHoverPosition = event.localPosition);
      }

      if (widget.controller.isMovingSelection) {
        widget.controller.updateMovingSelection(localPoint);
        return;
      }
      if (widget.controller.isDrawingSelection) {
        widget.controller.updateSelection(localPoint);
        return;
      }
      
      if (isShapeMode) {
        widget.controller.updateShape(localPoint);
        return;
      }
      
      widget.controller.updateStroke(
        localPoint,
        forceEraser: forceEraser,
        pressure: event.pressure,
        timestamp: event.timeStamp.inMilliseconds,
      );
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;
    final isSelectionMode = widget.controller.selectionTool != SelectionTool.none;
    final isShapeMode = widget.controller.inputMode == InputMode.shape;
    final isPointerForInput = isStylus || _currentInputKind == PointerDeviceKind.mouse ||
        (isSelectionMode && _currentInputKind == PointerDeviceKind.touch) ||
        (isShapeMode && _currentInputKind == PointerDeviceKind.touch);

    if (isPointerForInput) {
      setState(() => _eraserHoverPosition = null);
      if (widget.controller.isMovingSelection) {
        widget.controller.endMovingSelection();
        _currentInputKind = null;
        return;
      }
      if (widget.controller.isDrawingSelection) {
        widget.controller.endSelection();
        _currentInputKind = null;
        return;
      }
      if (isShapeMode) {
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

    // 글씨 쓰는 중(포인터 내려감)에는 닉네임 표시 안 함
    if (_currentInputKind != null || widget.controller.currentStroke != null) {
      _eraserHoverHideTimer?.cancel();
      setState(() {
        _eraserHoverPosition = null;
        _hoveredAuthorName = null;
        _hoveredPosition = null;
      });
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

    // 텍스트 입력 모드: 손가락으로 누른 위치에 커서 표시 후 다이얼로그
    if (widget.controller.inputMode == InputMode.text) {
      widget.controller.setTextCursorPosition(localPoint);
      _showTextInputDialog(localPoint);
      return;
    }

    // 빠른 텍스트 모드: 손가락으로 누른 위치에 커서 표시(깜빡임), 키보드로 입력 후 전송 시 그 위치에 글 씀
    if (widget.controller.inputMode == InputMode.quickText) {
      widget.controller.setQuickTextCursorPosition(localPoint);
      return;
    }

    // 작성자 표시: 손가락 탭에서만 (펜 뗄 때 탭으로 인식되면 닉네임 뜨는 것 방지)
    // 스타일러스는 펜 뗄 때 onTapUp이 불려 글씨 쓴 직후 닉네임이 보이므로, 호버로만 표시
    final isStylus = _currentInputKind == PointerDeviceKind.stylus ||
        _currentInputKind == PointerDeviceKind.invertedStylus;
    if (!isStylus) {
      _checkAuthorAtPoint(localPoint, details.localPosition);
    }
  }

  /// 텍스트 입력 다이얼로그 (엔터=다음 줄, 추가 버튼으로만 제출. 글자 크기는 툴바 설정과 동기화)
  void _showTextInputDialog(Offset position) {
    final textController = TextEditingController();
    double selectedFontSize = widget.controller.textFontSize;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.paper,
              title: const Text('텍스트 입력'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('글자 크기(pt)', style: TextStyle(fontSize: 12, color: AppColors.mutedGray)),
                    const SizedBox(height: 4),
                    DropdownButton<double>(
                      value: [12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 56, 64, 72, 80, 96, 128].contains(selectedFontSize.round())
                          ? selectedFontSize
                          : 16.0,
                      isExpanded: true,
                      items: [12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 56, 64, 72, 80, 96, 128]
                          .map((v) => DropdownMenuItem(value: v.toDouble(), child: Text('$v pt')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedFontSize = v);
                          widget.controller.setTextFontSize(v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textController,
                      autofocus: true,
                      keyboardType: TextInputType.multiline,
                      maxLines: 5,
                      style: const TextStyle(color: AppColors.ink, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: '텍스트를 입력하세요 (엔터: 다음 줄)',
                        hintStyle: TextStyle(color: AppColors.mutedGray),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (textController.text.isNotEmpty) {
                      widget.controller.addText(
                        textController.text,
                        position,
                        fontSize: widget.controller.textFontSize,
                      );
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
      },
    ).then((_) => widget.controller.clearTextCursorPosition());
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
          if ((p.offset - canvasPoint).distance < radius) {
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
        if (widget.controller.selectionTool != SelectionTool.none &&
            (widget.controller.isDrawingSelection || widget.controller.isMovingSelection)) {
          return;
        }
        // 도형 그리는 중에는 캔버스 팬 안 함 (손가락으로 도형 그릴 때 캔버스 고정)
        if (widget.controller.shapeStartPoint != null) return;
        widget.controller.pan(details.focalPointDelta);
      } else if (details.pointerCount == 2) {
        final newScale = (_pinchStartCanvasScale * details.scale).clamp(0.1, 5.0);
        final factor = newScale / widget.controller.canvasScale;
        widget.controller.zoom(factor, details.localFocalPoint);
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_gestureTarget == _GestureTarget.media && _activeMediaId != null) {
      widget.controller.moveMediaEnd(_activeMediaId!);
    }
    _gestureTarget = _GestureTarget.none;
    _activeMediaId = null;
  }

  /// 화면 좌표를 캔버스 좌표로 변환
  Offset _transformPoint(Offset screenPoint) {
    return (screenPoint - widget.controller.canvasOffset) / widget.controller.canvasScale;
  }
}

/// 깜빡이는 커서 (위치 지정 텍스트 모드)
class _BlinkingCursor extends StatefulWidget {
  final Widget child;

  const _BlinkingCursor({required this.child});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animation, child: widget.child);
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
  final List<Offset>? selectionPath;
  final (Offset, Offset)? selectionRect;
  final Set<String> selectedStrokeIds;
  final Set<String> selectedMediaIds;
  final Set<String> selectedTextIds;
  final List<MediaModel> serverMedia;
  final List<MessageModel> serverTexts;

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
    this.selectionPath,
    this.selectionRect,
    this.selectedStrokeIds = const {},
    this.selectedMediaIds = const {},
    this.selectedTextIds = const {},
    this.serverMedia = const [],
    this.serverTexts = const [],
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
      // 로컬 스트로크 (아직 확정 안 된 것 - 고스트). 0.9로 통일해 찐/흐린 편차 완화
      for (final stroke in localStrokes) {
        final opacity = stroke.isConfirmed ? 1.0 : 0.9;
        _drawLocalStroke(canvas, stroke, opacity);
      }
      // 다른 사용자의 고스트 스트로크
      for (final stroke in ghostStrokes) {
        _drawLocalStroke(canvas, stroke, 0.75);
      }
      // 현재 그리는 중인 스트로크 (저장 직후와 동일한 0.9로 자연스럽게)
      if (currentStroke != null) {
        _drawLocalStroke(canvas, currentStroke!, 0.9);
      }
      // 선택 영역 그리기 (올가미/사각형)
      _drawSelectionOverlay(canvas);
      // 선택된 스트로크 하이라이트
      _drawSelectedStrokeHighlights(canvas);
      // 선택된 미디어·텍스트 하이라이트
      _drawSelectedMediaAndTextHighlights(canvas);
    }

    canvas.restore();
  }

  void _drawSelectedMediaAndTextHighlights(Canvas canvas) {
    if (selectedMediaIds.isEmpty && selectedTextIds.isEmpty) return;
    final paint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final media in serverMedia) {
      if (!selectedMediaIds.contains(media.id)) continue;
      final rect = Rect.fromLTWH(media.x, media.y, media.width, media.height);
      canvas.drawRect(rect.inflate(2), paint);
    }
    for (final text in serverTexts) {
      if (!selectedTextIds.contains(text.id)) continue;
      final x = text.positionX ?? 0.0;
      final y = text.positionY ?? 0.0;
      final w = (text.width != null && text.width! > 0)
          ? text.width!
          : ((text.content?.length ?? 0) * 10.0).clamp(40.0, 400.0);
      final h = text.height ?? 24.0;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h).inflate(2), paint);
    }
  }

  void _drawSelectionOverlay(Canvas canvas) {
    final strokePaint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (selectionPath != null && selectionPath!.length >= 2) {
      final path = Path()..moveTo(selectionPath!.first.dx, selectionPath!.first.dy);
      for (int i = 1; i < selectionPath!.length; i++) {
        path.lineTo(selectionPath![i].dx, selectionPath![i].dy);
      }
      path.close();
      canvas.drawPath(path, strokePaint);
    } else if (selectionRect != null) {
      final (a, b) = selectionRect!;
      canvas.drawRect(Rect.fromPoints(a, b), strokePaint);
    }
  }

  void _drawSelectedStrokeHighlights(Canvas canvas) {
    if (selectedStrokeIds.isEmpty) return;
    final paint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.4)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final stroke in serverStrokes) {
      if (!selectedStrokeIds.contains(stroke.id)) continue;
      final bbox = _strokeBBox(stroke.points.map((p) => Offset(p.x, p.y)).toList());
      canvas.drawRect(bbox.inflate(4), paint);
    }
    for (final stroke in localStrokes) {
      final id = stroke.firestoreId ?? stroke.id;
      if (!selectedStrokeIds.contains(id)) continue;
      final bbox = _strokeBBox(stroke.points.map((p) => p.offset).toList());
      canvas.drawRect(bbox.inflate(4), paint);
    }
  }

  Rect _strokeBBox(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
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

  /// perfect_freehand thinning (필압 영향도). 0=무시, 1=강함
  static double _thinningForPen(String penType) {
    switch (penType) {
      case 'pen1': return 0.25;   // 볼펜: 적은 변화
      case 'pen2': return 0.5;    // 연필: 중간
      case 'fountain': return 0.75; // 만년필: 강한 변화
      case 'brush': return 0.7;   // 브러시: 강한 변화
      default: return 0.5;
    }
  }

  static bool _isPressureSensitivePen(String penType) {
    return penType != 'highlighter';
  }

  /// 아웃라인 포인트를 베지어 곡선으로 부드럽게 연결 (각진 꼭짓점 완화)
  Path _smoothOutlinePath(List<Offset> outline) {
    final n = outline.length;
    if (n < 3) return Path();
    final path = Path();
    final p = outline;
    path.moveTo((p[n - 1].dx + p[0].dx) / 2, (p[n - 1].dy + p[0].dy) / 2);
    for (int i = 0; i < n; i++) {
      final next = (i + 1) % n;
      path.quadraticBezierTo(
        p[i].dx,
        p[i].dy,
        (p[i].dx + p[next].dx) / 2,
        (p[i].dy + p[next].dy) / 2,
      );
    }
    path.close();
    return path;
  }

  /// perfect_freehand로 부드러운 가변 굵기 스트로크 그리기 (얼룩 현상 제거)
  void _drawStrokeWithFreehand(
    Canvas canvas,
    List<PointVector> points,
    Color color,
    double baseWidth,
    String penType,
  ) {
    if (points.length < 2) {
      if (points.length == 1) {
        final p = points.first;
        final r = baseWidth / 2 * (0.5 + 0.5 * (p.pressure ?? 1.0));
        canvas.drawCircle(Offset(p.x, p.y), r, Paint()..color = color..style = PaintingStyle.fill);
      }
      return;
    }
    // streamline 낮춤: 빠르게 쓸 때 실제 궤적을 따라가도록 (높으면 빠른 입력이 지나치게 단순화됨)
    final outline = getStroke(
      points,
      options: StrokeOptions(
        size: baseWidth,
        thinning: _thinningForPen(penType),
        smoothing: 0.6,   // 적당히 부드럽게 (0.9→0.6, 빠른 스트로크 보존)
        streamline: 0.4,  // 입력 경로 충실히 유지 (0.8→0.4, 빠르게 써도 따라옴)
        simulatePressure: false,
        isComplete: true,
      ),
    );
    if (outline.length < 3) return;
    // 베지어 곡선으로 아웃라인 부드럽게 (각진 꼭짓점 완화)
    final path = _smoothOutlinePath(outline);
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  void _drawServerStroke(Canvas canvas, StrokeModel stroke) {
    if (stroke.points.isEmpty) return;

    final colorHex = stroke.style.color.replaceAll('#', '');
    final colorValue = int.parse(colorHex, radix: 16);
    Color color = Color(colorValue | 0xFF000000);

    double opacity = stroke.isConfirmed ? 1.0 : 0.9;
    if (stroke.style.penType == 'highlighter') {
      opacity *= 0.4;
    }

    final baseWidth = stroke.style.width;
    final penType = stroke.style.penType;
    final usePressure = _isPressureSensitivePen(penType);

    final strokeColor = color.withValues(alpha: opacity);

    if (!usePressure) {
      // 형광펜: 단일 path
      final paint = Paint()
        ..color = strokeColor
        ..strokeWidth = baseWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          Offset(stroke.points.first.x, stroke.points.first.y),
          baseWidth / 2,
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
      return;
    }

    // perfect_freehand: 부드러운 가변 굵기 (얼룩 없음)
    final points = stroke.points.map((p) => PointVector(
      p.x,
      p.y,
      p.pressure.clamp(0.0, 1.0),
    )).toList();
    _drawStrokeWithFreehand(canvas, points, strokeColor, baseWidth, penType);
  }

  void _drawLocalStroke(Canvas canvas, LocalStrokeData stroke, double opacity) {
    if (stroke.points.isEmpty) return;

    double alpha = opacity;
    if (stroke.penType == PenType.highlighter) {
      alpha *= 0.4; // 형광펜 반투명
    }

    final baseWidth = stroke.strokeWidth;
    final penTypeStr = stroke.penType.name;
    final usePressure = _isPressureSensitivePen(penTypeStr);

    final strokeColor = stroke.color.withValues(alpha: alpha);

    if (!usePressure) {
      final paint = Paint()
        ..color = strokeColor
        ..strokeWidth = baseWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first.offset, baseWidth / 2, paint..style = PaintingStyle.fill);
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.x, stroke.points.first.y);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].x, stroke.points[i].y);
        }
        canvas.drawPath(path, paint);
      }
      return;
    }

    // perfect_freehand: 부드러운 가변 굵기 (얼룩 없음)
    final points = stroke.points.map((p) => PointVector(
      p.x,
      p.y,
      p.pressure.clamp(0.0, 1.0),
    )).toList();
    _drawStrokeWithFreehand(canvas, points, strokeColor, baseWidth, penTypeStr);
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return true;
  }
}
