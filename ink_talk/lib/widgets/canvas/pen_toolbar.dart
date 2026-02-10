import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/shape_model.dart';
import '../../screens/canvas/canvas_controller.dart';

/// 펜 툴바 (상단 중앙)
class PenToolbar extends StatelessWidget {
  final CanvasController controller;
  /// 방장 설정: false면 도형 버튼 비활성
  final bool canEditShapes;

  const PenToolbar({
    super.key,
    required this.controller,
    this.canEditShapes = true,
  });

  @override
  Widget build(BuildContext context) {
    final isEraserSelected = controller.currentPen == PenType.eraser;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPenSlots(context),
                  _buildDivider(),
                  _buildSelectionTools(),
                  _buildDivider(),
                  _buildColorSlots(context),
                  _buildDivider(),
                  _buildWidthSlots(),
                  _buildDivider(),
                  _buildUndoRedo(),
                  _buildDivider(),
                  _buildShapeButton(),
                  _buildDivider(),
                  _buildTextButtons(),
                  _buildDivider(),
                  _buildMediaButtons(),
                ],
              ),
            ),
          ),
          // 지우개 선택 시: 모드 + 크기 바
          if (isEraserSelected) _buildEraserSubBar(context),
        ],
      ),
    );
  }

  /// 색상: AUTO + 6색 + 파레트 (툴바 한 줄에 포함)
  Widget _buildColorSlots(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'AUTO 색상',
          child: InkWell(
            onTap: controller.toggleAutoColor,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: controller.isAutoColor ? AppColors.gold.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: controller.isAutoColor ? AppColors.gold : AppColors.border,
                ),
              ),
              child: Text(
                'AUTO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: controller.isAutoColor ? AppColors.gold : AppColors.mutedGray,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        ...List.generate(6, (index) {
          final isSelected = controller.selectedColorIndex == index && !controller.isAutoColor;
          return GestureDetector(
            onTap: () => controller.selectColor(index),
            child: Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: controller.colorSlots[index],
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.gold : AppColors.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
            ),
          );
        }),
        const SizedBox(width: 4),
        Tooltip(
          message: '길게 누르면 사용자 지정 색',
          child: GestureDetector(
            onLongPress: () => _showColorPickerForPalette(context),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
                gradient: const LinearGradient(
                  colors: [Colors.red, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.red],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.palette_outlined, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// 지우개 선택 시 표시: 모드(획/영역) + 바 형태 크기 조정
  Widget _buildEraserSubBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('모드', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('획'),
                selected: controller.eraserMode == EraserMode.stroke,
                onSelected: (_) => controller.setEraserMode(EraserMode.stroke),
                selectedColor: AppColors.gold.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('영역'),
                selected: controller.eraserMode == EraserMode.area,
                onSelected: (_) => controller.setEraserMode(EraserMode.area),
                selectedColor: AppColors.gold.withValues(alpha: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.auto_fix_off, size: 18, color: AppColors.mutedGray),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.gold,
                    inactiveTrackColor: AppColors.border,
                    thumbColor: AppColors.gold,
                  ),
                  child: Slider(
                    value: controller.eraserSize.clamp(8.0, 64.0),
                    min: 8,
                    max: 64,
                    onChanged: (v) => controller.setEraserSize(v),
                  ),
                ),
              ),
              Text(
                '${controller.eraserSize.round()}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.border,
    );
  }

  /// 펜 슬롯 (문서 스펙: 펜·연필·만년필·브러시·형광펜·지우개)
  Widget _buildPenSlots(BuildContext context) {
    return Row(
      children: [
        _buildPenButton(PenType.pen1, Icons.edit, '펜', controller.currentPen == PenType.pen1),
        _buildPenButton(PenType.pen2, Icons.create, '연필', controller.currentPen == PenType.pen2),
        _buildPenButton(PenType.fountain, Icons.brush_outlined, '만년필', controller.currentPen == PenType.fountain),
        _buildPenButton(PenType.brush, Icons.brush, '브러시', controller.currentPen == PenType.brush),
        _buildPenButton(PenType.highlighter, Icons.highlight, '형광펜', controller.currentPen == PenType.highlighter),
        _buildEraserButton(context),
      ],
    );
  }

  Widget _buildPenButton(
    PenType type,
    IconData icon,
    String tooltip,
    bool isSelected,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => controller.selectPen(type),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.gold.withValues(alpha: 0.2) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? AppColors.gold : AppColors.ink,
          ),
        ),
      ),
    );
  }

  /// 지우개 버튼 (탭 시 선택 → 바로 아래 바 형태로 크기 조정 표시)
  Widget _buildEraserButton(BuildContext context) {
    final isSelected = controller.currentPen == PenType.eraser;
    return Tooltip(
      message: '지우개',
      child: InkWell(
        onTap: () => controller.selectPen(PenType.eraser),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.gold.withValues(alpha: 0.2) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.auto_fix_off,
            size: 20,
            color: isSelected ? AppColors.gold : AppColors.ink,
          ),
        ),
      ),
    );
  }

  /// 선택 도구 (라쏘/사각)
  Widget _buildSelectionTools() {
    return Row(
      children: [
        _buildSelectionButton(
          SelectionTool.lasso,
          Icons.gesture,
          '자유형 선택',
          controller.selectionTool == SelectionTool.lasso,
        ),
        _buildSelectionButton(
          SelectionTool.rectangle,
          Icons.crop_square,
          '사각형 선택',
          controller.selectionTool == SelectionTool.rectangle,
        ),
      ],
    );
  }

  Widget _buildSelectionButton(
    SelectionTool tool,
    IconData icon,
    String tooltip,
    bool isSelected,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => controller.selectSelectionTool(
          isSelected ? SelectionTool.none : tool,
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.gold.withValues(alpha: 0.2) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? AppColors.gold : AppColors.mutedGray,
          ),
        ),
      ),
    );
  }

  void _showColorPickerForPalette(BuildContext context) {
    final colors = [
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('사용자 지정 색'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((color) {
              return GestureDetector(
                onTap: () {
                  controller.setCustomColor(color);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// 굵기 슬롯
  Widget _buildWidthSlots() {
    return Row(
      children: List.generate(3, (index) {
        final width = controller.widthSlots[index];
        final isSelected = controller.selectedWidthIndex == index;
        
        return Tooltip(
          message: '굵기 ${width.toInt()}',
          child: InkWell(
            onTap: () => controller.selectWidth(index),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.gold.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                child: Container(
                  width: width + 2,
                  height: width + 2,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.gold : AppColors.ink,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// Undo / Redo (컨트롤러 구독으로 스택 변경 시 버튼 활성/비활성 갱신)
  Widget _buildUndoRedo() {
    return ListenableBuilder(
      listenable: controller,
      builder: (_, __) {
        final canUndo = controller.canUndo;
        final canRedo = controller.canRedo;
        return Row(
          children: [
            Tooltip(
              message: '되돌리기',
              child: InkWell(
                onTap: canUndo ? () => controller.undo() : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.undo,
                    size: 20,
                    color: canUndo ? AppColors.ink : AppColors.mutedGray,
                  ),
                ),
              ),
            ),
            Tooltip(
              message: '다시 실행',
              child: InkWell(
                onTap: canRedo ? () => controller.redo() : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.redo,
                    size: 20,
                    color: canRedo ? AppColors.ink : AppColors.mutedGray,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 도형 선택
  Widget _buildShapeButton() {
    final isShapeMode = controller.inputMode == InputMode.shape;

    if (!canEditShapes) {
      return Tooltip(
        message: '방장이 도형 수정을 제한했습니다.',
        child: InkWell(
          onTap: () {
            // SnackBar is shown by caller if needed
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.crop_square, size: 20, color: AppColors.mutedGray),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down, size: 16, color: AppColors.mutedGray),
              ],
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<ShapeType>(
      tooltip: '도형',
      onSelected: (type) {
        controller.selectShapeType(type);
      },
      offset: const Offset(0, 40),
      itemBuilder: (context) => [
        _buildShapeMenuItem(ShapeType.line, Icons.horizontal_rule, '선'),
        _buildShapeMenuItem(ShapeType.arrow, Icons.arrow_forward, '화살표'),
        _buildShapeMenuItem(ShapeType.rectangle, Icons.crop_square, '사각형'),
        _buildShapeMenuItem(ShapeType.ellipse, Icons.circle_outlined, '원/타원'),
      ],
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isShapeMode ? AppColors.gold.withValues(alpha: 0.2) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getShapeIcon(controller.currentShapeType),
              size: 20,
              color: isShapeMode ? AppColors.gold : AppColors.ink,
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isShapeMode ? AppColors.gold : AppColors.mutedGray,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<ShapeType> _buildShapeMenuItem(ShapeType type, IconData icon, String label) {
    final isSelected = controller.currentShapeType == type;
    return PopupMenuItem<ShapeType>(
      value: type,
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? AppColors.gold : AppColors.ink),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: isSelected ? AppColors.gold : AppColors.ink)),
        ],
      ),
    );
  }

  IconData _getShapeIcon(ShapeType type) {
    switch (type) {
      case ShapeType.line:
        return Icons.horizontal_rule;
      case ShapeType.arrow:
        return Icons.arrow_forward;
      case ShapeType.rectangle:
        return Icons.crop_square;
      case ShapeType.ellipse:
        return Icons.circle_outlined;
    }
  }

  Widget _buildMediaButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 사진 업로드
        Tooltip(
          message: '사진',
          child: InkWell(
            onTap: () => controller.uploadImage(const Offset(100, 100)),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: controller.isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.gold,
                      ),
                    )
                  : const Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: AppColors.ink,
                    ),
            ),
          ),
        ),
        // 영상 업로드
        Tooltip(
          message: '영상',
          child: InkWell(
            onTap: () => controller.uploadVideo(const Offset(100, 100)),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.videocam_outlined,
                size: 20,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
        // PDF 업로드
        Tooltip(
          message: 'PDF',
          child: InkWell(
            onTap: () => controller.uploadPdf(const Offset(100, 100)),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                size: 20,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 텍스트 버튼
  Widget _buildTextButtons() {
    final isTextMode = controller.inputMode == InputMode.text;
    final isQuickTextMode = controller.inputMode == InputMode.quickText;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 위치 지정형 텍스트
        Tooltip(
          message: '텍스트 (위치 지정)',
          child: InkWell(
            onTap: () {
              if (isTextMode) {
                controller.setInputMode(InputMode.pen);
              } else {
                controller.setInputMode(InputMode.text);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isTextMode ? AppColors.gold.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.text_fields,
                size: 20,
                color: isTextMode ? AppColors.gold : AppColors.ink,
              ),
            ),
          ),
        ),
        // 빠른 텍스트
        Tooltip(
          message: '빠른 텍스트 (연속 작성)',
          child: InkWell(
            onTap: () {
              if (isQuickTextMode) {
                controller.setInputMode(InputMode.pen);
              } else {
                controller.setInputMode(InputMode.quickText);
                _showQuickTextInput();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isQuickTextMode ? AppColors.gold.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.text_snippet_outlined,
                size: 20,
                color: isQuickTextMode ? AppColors.gold : AppColors.ink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showQuickTextInput() {
    // 빠른 텍스트 입력은 CanvasScreen에서 처리
  }
}
