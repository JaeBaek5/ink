import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_colors.dart';
import '../../models/media_model.dart';
import '../../models/stroke_model.dart';
import '../../models/message_model.dart';

/// 타임라인 이벤트 타입
enum TimelineEventType {
  stroke,  // 손글씨
  text,    // 텍스트
  image,   // 사진
  video,   // 영상
  pdf,     // PDF
}

/// 타임라인 이벤트
class TimelineEvent {
  final String id;
  final TimelineEventType type;
  final DateTime timestamp;
  final double x;
  final double y;
  final String? senderId;

  TimelineEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.x,
    required this.y,
    this.senderId,
  });
}

/// 시간순 네비게이션 바 (우측 세로)
class TimelineNavigator extends StatefulWidget {
  final List<StrokeModel> strokes;
  final List<MessageModel> texts;
  final List<MediaModel> media;
  final Function(Offset position) onJump;
  final double canvasHeight;
  /// 방장 설정: false면 로그(타임라인) 비공개로 바 표시만
  final bool logPublic;

  const TimelineNavigator({
    super.key,
    required this.strokes,
    required this.texts,
    required this.media,
    required this.onJump,
    this.canvasHeight = 5000,
    this.logPublic = true,
  });

  @override
  State<TimelineNavigator> createState() => _TimelineNavigatorState();
}

class _TimelineNavigatorState extends State<TimelineNavigator> {
  double _dragPosition = 0;
  bool _isDragging = false;
  TimelineEvent? _hoveredEvent;
  double _barHeight = 200;

