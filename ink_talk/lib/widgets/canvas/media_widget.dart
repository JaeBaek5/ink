import 'dart:math' as math;
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
  /// 누르기 시작 시 (3초 길게 누르기 타이머 등용)
  final VoidCallback? onTapDown;
  /// 손을 뗐을 때
  final VoidCallback? onTapUp;
  /// 제스처 취소 시
  final VoidCallback? onTapCancel;
  final Function(Offset) onMove;
  /// (width, height, [x, y]) — 왼쪽/위쪽 핸들일 때 x,y 전달
  final void Function(double width, double height, {double? x, double? y})? onResize;
  /// 크기 조정 핸들 드래그를 끝냈을 때 (핸들 숨기기용)
  final VoidCallback? onResizeEnd;
  /// 회전 (도 단위, 오브젝트 중심 기준)
  final void Function(double angleDegrees)? onRotate;
  /// 기울이기 (도 단위, skewX, skewY)
  final void Function(double skewXDegrees, double skewYDegrees)? onSkew;
  /// true면 포인터 이벤트 무시(캔버스로 통과) — 펜/지우개 모드에서 사진 위 그리기·떨림 방지
  final bool ignorePointer;

  const MediaWidget({
    super.key,
    required this.media,
    required this.isSelected,
    this.isResizeMode = false,
    required this.canvasOffset,
    required this.canvasScale,
    required this.onTap,
    required this.onLongPress,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    required this.onMove,
    this.onResize,
    this.onResizeEnd,
    this.onRotate,
    this.onSkew,
    this.ignorePointer = false,
  });

  @override
  State<MediaWidget> createState() => _MediaWidgetState();
}

class _MediaWidgetState extends State<MediaWidget> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _videoLoaded = false;
  int _currentPdfPage = 1;
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
    final angleRad = widget.media.angleDegrees * math.pi / 180;
    final skewXRad = math.tan(widget.media.skewXDegrees * math.pi / 180);
    final skewYRad = math.tan(widget.media.skewYDegrees * math.pi / 180);
    final skewTransform = Matrix4.identity()
      ..setEntry(0, 1, skewXRad)
      ..setEntry(1, 0, skewYRad);
    final flipTransform = Matrix4.diagonal3Values(
      widget.media.flipHorizontal ? -1.0 : 1.0,
      widget.media.flipVertical ? -1.0 : 1.0,
      1.0,
    );

    return Positioned(
      left: x,
      top: y,
      child: Transform.rotate(
        angle: angleRad,
        alignment: Alignment.center,
        child: SizedBox(
          width: width,
          height: height,
          child: IgnorePointer(
            ignoring: widget.ignorePointer,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onTapDown: widget.onTapDown != null ? (_) => widget.onTapDown!() : null,
            onTapUp: widget.onTapUp != null ? (_) => widget.onTapUp!() : null,
            onTapCancel: widget.onTapCancel != null ? () => widget.onTapCancel!() : null,
            // 본체 이동은 상위 단일 제스처 라우터에서 처리 (onPan 제거 → 경쟁 제거, S노트 스타일)
            child: Transform(
              alignment: Alignment.center,
              transform: skewTransform,
              child: Transform(
                alignment: Alignment.center,
                transform: flipTransform,
                child: Opacity(
                opacity: widget.media.opacity,
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    border: widget.isSelected
                        ? Border.all(
                            color: locked ? AppColors.mutedGray : AppColors.mediaActive,
                            width: 2,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: _buildMediaContent(),
                        ),
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
            ),
          ),
        ],
        ),
          ),
        ),
      ),
    );
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

  /// 썸네일 우선 로딩 후 원본 (캐시 사용). 크기 변경 시 리빌드되어 박스에 맞게 채움.
  Widget _buildImageContent() {
    final thumbnailUrl = widget.media.thumbnailUrl;
    final imageUrl = widget.media.url;

    return CachedNetworkImage(
      key: ValueKey('img_${widget.media.id}_${widget.media.width}_${widget.media.height}'),
      imageUrl: imageUrl,
      fit: BoxFit.fill,
      memCacheWidth: thumbnailUrl != null ? 400 : null,
      memCacheHeight: thumbnailUrl != null ? 400 : null,
      placeholder: (context, url) => Container(
        color: AppColors.mutedGray.withValues(alpha: 0.2),
        child: thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: thumbnailUrl,
                fit: BoxFit.fill,
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
