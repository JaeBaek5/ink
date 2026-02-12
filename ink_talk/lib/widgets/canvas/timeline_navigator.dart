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

/// 타임라인 이벤트 (단일 항목)
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

/// 문장 단위 세그먼트 (3초 이상 손글씨 미입력 기준 그룹)
/// - 스트로크 그룹: 첫 입력 ~ 마지막 입력 (~3초 휴식)
/// - 텍스트/사진/영상/PDF: 각각 단일 세그먼트
class TimelineSegment {
  final TimelineEventType type;
  final DateTime startTime;
  final DateTime endTime;
  final double x;
  final double y;
  /// 점프 시 뷰포트 중앙에 올 좌표 (중앙 기준). null이면 x, y 사용(좌상단 기준).
  final double? centerX;
  final double? centerY;
  /// 스트로크 그룹일 때 포함된 스트로크 ID 목록
  final List<String> strokeIds;
  /// 단일 이벤트 ID (텍스트/미디어)
  final String? singleEventId;
  final String? senderId;

  TimelineSegment({
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.x,
    required this.y,
    this.centerX,
    this.centerY,
    this.strokeIds = const [],
    this.singleEventId,
    this.senderId,
  });

  String get displayId => singleEventId ?? (strokeIds.isNotEmpty ? strokeIds.first : '');
}

Color _parseHexColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length == 6) {
    return Color(int.parse(h, radix: 16) | 0xFF000000);
  }
  if (h.length == 8) {
    return Color(int.parse(h, radix: 16));
  }
  return AppColors.ink;
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

  /// 3초 휴식 기준 세그먼트 목록 (화살표 네비게이션 등 공유용)
  static List<TimelineSegment> buildSegments({
    required List<StrokeModel> strokes,
    required List<MessageModel> texts,
    required List<MediaModel> media,
  }) {
    final segs = <TimelineSegment>[];
    final strokeList = strokes.where((s) => s.points.isNotEmpty).toList();
    strokeList.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    const pauseMs = 3000;

    if (strokeList.isNotEmpty) {
      var gs = 0;
      for (var i = 1; i <= strokeList.length; i++) {
        final last = i == strokeList.length;
        final gap = last ? 0 : strokeList[i].createdAt.millisecondsSinceEpoch - strokeList[i - 1].createdAt.millisecondsSinceEpoch;
        if (last || gap >= pauseMs) {
          final g = strokeList.sublist(gs, i);
          double minX = double.infinity, minY = double.infinity, maxX = double.negativeInfinity, maxY = double.negativeInfinity;
          for (final s in g) {
            for (final p in s.points) {
              if (p.x < minX) minX = p.x;
              if (p.y < minY) minY = p.y;
              if (p.x > maxX) maxX = p.x;
              if (p.y > maxY) maxY = p.y;
            }
          }
          final cx = minX.isFinite ? (minX + maxX) / 2 : g.first.points.first.x;
          final cy = minY.isFinite ? (minY + maxY) / 2 : g.first.points.first.y;
          segs.add(TimelineSegment(
            type: TimelineEventType.stroke,
            startTime: g.first.createdAt,
            endTime: g.last.createdAt,
            x: g.first.points.first.x,
            y: g.first.points.first.y,
            centerX: cx,
            centerY: cy,
            strokeIds: g.map((s) => s.id).toList(),
            senderId: g.first.senderId,
          ));
          gs = i;
        }
      }
    }
    for (final t in texts) {
      final px = t.positionX ?? 0;
      final py = t.positionY ?? 0;
      final w = t.width ?? 0;
      final h = t.height ?? 0;
      segs.add(TimelineSegment(
        type: TimelineEventType.text,
        startTime: t.createdAt,
        endTime: t.createdAt,
        x: px,
        y: py,
        centerX: px + w / 2,
        centerY: py + h / 2,
        singleEventId: t.id,
        senderId: t.senderId,
      ));
    }
    for (final m in media) {
      final ty = switch (m.type) {
        MediaType.image => TimelineEventType.image,
        MediaType.video => TimelineEventType.video,
        MediaType.pdf => TimelineEventType.pdf,
      };
      segs.add(TimelineSegment(
        type: ty,
        startTime: m.createdAt,
        endTime: m.createdAt,
        x: m.x,
        y: m.y,
        centerX: m.x + m.width / 2,
        centerY: m.y + m.height / 2,
        singleEventId: m.id,
        senderId: m.senderId,
      ));
    }
    segs.sort((a, b) => a.startTime.compareTo(b.startTime));
    return segs;
  }
}

