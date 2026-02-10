import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/settings_service.dart';

/// 기본 펜 설정 화면 (캔버스 진입 시 펜1에 적용되는 색·굵기)
class DefaultPenScreen extends StatefulWidget {
  const DefaultPenScreen({super.key});

  @override
  State<DefaultPenScreen> createState() => _DefaultPenScreenState();
}

class _DefaultPenScreenState extends State<DefaultPenScreen> {
  final _settings = SettingsService();
  int? _savedColorValue;
  double? _savedWidth;
  bool _loading = true;

  static const List<Color> _presetColors = [
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.pink,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.brown,
    Colors.grey,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final colorValue = await _settings.getDefaultPenColorValue();
    final width = await _settings.getDefaultPenWidth();
    if (mounted) {
      setState(() {
        _savedColorValue = colorValue;
        _savedWidth = width;
        _loading = false;
      });
    }
  }

  Color get _currentColor {
    if (_savedColorValue != null) return Color(_savedColorValue!);
    return Colors.black;
  }

  double get _currentWidth => _savedWidth ?? 2.0;

  Future<void> _setColor(Color color) async {
    setState(() => _savedColorValue = color.value);
    await _settings.setDefaultPenColorValue(color.value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기본 펜 색상을 저장했습니다.')),
      );
    }
  }

  Future<void> _setWidth(double width, {bool showSnackBar = true}) async {
    final clamped = width.clamp(1.0, 24.0);
    setState(() => _savedWidth = clamped);
    await _settings.setDefaultPenWidth(clamped);
    if (mounted && showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('기본 펜 굵기를 ${clamped.toStringAsFixed(1)}로 저장했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('기본 펜 설정')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('기본 펜 설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '캔버스에 들어갈 때 펜(첫 번째 도구)에 적용되는 기본 색과 굵기입니다.',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '기본 색상',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _presetColors.map((color) {
              final isSelected = _savedColorValue != null && Color(_savedColorValue!) == color;
              return GestureDetector(
                onTap: () => _setColor(color),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.gold : colorScheme.outline,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          Text(
            '기본 굵기',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _currentWidth,
                  min: 1,
                  max: 24,
                  divisions: 23,
                  activeColor: AppColors.gold,
                  onChanged: (v) => _setWidth(v, showSnackBar: false),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${_currentWidth.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              child: CustomPaint(
                size: const Size(80, 80),
                painter: _PreviewPainter(
                  color: _currentColor,
                  strokeWidth: _currentWidth,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _PreviewPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.5),
      Offset(size.width * 0.8, size.height * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
