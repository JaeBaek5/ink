import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/shape_model.dart';
import '../../screens/canvas/canvas_controller.dart';

/// 우측 속성 패널 (문서 스펙: 현재 도구의 옵션)
class PropertiesPanel extends StatelessWidget {
  final CanvasController controller;

  const PropertiesPanel({super.key, required this.controller});

  static const double _panelWidth = 240;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _panelWidth,
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(
          left: BorderSide(color: AppColors.border),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.currentPen == PenType.eraser) _buildEraserOptions(context),
          if (controller.inputMode == InputMode.shape) _buildShapeOptions(context),
          if (controller.inputMode == InputMode.text) _buildTextHint(),
          if (controller.currentPen != PenType.eraser &&
              controller.inputMode != InputMode.shape &&
              controller.inputMode != InputMode.text)
            _buildEmptyHint(),
        ],
      ),
    );
  }

  Widget _buildEraserOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('지우개 모드', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _modeChip('획', EraserMode.stroke, controller.eraserMode == EraserMode.stroke, () => controller.setEraserMode(EraserMode.stroke)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _modeChip('영역', EraserMode.area, controller.eraserMode == EraserMode.area, () => controller.setEraserMode(EraserMode.area)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('크기 ${controller.eraserSize.round()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(activeTrackColor: AppColors.gold, thumbColor: AppColors.gold),
          child: Slider(
            value: controller.eraserSize.clamp(8.0, 64.0),
            min: 8,
            max: 64,
            onChanged: controller.setEraserSize,
          ),
        ),
      ],
    );
  }

  Widget _modeChip(String label, EraserMode mode, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? AppColors.gold.withValues(alpha: 0.2) : AppColors.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? AppColors.gold : AppColors.border),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, color: selected ? AppColors.gold : AppColors.ink)),
        ),
      ),
    );
  }

  Widget _buildShapeOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('도형 종류', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _shapeChip(ShapeType.line, Icons.horizontal_rule),
            _shapeChip(ShapeType.arrow, Icons.arrow_forward),
            _shapeChip(ShapeType.rectangle, Icons.crop_square),
            _shapeChip(ShapeType.ellipse, Icons.circle_outlined),
          ],
        ),
      ],
    );
  }

  Widget _shapeChip(ShapeType type, IconData icon) {
    final isSelected = controller.currentShapeType == type;
    return ChoiceChip(
      label: Icon(icon, size: 20, color: isSelected ? AppColors.gold : AppColors.ink),
      selected: isSelected,
      onSelected: (_) => controller.selectShapeType(type),
      selectedColor: AppColors.gold.withValues(alpha: 0.2),
    );
  }

  Widget _buildTextHint() {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text('캔버스를 탭하면 텍스트를 입력할 수 있습니다.', style: TextStyle(fontSize: 12, color: AppColors.mutedGray)),
    );
  }

  Widget _buildEmptyHint() {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text('도구를 선택하면 옵션이 표시됩니다.', style: TextStyle(fontSize: 12, color: AppColors.mutedGray)),
    );
  }

}