class _TimelineNavigatorState extends State<TimelineNavigator> {
  double _dragPosition = 0;
  bool _isDragging = false;
  TimelineSegment? _hoveredSegment;
  double _barHeight = 200;

  /// 3초 이상 손글씨 미입력 기준으로 스트로크를 문장 단위 세그먼트로 그룹화
  static const _pauseThresholdMs = 3000;

  List<TimelineSegment> get _segments {
    final segments = <TimelineSegment>[];

    // 1) 스트로크만 추출 후 시간순 정렬
    final strokes = widget.strokes.where((s) => s.points.isNotEmpty).toList();
    strokes.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // 2) 텍스트·미디어를 (timestamp, type, data) 형태로 (중앙 계산용 width/height 포함)
    final nonStrokeEvents = <({DateTime t, TimelineEventType type, String id, double x, double y, double width, double height, String? senderId})>[];
    for (final text in widget.texts) {
      final px = text.positionX ?? 0;
      final py = text.positionY ?? 0;
      final w = text.width ?? 0;
      final h = text.height ?? 0;
      nonStrokeEvents.add((
        t: text.createdAt,
        type: TimelineEventType.text,
        id: text.id,
        x: px,
        y: py,
        width: w,
        height: h,
        senderId: text.senderId,
      ));
    }
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
      nonStrokeEvents.add((
        t: m.createdAt,
        type: type,
        id: m.id,
        x: m.x,
        y: m.y,
        width: m.width,
        height: m.height,
        senderId: m.senderId,
      ));
    }

    if (strokes.isEmpty && nonStrokeEvents.isEmpty) return segments;

    // 3) 스트로크 그룹화: 3초 휴식 구간마다 새 세그먼트
    if (strokes.isNotEmpty) {
      var groupStart = 0;
      for (var i = 1; i <= strokes.length; i++) {
        final isLast = i == strokes.length;
        final gapMs = isLast
            ? 0
            : strokes[i].createdAt.millisecondsSinceEpoch -
                strokes[i - 1].createdAt.millisecondsSinceEpoch;
        if (isLast || gapMs >= _pauseThresholdMs) {
          final group = strokes.sublist(groupStart, i);
          final first = group.first;
          double minX = double.infinity, minY = double.infinity, maxX = double.negativeInfinity, maxY = double.negativeInfinity;
          for (final s in group) {
            for (final p in s.points) {
              if (p.x < minX) minX = p.x;
              if (p.y < minY) minY = p.y;
              if (p.x > maxX) maxX = p.x;
              if (p.y > maxY) maxY = p.y;
            }
          }
          final cx = minX.isFinite ? (minX + maxX) / 2 : first.points.first.x;
          final cy = minY.isFinite ? (minY + maxY) / 2 : first.points.first.y;
          segments.add(TimelineSegment(
            type: TimelineEventType.stroke,
            startTime: first.createdAt,
            endTime: group.last.createdAt,
            x: first.points.first.x,
            y: first.points.first.y,
            centerX: cx,
            centerY: cy,
            strokeIds: group.map((s) => s.id).toList(),
            senderId: first.senderId,
          ));
          groupStart = i;
        }
      }
    }

    // 4) 텍스트·미디어는 각각 단일 세그먼트 (중앙 좌표 포함)
    for (final e in nonStrokeEvents) {
      segments.add(TimelineSegment(
        type: e.type,
        startTime: e.t,
        endTime: e.t,
        x: e.x,
        y: e.y,
        centerX: e.x + e.width / 2,
        centerY: e.y + e.height / 2,
        singleEventId: e.id,
        senderId: e.senderId,
      ));
    }

