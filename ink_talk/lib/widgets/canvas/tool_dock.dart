import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/constants/app_colors.dart';
import '../../screens/canvas/canvas_controller.dart';

/// 좌측 툴 독 (문서 스펙: 태블릿/데스크톱에서 도구 상태 전환)
class ToolDock extends StatelessWidget {
  final CanvasController controller;
  final bool canEditShapes;

  const ToolDock({
    super.key,
    required this.controller,
    this.canEditShapes = true,
  });

  static const double _dockWidth = 56;
  static const double _iconSize = 24;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _dockWidth,
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(
          right: BorderSide(color: AppColors.border),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _tool(Symbols.stylus_pen, '펜', () => controller.selectPen(PenType.pen1), controller.currentPen == PenType.pen1),
          _tool(Symbols.stylus_pencil, '연필', () => controller.selectPen(PenType.pen2), controller.currentPen == PenType.pen2),
          _tool(Symbols.stylus_fountain_pen, '만년필', () => controller.selectPen(PenType.fountain), controller.currentPen == PenType.fountain),
          _tool(Symbols.stylus_brush, '브러시', () => controller.selectPen(PenType.brush), controller.currentPen == PenType.brush),
          _tool(Symbols.ink_highlighter, '형광펜', () => controller.selectPen(PenType.highlighter), controller.currentPen == PenType.highlighter),
          _tool(Symbols.ink_eraser, '지우개', () => controller.selectPen(PenType.eraser), controller.currentPen == PenType.eraser),
          const Divider(height: 24),
          _tool(Icons.crop_square, '선택', () => controller.selectSelectionTool(controller.selectionTool == SelectionTool.rectangle ? SelectionTool.none : SelectionTool.rectangle), controller.selectionTool == SelectionTool.rectangle),
          _tool(Icons.gesture, '올가미', () => controller.selectSelectionTool(controller.selectionTool == SelectionTool.lasso ? SelectionTool.none : SelectionTool.lasso), controller.selectionTool == SelectionTool.lasso),
          const Divider(height: 24),
          _tool(Icons.crop_square, '도형', () => controller.setInputMode(controller.inputMode == InputMode.shape ? InputMode.pen : InputMode.shape), controller.inputMode == InputMode.shape),
          _tool(Icons.text_fields, '텍스트', () => controller.setInputMode(controller.inputMode == InputMode.text ? InputMode.pen : InputMode.text), controller.inputMode == InputMode.text),
          _tool(Icons.image_outlined, '이미지', () => controller.uploadImage(const Offset(100, 100)), false),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, String tooltip, VoidCallback onTap, bool isSelected) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.gold.withValues(alpha: 0.2) : null,
            border: isSelected ? const Border(left: BorderSide(color: AppColors.gold, width: 3)) : null,
          ),
          child: Icon(icon, size: _iconSize, color: isSelected ? AppColors.gold : AppColors.ink),
        ),
      ),
    );
  }
}
