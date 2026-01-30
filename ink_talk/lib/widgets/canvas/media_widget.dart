import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/app_colors.dart';
import '../../models/media_model.dart';

/// 미디어 오브젝트 위젯 (이미지/영상/PDF)
class MediaWidget extends StatefulWidget {
  final MediaModel media;
  final bool isSelected;
  final Offset canvasOffset;
  final double canvasScale;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(Offset) onMove;

  const MediaWidget({
    super.key,
    required this.media,
    required this.isSelected,
    required this.canvasOffset,
    required this.canvasScale,
    required this.onTap,
    required this.onLongPress,
    required this.onMove,
  });

  @override
  State<MediaWidget> createState() => _MediaWidgetState();
}

class _MediaWidgetState extends State<MediaWidget> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  int _currentPdfPage = 1;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    if (widget.media.type == MediaType.video) {
      _initVideoController();
    }
  }

  void _initVideoController() {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.media.url))
      ..initialize().then((_) {
        setState(() {});
      });
    _videoController!.addListener(() {
      if (_videoController!.value.isPlaying != _isPlaying) {
        setState(() {
          _isPlaying = _videoController!.value.isPlaying;
        });
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
    // 캔버스 좌표 변환
    final x = widget.media.x * widget.canvasScale + widget.canvasOffset.dx;
    final y = widget.media.y * widget.canvasScale + widget.canvasOffset.dy;
    final width = widget.media.width * widget.canvasScale;
    final height = widget.media.height * widget.canvasScale;

    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onPanStart: (details) {
          _dragStart = details.localPosition;
        },
        onPanUpdate: (details) {
          if (_dragStart != null) {
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
        },
        child: Opacity(
          opacity: widget.media.opacity,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              border: widget.isSelected
                  ? Border.all(color: AppColors.gold, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _buildMediaContent(),
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

  Widget _buildImageContent() {
    return Image.network(
      widget.media.url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: AppColors.mutedGray.withValues(alpha: 0.2),
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: AppColors.mutedGray.withValues(alpha: 0.2),
          child: const Center(
            child: Icon(Icons.broken_image, color: AppColors.mutedGray),
          ),
        );
      },
    );
  }

  Widget _buildVideoContent() {
    return Stack(
      children: [
        // 비디오 플레이어 또는 썸네일
        if (_videoController != null && _videoController!.value.isInitialized)
          AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          )
        else
          Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            ),
          ),

        // 재생 버튼
        Positioned.fill(
          child: Center(
            child: IconButton(
              onPressed: () {
                if (_videoController == null) return;
                if (_isPlaying) {
                  _videoController!.pause();
                } else {
                  _videoController!.play();
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

        // 재생 바
        if (_videoController != null && _videoController!.value.isInitialized)
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