    segments.sort((a, b) => a.startTime.compareTo(b.startTime));
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.logPublic) {
      return SizedBox(
        width: 24,
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
    final segments = _segments;
    if (segments.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 24,
      child: Column(
        children: [
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
                      final previewSeg = _isDragging ? _segmentAtPosition(_dragPosition, height, segments) : null;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 세그먼트 마커들
                          ..._buildSegmentMarkers(segments, height),

                          // 드래그 중 미리보기 카드 (바 왼쪽에 표시)
                          if (_isDragging && previewSeg != null)
                            Positioned(
                              left: -132,
                              top: (_dragPosition.clamp(0.0, height - 20) - 28).clamp(0.0, height - 56),
                              child: _buildSegmentPreviewCard(previewSeg),
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
        ],
      ),
    );
  }

  /// 마커 배치와 미리보기/점프에서 공통 사용: 세그먼트별 Y 위치(픽셀). 이벤트 간격 동일하게 균등 배치.
  static List<double> _adjustedTopsForSegments(List<TimelineSegment> segments, double height) {
    if (segments.isEmpty) return [];
    const markerHeight = 8.0;
    final usableHeight = (height - markerHeight).clamp(1.0, double.infinity);
    if (segments.length == 1) {
      return [(height - markerHeight) / 2];
    }
    // 시간 비율이 아닌 개수 기준으로 균등 간격
    final step = usableHeight / (segments.length - 1);
    return List.generate(segments.length, (i) => (i * step).clamp(0.0, usableHeight));
  }

  List<Widget> _buildSegmentMarkers(List<TimelineSegment> segments, double height) {
    if (segments.isEmpty) return [];

    final adjustedTops = _adjustedTopsForSegments(segments, height);
    if (adjustedTops.isEmpty) return [];

    if (segments.length == 1) {
      return [
        Positioned(
          top: adjustedTops[0],
          left: 4,
          right: 4,
          child: _markerWithGesture(segments.first),
        ),
      ];
    }

    return List.generate(segments.length, (i) {
      return Positioned(
        top: adjustedTops[i],
        left: 4,
        right: 4,
        child: _markerWithGesture(segments[i]),
      );
    });
  }

  Widget _markerWithGesture(TimelineSegment segment) {
    return GestureDetector(
      onTap: () => _jumpToSegment(segment),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredSegment = segment),
        onExit: (_) => setState(() => _hoveredSegment = null),
        child: Tooltip(
          message: _segmentTooltip(segment),
          child: _buildSegmentMarker(segment),
        ),
      ),
    );
  }

  String _segmentTooltip(TimelineSegment seg) {
    final name = seg.type == TimelineEventType.stroke && seg.strokeIds.length > 1
        ? '손글씨 (${seg.strokeIds.length}획)'
        : _getEventTypeName(seg.type);
    return '$name - ${_formatDateTime(seg.startTime)}';
  }

  Widget _buildSegmentMarker(TimelineSegment segment) {
    final isHovered = _hoveredSegment == segment;
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: _getMarkerColor(segment.type).withValues(alpha: isHovered ? 1.0 : 0.7),
        borderRadius: BorderRadius.circular(4),
        border: isHovered
            ? Border.all(color: AppColors.gold, width: 1)
            : null,
      ),
      child: Center(
        child: Icon(
          _getMarkerIcon(segment.type),
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

  /// 바 위 Y 위치 → 마커와 동일한 보정된 위치 기준으로 가장 가까운 세그먼트 반환
  TimelineSegment? _segmentAtPosition(double barY, double height, List<TimelineSegment> segments) {
    if (segments.isEmpty || height <= 0) return null;
    const markerHeight = 8.0;
    final adjustedTops = _adjustedTopsForSegments(segments, height);
    if (adjustedTops.length != segments.length) return segments.first;

    var bestIdx = 0;
    var bestDiff = (adjustedTops[0] + markerHeight / 2 - barY).abs();
    for (var i = 1; i < segments.length; i++) {
      final centerY = adjustedTops[i] + markerHeight / 2;
      final d = (centerY - barY).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestIdx = i;
      }
    }
    return segments[bestIdx];
  }

  /// 드래그 중 표시할 미리보기 카드 (문장 단위: 여러 스트로크 합성 또는 단일 이벤트)
  Widget _buildSegmentPreviewCard(TimelineSegment segment) {
    const previewWidth = 128.0;
    const previewHeight = 96.0;

    Widget previewContent;
    if (segment.type == TimelineEventType.stroke && segment.strokeIds.isNotEmpty) {
      final strokes = segment.strokeIds
          .map((id) => widget.strokes.where((s) => s.id == id).firstOrNull)
          .whereType<StrokeModel>()
          .toList();
      previewContent = strokes.isNotEmpty
          ? _buildStrokeGroupPreview(strokes, previewWidth, previewHeight)
          : _buildFallbackSegmentPreview(segment, previewWidth, previewHeight);
    } else if (segment.singleEventId != null) {
      switch (segment.type) {
        case TimelineEventType.text:
          final text = widget.texts.where((t) => t.id == segment.singleEventId).firstOrNull;
          previewContent = text != null
              ? _buildTextPreview(text, previewWidth, previewHeight)
              : _buildFallbackSegmentPreview(segment, previewWidth, previewHeight);
          break;
        case TimelineEventType.image:
          final media = widget.media.where((m) => m.id == segment.singleEventId).firstOrNull;
          previewContent = media != null
              ? _buildImagePreview(media, previewWidth, previewHeight)
              : _buildFallbackSegmentPreview(segment, previewWidth, previewHeight);
          break;
        case TimelineEventType.video:
        case TimelineEventType.pdf:
          final mediaM = widget.media.where((m) => m.id == segment.singleEventId).firstOrNull;
          previewContent = mediaM != null
              ? _buildMediaThumbnailPreview(mediaM, previewWidth, previewHeight)
              : _buildFallbackSegmentPreview(segment, previewWidth, previewHeight);
          break;
        case TimelineEventType.stroke:
          previewContent = _buildFallbackSegmentPreview(segment, previewWidth, previewHeight);
          break;
      }
    } else {
      previewContent = _buildFallbackSegmentPreview(segment, previewWidth, previewHeight);
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
                _formatDateTime(segment.startTime),
                style: const TextStyle(fontSize: 10, color: AppColors.mutedGray),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 문장 단위: 여러 스트로크 합성 미리보기
  Widget _buildStrokeGroupPreview(List<StrokeModel> strokes, double w, double h) {
    if (strokes.isEmpty) {
      return const Center(child: Icon(Icons.edit, color: AppColors.mutedGray, size: 24));
    }
    if (strokes.length == 1) {
      return _buildStrokePreview(strokes.first, w, h);
    }
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final s in strokes) {
      for (final p in s.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }
    final rangeX = (maxX - minX).clamp(1.0, double.infinity);
    final rangeY = (maxY - minY).clamp(1.0, double.infinity);
    const pad = 4.0;
    final scale = ((w - pad * 2) / rangeX).clamp(0.0, (h - pad * 2) / rangeY);
    final scaleY = ((h - pad * 2) / rangeY).clamp(0.0, (w - pad * 2) / rangeX);
    final useScale = scale <= scaleY ? scale : scaleY;
    return CustomPaint(
      size: Size(w, h),
      painter: _StrokeGroupPreviewPainter(
        strokes: strokes,
        minX: minX,
        minY: minY,
        scale: useScale,
        padding: pad,
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

  Widget _buildFallbackSegmentPreview(TimelineSegment segment, double w, double h) {
    return Container(
      color: _getMarkerColor(segment.type).withValues(alpha: 0.15),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getMarkerIcon(segment.type), size: 28, color: _getMarkerColor(segment.type)),
            const SizedBox(height: 4),
            Text(
              segment.type == TimelineEventType.stroke && segment.strokeIds.length > 1
                  ? '손글씨 (${segment.strokeIds.length}획)'
                  : _getEventTypeName(segment.type),
              style: const TextStyle(fontSize: 10, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
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
    final segments = _segments;
    if (segments.isEmpty) return;
    final segment = _segmentAtPosition(barY, _barHeight, segments);
    if (segment != null) _jumpToSegment(segment);
  }

  void _jumpToSegment(TimelineSegment segment) {
    final cx = segment.centerX ?? segment.x;
    final cy = segment.centerY ?? segment.y;
    widget.onJump(Offset(cx, cy));
  }
}

/// 문장 단위 여러 스트로크 합성 미리보기용 페인터
class _StrokeGroupPreviewPainter extends CustomPainter {
  final List<StrokeModel> strokes;
  final double minX;
  final double minY;
  final double scale;
  final double padding;

  _StrokeGroupPreviewPainter({
    required this.strokes,
    required this.minX,
    required this.minY,
    required this.scale,
    required this.padding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dx = padding - minX * scale;
    final dy = padding - minY * scale;
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final color = _parseHexColor(stroke.style.color);
      final strokeWidth = (stroke.style.width * scale).clamp(0.5, 4.0);
      final paint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      final p0 = stroke.points.first;
      path.moveTo(p0.x * scale + dx, p0.y * scale + dy);
      for (var i = 1; i < stroke.points.length; i++) {
        final p = stroke.points[i];
        path.lineTo(p.x * scale + dx, p.y * scale + dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokeGroupPreviewPainter old) =>
      old.strokes != strokes || old.scale != scale;
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
