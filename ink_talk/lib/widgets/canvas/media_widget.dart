import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_colors.dart';
import '../../models/media_model.dart';

/// 미디어 오브젝트 위젯 (이미지/영상/PDF)
class MediaWidget extends StatefulWidget {
  final MediaModel media;
  final bool isSelected;
  /// true일 때만 크기 조정 핸들 표시 (롱프레스 → 크기 수정 선택 후)
  final bool isResizeMode;
  final Offset canvasOffset;
  final double canvasScale;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(Offset) onMove;
  /// (width, height, [x, y]) — 왼쪽/위쪽 핸들일 때 x,y 전달
  final void Function(double width, double height, {double? x, double? y})? onResize;

  const MediaWidget({
    super.key,
    required this.media,
    required this.isSelected,
    this.isResizeMode = false,
    required this.canvasOffset,
    required this.canvasScale,
    required this.onTap,
    required this.onLongPress,
    required this.onMove,
    this.onResize,
  });

  @override
  State<MediaWidget> createState() => _MediaWidgetState();
}

/// 크기 조정 핸들 위치
enum _ResizeHandle { none, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight }

class _MediaWidgetState extends State<MediaWidget> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _videoLoaded = false;
  int _currentPdfPage = 1;
  Offset? _dragStart;
  _ResizeHandle _resizeHandle = _ResizeHandle.none;
  double _resizeStartWidth = 0;
  double _resizeStartHeight = 0;
  double _resizeStartX = 0;
  double _resizeStartY = 0;

  static const double _handleSize = 14.0;
  static const double _minSize = 48.0;

  void _initVideoController() {
    if (_videoController != null) return;
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.media.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _videoLoaded = true);
      });
    _videoController!.addListener(() {
      if (_videoController!.value.isPlaying != _isPlaying && mounted) {
        setState(() => _isPlaying = _videoController!.value.isPlaying);
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.media.x * widget.canvasScale + widget.canvasOffset.dx;
    final y = widget.media.y * widget.canvasScale + widget.canvasOffset.dy;
    final width = widget.media.width * widget.canvasScale;
    final height = widget.media.height * widget.canvasScale;
    final locked = widget.media.isLocked;
    final showResize = widget.isResizeMode && !locked && widget.onResize != null;

    return Positioned(
      left: x,
      top: y,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onPanStart: (details) {
              if (showResize) {
                _resizeHandle = _hitTestHandle(details.localPosition, width, height);
                if (_resizeHandle != _ResizeHandle.none) {
                  _resizeStartWidth = widget.media.width;
                  _resizeStartHeight = widget.media.height;
                  _resizeStartX = widget.media.x;
                  _resizeStartY = widget.media.y;
                  return;
                }
              }
              if (!locked) _dragStart = details.localPosition;
            },
            onPanUpdate: (details) {
              if (_resizeHandle != _ResizeHandle.none) {
                final deltaCanvas = Offset(
                  details.delta.dx / widget.canvasScale,
                  details.delta.dy / widget.canvasScale,
                );
                double w = _resizeStartWidth;
                double h = _resizeStartHeight;
                double? newX;
                double? newY;
                switch (_resizeHandle) {
                  case _ResizeHandle.bottomRight:
                    w = (w + deltaCanvas.dx).clamp(_minSize, double.infinity);
                    h = (h + deltaCanvas.dy).clamp(_minSize, double.infinity);
                    break;
                  case _ResizeHandle.bottomLeft:
                    w = (w - deltaCanvas.dx).clamp(_minSize, double.infinity);
                    h = (h + deltaCanvas.dy).clamp(_minSize, double.infinity);
                    newX = _resizeStartX + (_resizeStartWidth - w);
                    break;
                  case _ResizeHandle.topRight:
                    w = (w + deltaCanvas.dx).clamp(_minSize, double.infinity);
                    h = (h - deltaCanvas.dy).clamp(_minSize, double.infinity);
                    newY = _resizeStartY + (_resizeStartHeight - h);
                    break;
                  case _ResizeHandle.topLeft:
                    w = (w - deltaCanvas.dx).clamp(_minSize, double.infinity);
                    h = (h - deltaCanvas.dy).clamp(_minSize, double.infinity);
                    newX = _resizeStartX + (_resizeStartWidth - w);
                    newY = _resizeStartY + (_resizeStartHeight - h);
                    break;
                  case _ResizeHandle.right:
                    w = (w + deltaCanvas.dx).clamp(_minSize, double.infinity);
                    break;
                  case _ResizeHandle.left:
                    w = (w - deltaCanvas.dx).clamp(_minSize, double.infinity);
                    newX = _resizeStartX + (_resizeStartWidth - w);
                    break;
                  case _ResizeHandle.bottom:
                    h = (h + deltaCanvas.dy).clamp(_minSize, double.infinity);
                    break;
                  case _ResizeHandle.top:
                    h = (h - deltaCanvas.dy).clamp(_minSize, double.infinity);
                    newY = _resizeStartY + (_resizeStartHeight - h);
                    break;
                  case _ResizeHandle.none:
                    break;
                }
                widget.onResize?.call(w, h, x: newX, y: newY);
                _resizeStartWidth = w;
                _resizeStartHeight = h;
                return;
              }
              if (!locked && _dragStart != null) {
                final delta = details.localPosition - _dragStart!;
                widget.onMove(Offset(
                  delta.dx / widget.canvasScale,
                  delta.dy / widget.canvasScale,
                ));
                _dragStart = details.localPosition;
              }
            },
            onPanEnd: (_) {
              _dragStart = null;
              _resizeHandle = _ResizeHandle.none;
            },
            child: Opacity(
              opacity: widget.media.opacity,
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  border: widget.isSelected
                      ? Border.all(
                          color: locked ? AppColors.mutedGray : AppColors.gold,
                          width: 2,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _buildMediaContent(),
                    ),
                    if (locked)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Icon(Icons.lock, size: 20, color: AppColors.gold),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (showResize) ..._buildResizeHandles(width, height),
        ],
      ),
    );
  }

  _ResizeHandle _hitTestHandle(Offset local, double w, double h) {
    if (local.dx <= _handleSize && local.dy <= _handleSize) return _ResizeHandle.topLeft;
    if (local.dx >= w - _handleSize && local.dy <= _handleSize) return _ResizeHandle.topRight;
    if (local.dx <= _handleSize && local.dy >= h - _handleSize) return _ResizeHandle.bottomLeft;
    if (local.dx >= w - _handleSize && local.dy >= h - _handleSize) return _ResizeHandle.bottomRight;
    if (local.dx <= _handleSize) return _ResizeHandle.left;
    if (local.dx >= w - _handleSize) return _ResizeHandle.right;
    if (local.dy <= _handleSize) return _ResizeHandle.top;
    if (local.dy >= h - _handleSize) return _ResizeHandle.bottom;
    return _ResizeHandle.none;
  }

  List<Widget> _buildResizeHandles(double width, double height) {
    final handles = <Widget>[];
    final positions = [
      [_ResizeHandle.topLeft, 0.0, 0.0],
      [_ResizeHandle.topRight, width - _handleSize, 0.0],
      [_ResizeHandle.bottomLeft, 0.0, height - _handleSize],
      [_ResizeHandle.bottomRight, width - _handleSize, height - _handleSize],
      [_ResizeHandle.top, width / 2 - _handleSize / 2, 0.0],
      [_ResizeHandle.bottom, width / 2 - _handleSize / 2, height - _handleSize],
      [_ResizeHandle.left, 0.0, height / 2 - _handleSize / 2],
      [_ResizeHandle.right, width - _handleSize, height / 2 - _handleSize / 2],
    ];
    for (final p in positions) {
      handles.add(
        Positioned(
          left: (p[1] as double),
          top: (p[2] as double),
          child: Container(
            width: _handleSize,
            height: _handleSize,
            decoration: BoxDecoration(
              color: AppColors.paper,
              border: Border.all(color: AppColors.gold, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }
    return handles;
  }

  Widget _buildMediaContent() {
    switch (widget.media.type) {
      case MediaType.image:
        return _buildImageContent();
      case MediaType.video:
        return _buildVideoContent();
      case MediaType.pdf:
        return _buildPdfContent();
    }
  }

  /// 썸네일 우선 로딩 후 원본 (캐시 사용)
  Widget _buildImageContent() {
    final thumbnailUrl = widget.media.thumbnailUrl;
    final imageUrl = widget.media.url;

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      memCacheWidth: thumbnailUrl != null ? 400 : null,
      memCacheHeight: thumbnailUrl != null ? 400 : null,
      placeholder: (context, url) => Container(
        color: AppColors.mutedGray.withValues(alpha: 0.2),
        child: thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.image_not_supported),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
      ),
      errorWidget: (context, url, error) => Container(
        color: AppColors.mutedGray.withValues(alpha: 0.2),
        child: const Center(
          child: Icon(Icons.broken_image, color: AppColors.mutedGray),
        ),
      ),
    );
  }

  /// 썸네일 우선 표시, 재생 탭 시 원본 로딩
  Widget _buildVideoContent() {
    final hasThumbnail = widget.media.thumbnailUrl != null;

    return Stack(
      children: [
        // 썸네일 우선 또는 로딩
        if (!_videoLoaded || _videoController == null || !_videoController!.value.isInitialized)
          Container(
            color: Colors.black,
            child: hasThumbnail
                ? CachedNetworkImage(
                    imageUrl: widget.media.thumbnailUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    ),
                  )
                : const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  ),
          )
        else
          AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),

        // 재생 버튼 (탭 시 원본 로딩 시작)
        Positioned.fill(
          child: Center(
            child: IconButton(
              onPressed: () {
                _initVideoController();
                if (_videoController != null && _videoController!.value.isInitialized) {
                  if (_isPlaying) {
                    _videoController!.pause();
                  } else {
                    _videoController!.play();
                  }
                }
              },
              icon: Icon(
                _isPlaying ? Icons.pause_circle : Icons.play_circle,
                size: 48,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),

        if (_videoLoaded &&
            _videoController != null &&
            _videoController!.value.isInitialized)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              _videoController!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: AppColors.gold,
                bufferedColor: AppColors.mutedGray,
                backgroundColor: Colors.black26,
              ),
            ),
          ),
      ],
    );
  }

  void _showPdfPagePanel() {
    final totalPages = widget.media.totalPages ?? 1;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.paper,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('펼쳐보기', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.8,
                ),
                itemCount: totalPages,
                itemBuilder: (context, index) {
                  final page = index + 1;
                  final isCurrent = page == _currentPdfPage;
                  return InkWell(
                    onTap: () {
                      setState(() => _currentPdfPage = page);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isCurrent ? AppColors.gold : AppColors.border,
                          width: isCurrent ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          '$page',
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : null,
                            color: isCurrent ? AppColors.gold : AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfContent() {
    final totalPages = widget.media.totalPages ?? 1;

    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          // PDF 내용 (실제 렌더링은 별도 패키지 필요)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.picture_as_pdf, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text(
                  widget.media.fileName,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '페이지 $_currentPdfPage / $totalPages',
                  style: const TextStyle(fontSize: 10, color: AppColors.mutedGray),
                ),
                TextButton.icon(
                  onPressed: _showPdfPagePanel,
                  icon: const Icon(Icons.grid_view, size: 18),
                  label: const Text('펼쳐보기'),
                ),
              ],
            ),
          ),

          // 페이지 넘김 버튼 (왼쪽)
          if (_currentPdfPage > 1)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      _currentPdfPage--;
                    });
                  },
                  icon: Icon(
                    Icons.chevron_left,
                    color: AppColors.ink.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),

          // 페이지 넘김 버튼 (오른쪽)
          if (_currentPdfPage < totalPages)
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      _currentPdfPage++;
                    });
                  },
                  icon: Icon(
                    Icons.chevron_right,
                    color: AppColors.ink.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
