import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../models/stroke_model.dart';
import '../../services/stroke_service.dart';
import '../../services/text_service.dart';

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

/// 로컬 스트로크 데이터 (그리는 중)
class LocalStrokeData {
  final String id;
  final String senderId;
  final String? senderName;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final PenType penType;
  final DateTime createdAt;
  bool isConfirmed;
  String? firestoreId; // Firestore에 저장된 ID

  LocalStrokeData({
    required this.id,
    required this.senderId,
    this.senderName,
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.penType,
    required this.createdAt,
    this.isConfirmed = false,
    this.firestoreId,
  });
}

/// 사용자별 자동 색상
class UserAutoColor {
  static final List<Color> _colors = [
    const Color(0xFF1E88E5), // 파랑
    const Color(0xFFE53935), // 빨강
    const Color(0xFF43A047), // 초록
    const Color(0xFFFF9800), // 주황
    const Color(0xFF8E24AA), // 보라
    const Color(0xFF00ACC1), // 청록
    const Color(0xFFD81B60), // 핑크
    const Color(0xFF6D4C41), // 갈색
  ];

  static final Map<String, Color> _userColors = {};

  static Color getColor(String userId) {
    if (!_userColors.containsKey(userId)) {
      final index = _userColors.length % _colors.length;
      _userColors[userId] = _colors[index];
    }
    return _userColors[userId]!;
  }
}

/// 입력 모드
enum InputMode {
  pen,       // 펜 그리기
  text,      // 텍스트 입력
  quickText, // 빠른 텍스트
}

/// 캔버스 컨트롤러 (실시간 동기화 포함)
class CanvasController extends ChangeNotifier {
  final StrokeService _strokeService = StrokeService();
  final TextService _textService = TextService();
  StreamSubscription<List<StrokeModel>>? _strokesSubscription;
  StreamSubscription<List<MessageModel>>? _textsSubscription;

  String? _roomId;
  String? _userId;
  String? _userName;

  // 입력 모드
  InputMode _inputMode = InputMode.pen;
  InputMode get inputMode => _inputMode;

  // 텍스트 목록 (서버)
  List<MessageModel> _serverTexts = [];
  List<MessageModel> get serverTexts => _serverTexts;

  // 빠른 텍스트 마지막 위치
  Offset? _lastTextPosition;

  // 현재 펜
  PenType _currentPen = PenType.pen1;
  PenType get currentPen => _currentPen;

  // 선택 도구
  SelectionTool _selectionTool = SelectionTool.none;
  SelectionTool get selectionTool => _selectionTool;

