import 'package:flutter/material.dart';

/// 펜 종류
enum PenType {
  pen1,
  pen2,
  eraser,
}

/// 선택 도구 종류
enum SelectionTool {
  none,
  lasso,
  rectangle,
}

/// 스트로크 데이터
class StrokeData {
  final String id;
  final String senderId;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final PenType penType;
  final DateTime createdAt;
  bool isConfirmed;

  StrokeData({
    required this.id,
    required this.senderId,
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.penType,
    required this.createdAt,
    this.isConfirmed = false,
  });
}

/// 캔버스 컨트롤러
class CanvasController extends ChangeNotifier {
  // 현재 펜
  PenType _currentPen = PenType.pen1;
  PenType get currentPen => _currentPen;

  // 선택 도구
  SelectionTool _selectionTool = SelectionTool.none;
  SelectionTool get selectionTool => _selectionTool;

  // 펜 슬롯별 색상
  final Map<PenType, Color> _penColors = {
    PenType.pen1: Colors.black,
    PenType.pen2: const Color(0xFF1E88E5), // 파란색
    PenType.eraser: Colors.white,
  };

  // 펜 슬롯별 굵기
  final Map<PenType, double> _penWidths = {
    PenType.pen1: 2.0,
    PenType.pen2: 2.0,
    PenType.eraser: 20.0,
  };

  // 색상 슬롯 (3개)
  final List<Color> _colorSlots = [
    Colors.black,
    const Color(0xFF1E88E5),
    const Color(0xFFE53935),
  ];

  // 굵기 슬롯 (3개)
  final List<double> _widthSlots = [2.0, 4.0, 8.0];

  // 현재 선택된 색상/굵기 인덱스
  int _selectedColorIndex = 0;
  int _selectedWidthIndex = 0;

  // AUTO 모드 (사용자별 자동 색상)
  bool _isAutoColor = false;
  bool get isAutoColor => _isAutoColor;

  // 스트로크 목록
  final List<StrokeData> _strokes = [];
  List<StrokeData> get strokes => List.unmodifiable(_strokes);

  // 현재 그리는 중인 스트로크
  StrokeData? _currentStroke;
  StrokeData? get currentStroke => _currentStroke;

  // Undo/Redo 스택
  final List<StrokeData> _undoStack = [];
  final List<StrokeData> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // 캔버스 변환
  Offset _canvasOffset = Offset.zero;
  double _canvasScale = 1.0;

  Offset get canvasOffset => _canvasOffset;
  double get canvasScale => _canvasScale;

  // Getters
  Color get currentColor => _penColors[_currentPen] ?? Colors.black;
  double get currentWidth => _penWidths[_currentPen] ?? 2.0;
  List<Color> get colorSlots => List.unmodifiable(_colorSlots);
  List<double> get widthSlots => List.unmodifiable(_widthSlots);
  int get selectedColorIndex => _selectedColorIndex;
  int get selectedWidthIndex => _selectedWidthIndex;

  /// 펜 선택
  void selectPen(PenType pen) {
    _currentPen = pen;
    _selectionTool = SelectionTool.none;
    notifyListeners();
  }

  /// 선택 도구 선택
  void selectSelectionTool(SelectionTool tool) {
    _selectionTool = tool;
    notifyListeners();
  }

  /// 색상 선택
  void selectColor(int index) {
    if (index >= 0 && index < _colorSlots.length) {
      _selectedColorIndex = index;
      if (_currentPen != PenType.eraser) {
        _penColors[_currentPen] = _colorSlots[index];
      }
      _isAutoColor = false;
      notifyListeners();
    }
  }

  /// 색상 변경 (팔레트에서)
  void setSlotColor(int index, Color color) {
    if (index >= 0 && index < _colorSlots.length) {
      _colorSlots[index] = color;
      if (_selectedColorIndex == index && _currentPen != PenType.eraser) {
        _penColors[_currentPen] = color;
      }
      notifyListeners();
    }
  }

  /// 굵기 선택
  void selectWidth(int index) {
    if (index >= 0 && index < _widthSlots.length) {
      _selectedWidthIndex = index;
      _penWidths[_currentPen] = _widthSlots[index];
      notifyListeners();
    }
  }

  /// AUTO 모드 토글
  void toggleAutoColor() {
    _isAutoColor = !_isAutoColor;
    notifyListeners();
  }

  /// 그리기 시작
  void startStroke(Offset point, String userId) {
    if (_currentPen == PenType.eraser) {
      _eraseAtPoint(point);
      return;
    }

    final id = '${userId}_${DateTime.now().millisecondsSinceEpoch}';
    _currentStroke = StrokeData(
      id: id,
      senderId: userId,
      points: [point],
      color: currentColor,
      strokeWidth: currentWidth,
      penType: _currentPen,
      createdAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// 그리기 중
  void updateStroke(Offset point) {
    if (_currentPen == PenType.eraser) {
      _eraseAtPoint(point);
      return;
    }

    if (_currentStroke != null) {
      _currentStroke!.points.add(point);
      notifyListeners();
    }
  }

  /// 그리기 끝
  void endStroke() {
    if (_currentStroke != null) {
      _currentStroke!.isConfirmed = true;
      _strokes.add(_currentStroke!);
      _undoStack.add(_currentStroke!);
      _redoStack.clear();
      _currentStroke = null;
      notifyListeners();
    }
  }

  /// 지우기 (포인트)
  void _eraseAtPoint(Offset point) {
    final eraserRadius = _penWidths[PenType.eraser]! / 2;
    
    _strokes.removeWhere((stroke) {
      for (final p in stroke.points) {
        if ((p - point).distance < eraserRadius) {
          _undoStack.add(stroke);
          return true;
        }
      }
      return false;
    });
    notifyListeners();
  }

  /// Undo
  void undo() {
    if (_undoStack.isNotEmpty) {
      final stroke = _undoStack.removeLast();
      _strokes.remove(stroke);
      _redoStack.add(stroke);
      notifyListeners();
    }
  }

  /// Redo
  void redo() {
    if (_redoStack.isNotEmpty) {
      final stroke = _redoStack.removeLast();
      _strokes.add(stroke);
      _undoStack.add(stroke);
      notifyListeners();
    }
  }

  /// 캔버스 이동
  void pan(Offset delta) {
    _canvasOffset += delta;
    notifyListeners();
  }

  /// 캔버스 확대/축소
  void zoom(double scale, Offset focalPoint) {
    final newScale = (_canvasScale * scale).clamp(0.1, 5.0);
    
    // 줌 중심점 유지
    final focalPointDelta = focalPoint - _canvasOffset;
    _canvasOffset = focalPoint - focalPointDelta * (newScale / _canvasScale);
    _canvasScale = newScale;
    
    notifyListeners();
  }

  /// 캔버스 리셋
  void resetView() {
    _canvasOffset = Offset.zero;
    _canvasScale = 1.0;
    notifyListeners();
  }

  /// 전체 지우기
  void clearAll() {
    _undoStack.addAll(_strokes);
    _strokes.clear();
    _redoStack.clear();
    notifyListeners();
  }
}
