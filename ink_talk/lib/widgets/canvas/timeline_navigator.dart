import 'package:flutter/material.dart';
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

  const TimelineNavigator({
    super.key,
    required this.strokes,
    required this.texts,
    required this.media,
    required this.onJump,
    this.canvasHeight = 5000,
  });

  @override
  State<TimelineNavigator> createState() => _TimelineNavigatorState();
}

class _TimelineNavigatorState extends State<TimelineNavigator> {
  double _dragPosition = 0;
  bool _isDragging = false;
  TimelineEvent? _hoveredEvent;

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
    final events = _allEvents;
    if (events.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 40,
      child: Column(
          children: [
            // 시간 표시 (상단)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatTime(events.first.timestamp),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                ),
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
                      return Stack(
                        children: [
                          // 이벤트 마커들
                          ..._buildEventMarkers(events, height),
                          
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
            // 시간 표시 (하단)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatTime(events.last.timestamp),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                ),
              ),
            ),
          ],
        ),
    );
  }

  List<Widget> _buildEventMarkers(List<TimelineEvent> events, double height) {
    if (events.isEmpty) return [];

    final firstTime = events.first.timestamp.millisecondsSinceEpoch;
    final lastTime = events.last.timestamp.millisecondsSinceEpoch;
    final timeRange = lastTime - firstTime;

    if (timeRange == 0) {
      // 모든 이벤트가 같은 시간인 경우
      return [
        Positioned(
          top: height / 2 - 4,
          left: 4,
          right: 4,
          child: _buildMarker(events.first),
        ),
      ];
    }

    return events.map((event) {
      final progress = (event.timestamp.millisecondsSinceEpoch - firstTime) / timeRange;
      final top = progress * (height - 8);

      return Positioned(
        top: top.clamp(0, height - 8),
        left: 4,
        right: 4,
        child: GestureDetector(
          onTap: () => _jumpToEvent(event),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoveredEvent = event),
            onExit: (_) => setState(() => _hoveredEvent = null),
            child: Tooltip(
              message: '${_getEventTypeName(event.type)} - ${_formatDateTime(event.timestamp)}',
              child: _buildMarker(event),
            ),
          ),
        ),
      );
    }).toList();
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

  void _jumpToPosition(double tapY) {
    final events = _allEvents;
    if (events.isEmpty) return;

    // 탭 위치에 해당하는 이벤트 찾기
    final renderBox = context.findRenderObject() as RenderBox;
    final height = renderBox.size.height - 120; // 상하 여백 제외
    
    final progress = (tapY / height).clamp(0.0, 1.0);
    final index = (progress * (events.length - 1)).round();
    
    if (index >= 0 && index < events.length) {
      _jumpToEvent(events[index]);
    }
  }

  void _jumpToEvent(TimelineEvent event) {
    widget.onJump(Offset(event.x, event.y));
  }
}