  // 펜 슬롯별 색상
  final Map<PenType, Color> _penColors = {
    PenType.pen1: Colors.black,
    PenType.pen2: const Color(0xFF1E88E5),
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

  // 로컬 스트로크 (현재 그리는 중인 것만)
  final List<LocalStrokeData> _localStrokes = [];
  List<LocalStrokeData> get localStrokes => List.unmodifiable(_localStrokes);

  // 서버 스트로크 (Firestore에서 가져온 것)
  List<StrokeModel> _serverStrokes = [];
  List<StrokeModel> get serverStrokes => _serverStrokes;

  // 현재 그리는 중인 스트로크
  LocalStrokeData? _currentStroke;
  LocalStrokeData? get currentStroke => _currentStroke;

  // 다른 사용자가 그리는 중인 스트로크 (고스트)
  final Map<String, LocalStrokeData> _ghostStrokes = {};
  Map<String, LocalStrokeData> get ghostStrokes => Map.unmodifiable(_ghostStrokes);

  // Undo/Redo 스택 (로컬)
  final List<String> _undoStack = []; // stroke IDs
  final List<String> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // 캔버스 변환
  Offset _canvasOffset = Offset.zero;
  double _canvasScale = 1.0;

  Offset get canvasOffset => _canvasOffset;
  double get canvasScale => _canvasScale;

  // 고스트 라이팅 확정 타이머
  Timer? _confirmTimer;
  static const _confirmDelay = Duration(seconds: 2);

  // Getters
  Color get currentColor {
    if (_isAutoColor && _userId != null) {
      return UserAutoColor.getColor(_userId!);
    }
    return _penColors[_currentPen] ?? Colors.black;
  }

  double get currentWidth => _penWidths[_currentPen] ?? 2.0;
  List<Color> get colorSlots => List.unmodifiable(_colorSlots);
  List<double> get widthSlots => List.unmodifiable(_widthSlots);
  int get selectedColorIndex => _selectedColorIndex;
  int get selectedWidthIndex => _selectedWidthIndex;

  /// 초기화 (채팅방 연결)
  void initialize(String roomId, String userId, {String? userName}) {
    _roomId = roomId;
    _userId = userId;
    _userName = userName;

    // 실시간 스트로크 구독
    _strokesSubscription?.cancel();
    _strokesSubscription = _strokeService.getStrokesStream(roomId).listen(
      (strokes) {
        _serverStrokes = strokes;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('스트로크 스트림 오류: $e');
      },
    );

    // 실시간 텍스트 구독
    _textsSubscription?.cancel();
    _textsSubscription = _textService.getTextsStream(roomId).listen(
      (texts) {
        _serverTexts = texts;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('텍스트 스트림 오류: $e');
      },
    );
  }

  /// 입력 모드 변경
  void setInputMode(InputMode mode) {
    _inputMode = mode;
    notifyListeners();
  }

  /// 텍스트 추가 (위치 지정형)
  Future<void> addText(String content, Offset position, {
    Color? color,
    double fontSize = 16.0,
  }) async {
    if (_roomId == null || _userId == null || content.isEmpty) return;

    final text = MessageModel(
      id: '',
      roomId: _roomId!,
      senderId: _userId!,
      type: MessageType.text,
      content: content,
      positionX: position.dx,
      positionY: position.dy,
      createdAt: DateTime.now(),
    );

    try {
      await _textService.saveText(text);
      _lastTextPosition = Offset(position.dx, position.dy + 30); // 다음 위치
    } catch (e) {
      debugPrint('텍스트 추가 오류: $e');
    }
  }

  /// 빠른 텍스트 추가 (자동 배치)
  Future<void> addQuickText(String content, {Color? color}) async {
    // 마지막 위치 아래에 자동 배치
    final position = _lastTextPosition ?? const Offset(50, 100);
    await addText(content, position, color: color);
  }

  /// 텍스트 삭제
  Future<void> deleteText(String textId) async {
    if (_roomId == null) return;
    await _textService.deleteText(_roomId!, textId);
  }

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
  void startStroke(Offset point) {
    if (_userId == null || _roomId == null) return;

    if (_currentPen == PenType.eraser) {
      _eraseAtPoint(point);
      return;
    }

    final id = '${_userId}_${DateTime.now().millisecondsSinceEpoch}';
    _currentStroke = LocalStrokeData(
      id: id,
      senderId: _userId!,
      senderName: _userName,
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
  Future<void> endStroke() async {
    if (_currentStroke == null || _roomId == null) return;

    final stroke = _currentStroke!;
    _currentStroke = null;

    // 최소 2점 이상일 때만 저장
    if (stroke.points.length < 2) {
      notifyListeners();
      return;
    }

    // 로컬에 추가 (고스트 상태)
    _localStrokes.add(stroke);
    notifyListeners();

    // Firestore에 저장
    try {
      final points = stroke.points.map((p) {
        return StrokePoint(
          x: p.dx,
          y: p.dy,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
      }).toList();

      // Douglas-Peucker 알고리즘으로 압축 (epsilon = 1.0)
      final simplifiedPoints = StrokeService.simplifyPoints(points, 1.0);

      final strokeModel = StrokeModel(
        id: stroke.id,
        roomId: _roomId!,
        senderId: stroke.senderId,
        points: simplifiedPoints,
        style: PenStyle(
          color: '#${stroke.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
          width: stroke.strokeWidth,
          penType: stroke.penType.name,
        ),
        createdAt: stroke.createdAt,
        isConfirmed: false,
      );

      final firestoreId = await _strokeService.saveStroke(strokeModel);
      stroke.firestoreId = firestoreId;

      // 2초 후 확정
      _confirmTimer?.cancel();
      _confirmTimer = Timer(_confirmDelay, () {
        _confirmStroke(stroke);
      });

      _undoStack.add(firestoreId);
      _redoStack.clear();
    } catch (e) {
      debugPrint('스트로크 저장 오류: $e');
      // 로컬에서 제거
      _localStrokes.remove(stroke);
      notifyListeners();
    }
  }

  /// 스트로크 확정 (고스트 → 실선)
  Future<void> _confirmStroke(LocalStrokeData stroke) async {
    if (stroke.firestoreId == null || _roomId == null) return;

    stroke.isConfirmed = true;
    await _strokeService.confirmStroke(_roomId!, stroke.firestoreId!);

    // 로컬에서 제거 (서버에서 가져올 것이므로)
    _localStrokes.remove(stroke);
    notifyListeners();
  }

  /// 지우기 (포인트)
  Future<void> _eraseAtPoint(Offset point) async {
    if (_roomId == null) return;

    final eraserRadius = _penWidths[PenType.eraser]! / 2;
    final strokesToDelete = <String>[];

    // 서버 스트로크에서 찾기
    for (final stroke in _serverStrokes) {
      for (final p in stroke.points) {
        final offset = Offset(p.x, p.y);
        if ((offset - point).distance < eraserRadius) {
          strokesToDelete.add(stroke.id);
          break;
        }
      }
    }

    // 로컬 스트로크에서 찾기
    final localToRemove = <LocalStrokeData>[];
    for (final stroke in _localStrokes) {
      for (final p in stroke.points) {
        if ((p - point).distance < eraserRadius) {
          if (stroke.firestoreId != null) {
            strokesToDelete.add(stroke.firestoreId!);
          }
          localToRemove.add(stroke);
          break;
        }
      }
    }

    // 삭제
    if (strokesToDelete.isNotEmpty) {
      await _strokeService.deleteStrokes(_roomId!, strokesToDelete);
    }
    _localStrokes.removeWhere((s) => localToRemove.contains(s));
    notifyListeners();
  }

  /// Undo
  Future<void> undo() async {
    if (_undoStack.isEmpty || _roomId == null) return;

    final strokeId = _undoStack.removeLast();
    await _strokeService.deleteStroke(_roomId!, strokeId);
    _redoStack.add(strokeId);
    notifyListeners();
  }

  /// Redo (제한적 - 서버에서 복구 불가)
  void redo() {
    // Firestore에서 소프트 삭제된 것을 복구하려면 추가 로직 필요
    // 현재는 미구현
  }

  /// 캔버스 이동
  void pan(Offset delta) {
    _canvasOffset += delta;
    notifyListeners();
  }

  /// 캔버스 확대/축소
  void zoom(double scale, Offset focalPoint) {
    final newScale = (_canvasScale * scale).clamp(0.1, 5.0);

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

  /// 작성자 색상 가져오기
  Color getAuthorColor(String senderId) {
    return UserAutoColor.getColor(senderId);
  }

  @override
  void dispose() {
    _strokesSubscription?.cancel();
    _textsSubscription?.cancel();
    _confirmTimer?.cancel();
    super.dispose();
  }
}
