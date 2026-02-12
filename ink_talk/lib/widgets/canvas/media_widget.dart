import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'video_cache_stub.dart' if (dart.library.io) 'video_cache_io.dart' as video_cache;
import 'pdf_cache_stub.dart' if (dart.library.io) 'pdf_cache_io.dart' as pdf_cache;
import 'package:pdfx/pdfx.dart';
import '../../core/constants/app_colors.dart';
import '../../models/media_model.dart';
import '../../screens/canvas/canvas_controller.dart';

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
  /// PDF일 때만: 한 페이지(화살표) vs 그리드 (null이면 singlePage)
  final PdfViewMode? pdfViewMode;
  /// PDF 현재 페이지 (1-based). 화살표는 캔버스 밖에서 제어.
  final int pdfCurrentPage;
  /// PDF 페이지가 바뀔 때 (스와이프 또는 화살표)
  final void Function(int page)? onPdfPageChanged;
  /// PDF 로드 완료 시 총 페이지 수 알림
  final void Function(int count)? onPdfPageCountLoaded;
  /// 이미지 자르기 영역 (정규화 0~1). null이면 전체 표시.
  final Rect? cropRect;

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
    this.pdfViewMode,
    this.pdfCurrentPage = 1,
    this.onPdfPageChanged,
    this.onPdfPageCountLoaded,
    this.cropRect,
  });

  @override
  State<MediaWidget> createState() => _MediaWidgetState();
}