  List<TimelineEvent> get _allEvents {
    final events = <TimelineEvent>[];

    // 스트로크
    for (final stroke in widget.strokes) {
      if (stroke.points.isNotEmpty) {
        events.add(TimelineEvent(
          id: stroke.id,
          type: TimelineEventType.stroke,
          timestamp: stroke.createdAt,
          x: stroke.points.first.x,
          y: stroke.points.first.y,
          senderId: stroke.senderId,
        ));
      }
    }

    // 텍스트
    for (final text in widget.texts) {
      events.add(TimelineEvent(
        id: text.id,
        type: TimelineEventType.text,
        timestamp: text.createdAt,
        x: text.positionX ?? 0,
        y: text.positionY ?? 0,
        senderId: text.senderId,
      ));
    }

    // 미디어
    for (final m in widget.media) {
      TimelineEventType type;
      switch (m.type) {
        case MediaType.image:
          type = TimelineEventType.image;
          break;
        case MediaType.video:
          type = TimelineEventType.video;
          break;
        case MediaType.pdf:
          type = TimelineEventType.pdf;
          break;
      }
      events.add(TimelineEvent(
        id: m.id,
        type: type,
        timestamp: m.createdAt,
        x: m.x,
        y: m.y,
        senderId: m.senderId,
      ));
    }

    // 시간순 정렬
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return events;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.logPublic) {
      return SizedBox(
        width: 40,
        child: Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(
              '로그 비공개',
              style: TextStyle(fontSize: 10, color: AppColors.mutedGray),
            ),
          ),
        ),
      );
    }
    final events = _allEvents;
    if (events.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 40,
      child: Column(
          children: [
            // 시작 시간 (상단, 단순 표시)
            Text(
              _formatTime(events.first.timestamp),
              style: TextStyle(
                color: AppColors.mutedGray,
                fontSize: 9,
              ),
            ),
            const SizedBox(height: 4),
            // 네비게이션 바
            Expanded(
              child: GestureDetector(
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                onTapUp: _onTap,
                child: Container(
                  width: 24,
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;
                      if (height > 0) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _barHeight != height) setState(() => _barHeight = height);
                        });
                      }
                      final previewEvent = _isDragging ? _eventAtPosition(_dragPosition, height, events) : null;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 이벤트 마커들
                          ..._buildEventMarkers(events, height),

                          // 드래그 중 미리보기 카드 (바 왼쪽에 표시)
                          if (_isDragging && previewEvent != null)
                            Positioned(
                              left: -132,
                              top: (_dragPosition.clamp(0.0, height - 20) - 28).clamp(0.0, height - 56),
                              child: _buildDragPreviewCard(previewEvent),
                            ),

                          // 드래그 핸들
                          if (_isDragging)
                            Positioned(
                              top: _dragPosition.clamp(0, height - 20),
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.drag_handle,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 4),
            // 끝 시간 (하단, 단순 표시)
            Text(
              _formatTime(events.last.timestamp),
              style: TextStyle(
                color: AppColors.mutedGray,
                fontSize: 9,
              ),
            ),
          ],
        ),
    );
  }

  /// 마커 배치와 미리보기/점프에서 공통 사용: 이벤트별 보정된 Y 위치(픽셀) 반환.
  static List<double> _adjustedTopsForEvents(List<TimelineEvent> events, double height) {
    if (events.isEmpty) return [];
    const markerHeight = 8.0;
    final usableHeight = (height - markerHeight).clamp(1.0, double.infinity);
    final firstTime = events.first.timestamp.millisecondsSinceEpoch;
    final lastTime = events.last.timestamp.millisecondsSinceEpoch;
    final timeRange = (lastTime - firstTime).clamp(1, 0x7FFFFFFFFFFFFFFF);

    if (events.length == 1) {
      return [(height - markerHeight) / 2];
    }

    final tops = <double>[];
    for (var i = 0; i < events.length; i++) {
      final progress = (events[i].timestamp.millisecondsSinceEpoch - firstTime) / timeRange;
      tops.add((progress * usableHeight).clamp(0.0, usableHeight));
    }

    final sortedIndices = List.generate(events.length, (i) => i);
    sortedIndices.sort((a, b) => tops[a].compareTo(tops[b]));
    const overlapThreshold = 10.0;
    var prevTop = -100.0;
    final adjustedTops = List.filled(events.length, 0.0);
    for (final i in sortedIndices) {
      var top = tops[i];
      if (top - prevTop < overlapThreshold && prevTop >= 0) {
        top = (prevTop + overlapThreshold).clamp(0.0, usableHeight);
      }
      prevTop = top;
      adjustedTops[i] = top;
    }
    return adjustedTops;
  }

  List<Widget> _buildEventMarkers(List<TimelineEvent> events, double height) {
    if (events.isEmpty) return [];

    final adjustedTops = _adjustedTopsForEvents(events, height);
    if (adjustedTops.isEmpty) return [];

    if (events.length == 1) {
      return [
        Positioned(
          top: adjustedTops[0],
          left: 4,
          right: 4,
          child: _markerWithGesture(events.first),
        ),
      ];
    }

    return List.generate(events.length, (i) {
      return Positioned(
        top: adjustedTops[i],
        left: 4,
        right: 4,
        child: _markerWithGesture(events[i]),
      );
    });
  }

  Widget _markerWithGesture(TimelineEvent event) {
    return GestureDetector(
      onTap: () => _jumpToEvent(event),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredEvent = event),
        onExit: (_) => setState(() => _hoveredEvent = null),
        child: Tooltip(
          message: '${_getEventTypeName(event.type)} - ${_formatDateTime(event.timestamp)}',
          child: _buildMarker(event),
        ),
      ),
    );
  }

  Widget _buildMarker(TimelineEvent event) {
    final isHovered = _hoveredEvent?.id == event.id;
    
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: _getMarkerColor(event.type).withValues(alpha: isHovered ? 1.0 : 0.7),
        borderRadius: BorderRadius.circular(4),
        border: isHovered
            ? Border.all(color: AppColors.gold, width: 1)
            : null,
      ),
      child: Center(
        child: Icon(
          _getMarkerIcon(event.type),
          size: 6,
          color: Colors.white,
        ),
      ),
    );
  }

  Color _getMarkerColor(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.stroke:
        return AppColors.ink;
      case TimelineEventType.text:
        return Colors.blue;
      case TimelineEventType.image:
        return Colors.green;
      case TimelineEventType.video:
        return Colors.purple;
      case TimelineEventType.pdf:
        return Colors.red;
    }
  }

  IconData _getMarkerIcon(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.stroke:
        return Icons.edit;
      case TimelineEventType.text:
        return Icons.text_fields;
      case TimelineEventType.image:
        return Icons.image;
      case TimelineEventType.video:
        return Icons.videocam;
      case TimelineEventType.pdf:
        return Icons.picture_as_pdf;
    }
  }

  String _getEventTypeName(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.stroke:
        return '손글씨';
      case TimelineEventType.text:
        return '텍스트';
      case TimelineEventType.image:
        return '사진';
      case TimelineEventType.video:
        return '영상';
      case TimelineEventType.pdf:
        return 'PDF';
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${_formatTime(dt)}';
  }

  /// 바 위 Y 위치 → 마커와 동일한 보정된 위치 기준으로 가장 가까운 이벤트 반환 (미리보기/점프와 마커 시각 동기화)
  TimelineEvent? _eventAtPosition(double barY, double height, List<TimelineEvent> events) {
    if (events.isEmpty || height <= 0) return null;
    const markerHeight = 8.0;
    final adjustedTops = _adjustedTopsForEvents(events, height);
    if (adjustedTops.length != events.length) return events.first;

    // 각 마커의 시각적 중심 Y = adjustedTop + markerHeight/2
    var bestIdx = 0;
    var bestDiff = (adjustedTops[0] + markerHeight / 2 - barY).abs();
    for (var i = 1; i < events.length; i++) {
      final centerY = adjustedTops[i] + markerHeight / 2;
      final d = (centerY - barY).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestIdx = i;
      }
    }
    return events[bestIdx];
  }

  /// 드래그 중 표시할 미리보기 카드 (실제 손글씨/이미지/텍스트 표시)
  Widget _buildDragPreviewCard(TimelineEvent event) {
    const previewWidth = 128.0;
    const previewHeight = 96.0;

    Widget previewContent;
    switch (event.type) {
      case TimelineEventType.stroke:
        StrokeModel? stroke;
        try {
          stroke = widget.strokes.firstWhere((s) => s.id == event.id);
        } catch (_) {}
        previewContent = stroke != null
            ? _buildStrokePreview(stroke, previewWidth, previewHeight)
            : _buildFallbackPreview(event, previewWidth, previewHeight);
        break;
      case TimelineEventType.image:
        MediaModel? media;
        try {
          media = widget.media.firstWhere((m) => m.id == event.id);
        } catch (_) {}
        previewContent = media != null
            ? _buildImagePreview(media, previewWidth, previewHeight)
            : _buildFallbackPreview(event, previewWidth, previewHeight);
        break;
      case TimelineEventType.video:
      case TimelineEventType.pdf:
        MediaModel? mediaM;
        try {
          mediaM = widget.media.firstWhere((m) => m.id == event.id);
        } catch (_) {}
        previewContent = mediaM != null
            ? _buildMediaThumbnailPreview(mediaM, previewWidth, previewHeight)
            : _buildFallbackPreview(event, previewWidth, previewHeight);
        break;
      case TimelineEventType.text:
        MessageModel? text;
        try {
          text = widget.texts.firstWhere((t) => t.id == event.id);
        } catch (_) {}
        previewContent = text != null
            ? _buildTextPreview(text, previewWidth, previewHeight)
            : _buildFallbackPreview(event, previewWidth, previewHeight);
        break;
    }

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: AppColors.paper,
      child: Container(
        width: previewWidth,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: previewContent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                _formatDateTime(event.timestamp),
                style: const TextStyle(fontSize: 10, color: AppColors.mutedGray),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 손글씨 스트로크 미리보기 (실제 그린 선 표시)
  Widget _buildStrokePreview(StrokeModel stroke, double w, double h) {
    if (stroke.points.isEmpty) {
      return const Center(child: Icon(Icons.edit, color: AppColors.mutedGray, size: 24));
    }
    final points = stroke.points.map((p) => Offset(p.x, p.y)).toList();
    double minX = points.first.dx, maxX = points.first.dx;
    double minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final rangeX = (maxX - minX).clamp(1.0, double.infinity);
    final rangeY = (maxY - minY).clamp(1.0, double.infinity);
    const pad = 4.0;
    final scale = ((w - pad * 2) / rangeX).clamp(0.0, (h - pad * 2) / rangeY);
    final scaleY = ((h - pad * 2) / rangeY).clamp(0.0, (w - pad * 2) / rangeX);
    final useScale = scale <= scaleY ? scale : scaleY;
    final color = _parseHexColor(stroke.style.color);

    return CustomPaint(
      size: Size(w, h),
      painter: _StrokePreviewPainter(
        points: points,
        minX: minX,
        minY: minY,
        scale: useScale,
        padding: pad,
        color: color,
        strokeWidth: (stroke.style.width * useScale).clamp(0.5, 4.0),
      ),
    );
  }

  /// 사진 미리보기 (실제 이미지)
  Widget _buildImagePreview(MediaModel media, double w, double h) {
    final url = media.thumbnailUrl ?? media.url;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: w,
      height: h,
      memCacheWidth: 256,
      memCacheHeight: 192,
      placeholder: (_, __) => Container(
        color: AppColors.mutedGray.withValues(alpha: 0.2),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: AppColors.mutedGray.withValues(alpha: 0.2),
        child: const Icon(Icons.image_not_supported, color: AppColors.mutedGray),
      ),
    );
  }

  /// 영상/PDF 썸네일 또는 아이콘
  Widget _buildMediaThumbnailPreview(MediaModel media, double w, double h) {
    final thumbUrl = media.thumbnailUrl;
    final eventType = media.type == MediaType.video
        ? TimelineEventType.video
        : TimelineEventType.pdf;
    if (thumbUrl != null && media.type == MediaType.video) {
      return CachedNetworkImage(
        imageUrl: thumbUrl,
        fit: BoxFit.cover,
        width: w,
        height: h,
        placeholder: (_, __) => _mediaPlaceholder(eventType, w, h),
        errorWidget: (_, __, ___) => _mediaPlaceholder(eventType, w, h),
      );
    }
    return _mediaPlaceholder(eventType, w, h);
  }

  Widget _mediaPlaceholder(TimelineEventType type, double w, double h) {
    return Container(
      color: _getMarkerColor(type).withValues(alpha: 0.15),
      child: Center(
        child: Icon(_getMarkerIcon(type), size: 32, color: _getMarkerColor(type)),
      ),
    );
  }

  /// 텍스트 미리보기
  Widget _buildTextPreview(MessageModel text, double w, double h) {
    final content = text.content ?? '';
    return Container(
      color: AppColors.paper,
      padding: const EdgeInsets.all(6),
      alignment: Alignment.topLeft,
      child: Text(
        content.isEmpty ? '(텍스트)' : content,
        style: const TextStyle(fontSize: 11, color: AppColors.ink),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 유형만 표시 (원본을 찾지 못한 경우)
  Widget _buildFallbackPreview(TimelineEvent event, double w, double h) {
    return Container(
      color: _getMarkerColor(event.type).withValues(alpha: 0.15),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getMarkerIcon(event.type), size: 28, color: _getMarkerColor(event.type)),
            const SizedBox(height: 4),
            Text(
              _getEventTypeName(event.type),
              style: const TextStyle(fontSize: 10, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }

  static Color _parseHexColor(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) {
      return Color(int.parse(h, radix: 16) | 0xFF000000);
    }
    if (h.length == 8) {
      return Color(int.parse(h, radix: 16));
    }
    return AppColors.ink;
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragPosition = details.localPosition.dy;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragPosition = details.localPosition.dy;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    _jumpToPosition(_dragPosition);
    setState(() {
      _isDragging = false;
    });
  }

  void _onTap(TapUpDetails details) {
    _jumpToPosition(details.localPosition.dy);
  }

  void _jumpToPosition(double barY) {
    final events = _allEvents;
    if (events.isEmpty) return;
    final event = _eventAtPosition(barY, _barHeight, events);
    if (event != null) _jumpToEvent(event);
  }

  void _jumpToEvent(TimelineEvent event) {
    widget.onJump(Offset(event.x, event.y));
  }
}

/// 손글씨 미리보기용 페인터
class _StrokePreviewPainter extends CustomPainter {
  final List<Offset> points;
  final double minX;
  final double minY;
  final double scale;
  final double padding;
  final Color color;
  final double strokeWidth;

  _StrokePreviewPainter({
    required this.points,
    required this.minX,
    required this.minY,
    required this.scale,
    required this.padding,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final dx = padding - minX * scale;
    final dy = padding - minY * scale;
    path.moveTo(points[0].dx * scale + dx, points[0].dy * scale + dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx * scale + dx, points[i].dy * scale + dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokePreviewPainter old) {
    return old.points != points ||
        old.scale != scale ||
        old.padding != padding ||
        old.color != color ||
        old.strokeWidth != strokeWidth;
  }
}
