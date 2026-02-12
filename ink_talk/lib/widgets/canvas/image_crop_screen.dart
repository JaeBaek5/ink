import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../../core/constants/app_colors.dart';
import '../../models/media_model.dart';

/// 이미지 자르기 화면. 정규화(0~1) crop rect 반환.
class ImageCropScreen extends StatefulWidget {
  final MediaModel media;
  final Rect? initialCropRect;
  final void Function(Rect rect) onConfirm;
  final VoidCallback onCancel;

  const ImageCropScreen({
    super.key,
    required this.media,
    this.initialCropRect,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  double? _imageWidth;
  double? _imageHeight;
  Object? _loadError;
  bool _loading = true;

  late double _left;
  late double _top;
  late double _right;
  late double _bottom;

  @override
  void initState() {
    super.initState();
    final init = widget.initialCropRect;
    if (init != null) {
      _left = init.left.clamp(0.0, 1.0);
      _top = init.top.clamp(0.0, 1.0);
      _right = init.right.clamp(0.0, 1.0);
      _bottom = init.bottom.clamp(0.0, 1.0);
    } else {
      _left = 0;
      _top = 0;
      _right = 1;
      _bottom = 1;
    }
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final response = await http.get(Uri.parse(widget.media.url));
      if (!mounted) return;
      if (response.statusCode != 200) {
        throw Exception('이미지를 불러올 수 없습니다.');
      }
      final decoded = img.decodeImage(response.bodyBytes);
      if (!mounted) return;
      if (decoded == null) {
        setState(() {
          _loadError = Exception('이미지 형식을 인식할 수 없습니다.');
          _loading = false;
        });
        return;
      }
      setState(() {
        _imageWidth = decoded.width.toDouble();
        _imageHeight = decoded.height.toDouble();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  Rect get _cropRect => Rect.fromLTRB(_left, _top, _right, _bottom);

  void _applyCrop() {
    widget.onConfirm(_cropRect);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('자르기', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            widget.onCancel();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: _loading || _loadError != null ? null : _applyCrop,
            child: const Text('적용', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 48, color: AppColors.mutedGray),
            const SizedBox(height: 16),
            Text(
              _loadError.toString().replaceFirst('Exception: ', ''),
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final w = _imageWidth!;
    final h = _imageHeight!;
    return LayoutBuilder(
      builder: (context, constraints) {
        return _CropOverlay(
          imageUrl: widget.media.url,
          imageAspectRatio: w / h,
          cropLeft: _left,
          cropTop: _top,
          cropRight: _right,
          cropBottom: _bottom,
          availableWidth: constraints.maxWidth,
          availableHeight: constraints.maxHeight,
          onCropChanged: (l, t, r, b) {
            setState(() {
              _left = l;
              _top = t;
              _right = r;
              _bottom = b;
            });
          },
        );
      },
    );
  }
}

/// 이미지 + 크롭 오버레이 (드래그로 영역 조절)
class _CropOverlay extends StatefulWidget {
  final String imageUrl;
  final double imageAspectRatio;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final double availableWidth;
  final double availableHeight;
  final void Function(double left, double top, double right, double bottom) onCropChanged;

  const _CropOverlay({
    required this.imageUrl,
    required this.imageAspectRatio,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.availableWidth,
    required this.availableHeight,
    required this.onCropChanged,
  });

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  static const _minSize = 0.1;
  static const _handleSize = 32.0;

  late double _left;
  late double _top;
  late double _right;
  late double _bottom;

  @override
  void initState() {
    super.initState();
    _left = widget.cropLeft;
    _top = widget.cropTop;
    _right = widget.cropRight;
    _bottom = widget.cropBottom;
  }

  @override
  void didUpdateWidget(_CropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cropLeft != widget.cropLeft || oldWidget.cropTop != widget.cropTop ||
        oldWidget.cropRight != widget.cropRight || oldWidget.cropBottom != widget.cropBottom) {
      _left = widget.cropLeft;
      _top = widget.cropTop;
      _right = widget.cropRight;
      _bottom = widget.cropBottom;
    }
  }

  void _normalize() {
    final l = _left.clamp(0.0, 1.0);
    final t = _top.clamp(0.0, 1.0);
    final r = _right.clamp(0.0, 1.0);
    final b = _bottom.clamp(0.0, 1.0);
    final w = (r - l).clamp(_minSize, 1.0);
    final h = (b - t).clamp(_minSize, 1.0);
    _left = (r - w).clamp(0.0, 1.0);
    _top = (b - h).clamp(0.0, 1.0);
    _right = _left + w;
    _bottom = _top + h;
    widget.onCropChanged(_left, _top, _right, _bottom);
  }

  static const _imagePadding = 48.0; // 사진 주변 여백 (2배)

  @override
  Widget build(BuildContext context) {
    final availableWidth = widget.availableWidth;
    final availableHeight = widget.availableHeight;
    final innerWidth = (availableWidth - 2 * _imagePadding).clamp(1.0, double.infinity);
    final innerHeight = (availableHeight - 2 * _imagePadding).clamp(1.0, double.infinity);

    // 이미지가 들어가는 영역 (여백 안에서 BoxFit.contain)
    double imageW = innerWidth;
    double imageH = innerHeight;
    if (widget.imageAspectRatio > innerWidth / innerHeight) {
      imageH = innerWidth / widget.imageAspectRatio;
    } else {
      imageW = innerHeight * widget.imageAspectRatio;
    }
    final imageRect = Rect.fromLTWH(
      _imagePadding + (innerWidth - imageW) / 2,
      _imagePadding + (innerHeight - imageH) / 2,
      imageW,
      imageH,
    );

    double left = imageRect.left + _left * imageRect.width;
    double top = imageRect.top + _top * imageRect.height;
    double right = imageRect.left + _right * imageRect.width;
    double bottom = imageRect.top + _bottom * imageRect.height;

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      panEnabled: true,
      boundaryMargin: const EdgeInsets.all(80),
      child: SizedBox(
        width: availableWidth,
        height: availableHeight,
        child: Stack(
          children: [
        // 이미지 (전체 영역에 contain)
        Positioned(
          left: imageRect.left,
          top: imageRect.top,
          width: imageRect.width,
          height: imageRect.height,
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
              );
            },
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
            ),
          ),
        ),
        // 어두운 마스크 + 투명 crop 영역 (터치 통과시켜 줌된 뷰 이동 가능)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CropMaskPainter(
              imageRect: imageRect,
              cropLeft: _left,
              cropTop: _top,
              cropRight: _right,
              cropBottom: _bottom,
            ),
            ),
          ),
        ),
        // crop 영역 전체 드래그로 이동 (panEnabled: false라서 제스처 경쟁 없음)
        Positioned(
          left: left,
          top: top,
          width: (right - left).clamp(1.0, double.infinity),
          height: (bottom - top).clamp(1.0, double.infinity),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) {
              final dxNorm = d.delta.dx / imageRect.width;
              final dyNorm = d.delta.dy / imageRect.height;
              double nl = _left + dxNorm;
              double nt = _top + dyNorm;
              double nr = _right + dxNorm;
              double nb = _bottom + dyNorm;
              final w = _right - _left;
              final h = _bottom - _top;
              if (nl < 0) { nl = 0; nr = w; }
              if (nr > 1) { nr = 1; nl = 1 - w; }
              if (nt < 0) { nt = 0; nb = h; }
              if (nb > 1) { nb = 1; nt = 1 - h; }
              setState(() {
                _left = nl;
                _top = nt;
                _right = nr;
                _bottom = nb;
              });
              widget.onCropChanged(_left, _top, _right, _bottom);
            },
          ),
        ),
        // 모서리 핸들 (4 코너)
        _buildHandle(imageRect, left, top, _handleSize, (dx, dy) {
          final nl = (_left + dx / imageRect.width).clamp(0.0, _right - _minSize);
          final nt = (_top + dy / imageRect.height).clamp(0.0, _bottom - _minSize);
          setState(() {
            _left = nl;
            _top = nt;
          });
          _normalize();
        }),
        _buildHandle(imageRect, right, top, _handleSize, (dx, dy) {
          final nr = (_right + dx / imageRect.width).clamp(_left + _minSize, 1.0);
          final nt = (_top + dy / imageRect.height).clamp(0.0, _bottom - _minSize);
          setState(() {
            _right = nr;
            _top = nt;
          });
          _normalize();
        }),
        _buildHandle(imageRect, left, bottom, _handleSize, (dx, dy) {
          final nl = (_left + dx / imageRect.width).clamp(0.0, _right - _minSize);
          final nb = (_bottom + dy / imageRect.height).clamp(_top + _minSize, 1.0);
          setState(() {
            _left = nl;
            _bottom = nb;
          });
          _normalize();
        }),
        _buildHandle(imageRect, right, bottom, _handleSize, (dx, dy) {
          final nr = (_right + dx / imageRect.width).clamp(_left + _minSize, 1.0);
          final nb = (_bottom + dy / imageRect.height).clamp(_top + _minSize, 1.0);
          setState(() {
            _right = nr;
            _bottom = nb;
          });
          _normalize();
        }),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle(Rect imageRect, double x, double y, double size, void Function(double dx, double dy) onPan) {
    return Positioned(
      left: x - size / 2,
      top: y - size / 2,
      width: size,
      height: size,
      child: GestureDetector(
        onPanUpdate: (d) {
          final dx = d.delta.dx;
          final dy = d.delta.dy;
          onPan(dx, dy);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.gold, width: 2),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  final Rect imageRect;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;

  _CropMaskPainter({
    required this.imageRect,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()..color = Colors.black54;
    final cropL = imageRect.left + cropLeft * imageRect.width;
    final cropT = imageRect.top + cropTop * imageRect.height;
    final cropR = imageRect.left + cropRight * imageRect.width;
    final cropB = imageRect.top + cropBottom * imageRect.height;
    final cropRect = Rect.fromLTRB(cropL, cropT, cropR, cropB);

    // 전체에서 crop 영역만 뺀 경로에 어두운 색 채우기 (evenOdd로 구멍)
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dark);

    // crop 테두리
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, border);
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter old) {
    return old.cropLeft != cropLeft || old.cropTop != cropTop ||
        old.cropRight != cropRight || old.cropBottom != cropBottom ||
        old.imageRect != imageRect;
  }
}