class _MediaWidgetState extends State<MediaWidget> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _videoLoaded = false;
  bool _playWhenReady = false; // 로딩 완료 후 자동 재생
  bool _isMuted = false;
  int _currentPdfPage = 1;
  PdfController? _pdfController;
  Future<PdfDocument>? _pdfDocumentFuture;
  int? _pdfPagesCount;
  Object? _pdfLoadError;
  bool _pdfLoadStarted = false;

  @override
  void initState() {
    super.initState();
    if (widget.media.type == MediaType.pdf) _initPdf();
    if (widget.media.type == MediaType.video) _preloadVideo();
  }

  @override
  void didUpdateWidget(MediaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.media.type == MediaType.pdf &&
        widget.pdfCurrentPage != oldWidget.pdfCurrentPage &&
        widget.pdfCurrentPage != _currentPdfPage &&
        _pdfController != null) {
      final total = _pdfPagesCount ?? 1;
      final page = widget.pdfCurrentPage.clamp(1, total);
      _pdfController!.jumpToPage(page);
      _currentPdfPage = page;
    }
  }

  Future<void> _initPdf() async {
    if (_pdfLoadStarted) return;
    _pdfLoadStarted = true;
    final url = widget.media.url;
    try {
      // 캐시 먼저 사용(방 나갔다 와도 재다운로드 없음)
      final cachedBytes = await pdf_cache.getPdfBytesFromCache(url);
      final List<int> bytes;
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        bytes = cachedBytes;
      } else {
        final response = await http.get(Uri.parse(url));
        if (!mounted) return;
        if (response.statusCode != 200) {
          throw Exception('PDF 로드 실패: ${response.statusCode}');
        }
        bytes = response.bodyBytes;
        pdf_cache.cachePdfBytes(url, bytes);
      }
      final docFuture = PdfDocument.openData(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      );
      _pdfDocumentFuture = docFuture;
      final doc = await docFuture;
      if (!mounted) return;
      _pdfPagesCount = doc.pagesCount;
      widget.onPdfPageCountLoaded?.call(doc.pagesCount);
      final totalPages = _pdfPagesCount ?? widget.media.totalPages ?? 1;
      final initialPage = widget.pdfCurrentPage.clamp(1, totalPages);
      _currentPdfPage = initialPage;
      if (!mounted) return;
      _pdfController = PdfController(
        document: docFuture,
        initialPage: initialPage,
      );
      if (mounted) setState(() {});
    } catch (e) {
      _pdfLoadError = e;
      if (mounted) setState(() {});
    }
  }

  /// 영상: 기기 캐시에서 재생 (한 번 받으면 저장, 다음엔 로컬에서 재생). 웹은 네트워크만.
  void _preloadVideo() {
    if (_videoController != null) return;
    final playWhenReady = _playWhenReady;
    final url = widget.media.url;

    video_cache.createVideoControllerFromCache(url).then((VideoPlayerController? controller) {
      if (!mounted || _videoController != null) return;
      if (controller != null) {
        _videoController = controller;
        controller.addListener(() {
          if (controller.value.isPlaying != _isPlaying && mounted) {
            setState(() => _isPlaying = controller.value.isPlaying);
          }
        });
        controller.initialize().then((_) {
          if (!mounted || _videoController != controller) return;
          setState(() => _videoLoaded = true);
          if (_playWhenReady) {
            _playWhenReady = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _videoController == controller && controller.value.isInitialized) {
                controller.play();
              }
            });
          }
        }).catchError((Object e, StackTrace st) {
          if (mounted && _videoController == controller) {
            setState(() => _videoLoaded = false);
            _playWhenReady = false;
          }
        });
      } else {
        _playWhenReady = playWhenReady;
        _initVideoFromNetwork();
      }
    }).catchError((Object e, StackTrace st) {
      if (!mounted || _videoController != null) return;
      _playWhenReady = playWhenReady;
      _initVideoFromNetwork();
    });
  }

  /// 캐시 실패 시 네트워크 URL로 직접 재생 (폴백) — 백그라운드에서 캐시해 두 번째 재생부터 로컬 사용
  void _initVideoFromNetwork() {
    if (_videoController != null) return;
    video_cache.cacheVideoInBackground(widget.media.url);
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
    _videoController = controller;
    controller.addListener(() {
      if (controller.value.isPlaying != _isPlaying && mounted) {
        setState(() => _isPlaying = controller.value.isPlaying);
      }
    });
    controller.initialize().then((_) {
      if (!mounted || _videoController != controller) return;
      setState(() => _videoLoaded = true);
      if (_playWhenReady) {
        _playWhenReady = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _videoController == controller && controller.value.isInitialized) {
            controller.play();
          }
        });
      }
    }).catchError((Object e, StackTrace st) {
      if (mounted && _videoController == controller) {
        setState(() => _videoLoaded = false);
        _playWhenReady = false;
      }
    });
  }

  /// 재생 버튼 탭: 이미 초기화됐으면 바로 재생/일시정지, 아니면 초기화 후 재생
  void _initVideoController() {
    if (_videoController != null) {
      if (_videoController!.value.isInitialized) {
        if (_isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
      } else {
        _playWhenReady = true;
        if (mounted) setState(() {});
      }
      return;
    }
    _playWhenReady = true;
    _preloadVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pdfController?.dispose();
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

    const kVideoTimelineHeight = 18.0;
    final isVideo = widget.media.type == MediaType.video;
    final totalHeight = isVideo ? height + kVideoTimelineHeight : height;

    return Positioned(
      left: x,
      top: y,
      child: Transform.rotate(
        angle: angleRad,
        alignment: Alignment.center,
        child: SizedBox(
          width: width,
          height: totalHeight,
          child: isVideo
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
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
                    SizedBox(
                      height: kVideoTimelineHeight,
                      child: _videoLoaded &&
                              _videoController != null &&
                              _videoController!.value.isInitialized
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                color: Colors.black26,
                                width: double.infinity,
                                height: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: ValueListenableBuilder<VideoPlayerValue>(
                                  valueListenable: _videoController!,
                                  builder: (context, value, _) {
                                    final pos = value.position;
                                    final dur = value.duration;
                                    final posStr = '${pos.inMinutes.remainder(60).toString().padLeft(2, '0')}:${pos.inSeconds.remainder(60).toString().padLeft(2, '0')}';
                                    final durStr = dur.inMilliseconds > 0
                                        ? '${dur.inMinutes.remainder(60).toString().padLeft(2, '0')}:${dur.inSeconds.remainder(60).toString().padLeft(2, '0')}'
                                        : '--:--';
                                    return Row(
                                      children: [
                                        SizedBox(
                                          width: 32,
                                          child: Text(
                                            posStr,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white70,
                                              fontFeatures: [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: VideoProgressIndicator(
                                            _videoController!,
                                            allowScrubbing: true,
                                            colors: const VideoProgressColors(
                                              playedColor: AppColors.gold,
                                              bufferedColor: AppColors.mutedGray,
                                              backgroundColor: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 32,
                                          child: Text(
                                            durStr,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white70,
                                              fontFeatures: [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                )
              : IgnorePointer(
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

  /// 썸네일 우선 로딩 후 원본 (캐시 사용). cropRect가 있으면 해당 영역만 표시.
  Widget _buildImageContent() {
    final thumbnailUrl = widget.media.thumbnailUrl;
    final imageUrl = widget.media.url;
    final r = widget.cropRect;

    final imageWidget = CachedNetworkImage(
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

    if (r == null || (r.left == 0 && r.top == 0 && r.right == 1 && r.bottom == 1)) {
      return imageWidget;
    }
    final w = r.right - r.left;
    final h = r.bottom - r.top;
    if (w <= 0 || h <= 0) return imageWidget;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -cw * r.left / w,
                top: -ch * r.top / h,
                width: cw / w,
                height: ch / h,
                child: imageWidget,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 썸네일만 먼저 표시, 재생 탭 시에만 영상 로딩 (로딩 시간 단축)
  Widget _buildVideoContent() {
    final hasThumbnail = widget.media.thumbnailUrl != null;

    return Stack(
      children: [
        // 썸네일 또는 플레이스홀더 (영상은 재생 탭 시에만 로드)
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
                      child: Icon(Icons.videocam, size: 48, color: AppColors.mutedGray),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.videocam_off, size: 48, color: AppColors.mutedGray),
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam, size: 48, color: AppColors.mutedGray),
                        SizedBox(height: 8),
                        Text('영상', style: TextStyle(color: AppColors.mutedGray, fontSize: 12)),
                      ],
                    ),
                  ),
          )
        else ...[
          SizedBox.expand(), // Stack이 박스와 같은 크기를 쓰도록
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          ),
        ],

        // 재생/일시정지: 재생 중 터치 → 일시정지 후 재생·음소거 버튼 표시
        Positioned.fill(
          child: IgnorePointer(
            ignoring: widget.isResizeMode,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _initVideoController(),
              child: _isPlaying
                  ? const SizedBox.expand()
                  : Center(
                      child: Icon(
                        Icons.play_circle,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
            ),
          ),
        ),

        // 영상 로딩 중일 때만 스피너 (재생 탭 후)
        if (_videoController != null && !_videoController!.value.isInitialized)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.gold),
                  SizedBox(height: 12),
                  Text('영상 불러오는 중...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),

        if (_videoLoaded &&
            _videoController != null &&
            _videoController!.value.isInitialized &&
            !_isPlaying) ...[
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () {
                  if (_videoController == null || !_videoController!.value.isInitialized) return;
                  setState(() {
                    _isMuted = !_isMuted;
                    _videoController!.setVolume(_isMuted ? 0 : 1);
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPdfContent() {
    if (_pdfLoadError != null) {
      return Container(
        color: Colors.white,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.picture_as_pdf, size: 48, color: AppColors.mutedGray),
                  const SizedBox(height: 8),
                  Text(
                    widget.media.fileName,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PDF를 불러올 수 없습니다.',
                    style: TextStyle(fontSize: 11, color: AppColors.mutedGray),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_pdfController == null) {
      return Container(
        color: Colors.white,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.gold),
                SizedBox(height: 12),
                Text('PDF 불러오는 중...', style: TextStyle(fontSize: 12, color: AppColors.mutedGray)),
              ],
            ),
          ),
        ),
      );
    }

    final mode = widget.pdfViewMode ?? PdfViewMode.singlePage;
    final totalPages = _pdfPagesCount ?? widget.media.totalPages ?? 1;

    if (mode == PdfViewMode.grid && _pdfDocumentFuture != null) {
      return Container(
        color: Colors.white,
        child: ClipRect(
          clipBehavior: Clip.hardEdge,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.7,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            padding: const EdgeInsets.all(4),
            itemCount: totalPages,
            itemBuilder: (context, index) {
              return _PdfPageCell(
                key: ValueKey('pdf_page_${widget.media.id}_${index + 1}'),
                documentFuture: _pdfDocumentFuture!,
                pageNumber: index + 1,
              );
            },
          ),
        ),
      );
    }

    final pdfView = PdfView(
      controller: _pdfController!,
      onPageChanged: (page) {
        if (mounted && page != _currentPdfPage) {
          setState(() => _currentPdfPage = page);
          widget.onPdfPageChanged?.call(page);
        }
      },
      onDocumentLoaded: (document) {
        if (mounted) {
          setState(() => _pdfPagesCount = document.pagesCount);
          widget.onPdfPageCountLoaded?.call(document.pagesCount);
        }
      },
      builders: PdfViewBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
        pageLoaderBuilder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      ),
    );

    // 화살표는 캔버스 오버레이(박스 밖)에 표시됨
    return Container(
      color: Colors.white,
      child: pdfView,
    );
  }
}

/// 그리드 모드에서 한 페이지만 표시하는 셀 (각 페이지별 PdfController 사용)
class _PdfPageCell extends StatefulWidget {
  final Future<PdfDocument> documentFuture;
  final int pageNumber;

  const _PdfPageCell({
    super.key,
    required this.documentFuture,
    required this.pageNumber,
  });

  @override
  State<_PdfPageCell> createState() => _PdfPageCellState();
}

class _PdfPageCellState extends State<_PdfPageCell> {
  PdfController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfController(
      document: widget.documentFuture,
      initialPage: widget.pageNumber,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: PdfView(
          controller: _controller!,
          builders: PdfViewBuilders<DefaultBuilderOptions>(
            options: const DefaultBuilderOptions(),
            documentLoaderBuilder: (_) => const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
              ),
            ),
            pageLoaderBuilder: (_) => const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
