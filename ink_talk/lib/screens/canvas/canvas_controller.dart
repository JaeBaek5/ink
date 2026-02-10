import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/message_model.dart';
import '../../models/shape_model.dart';
import '../../models/stroke_model.dart';
import '../../services/shape_service.dart';
import '../../services/stroke_service.dart';
import '../../services/text_service.dart';
import '../../models/media_model.dart';
import '../../services/media_service.dart';
import '../../services/room_service.dart';
import '../../services/settings_service.dart';

/// 펜 종류 (문서 스펙: Pen, Pencil, Fountain, Brush, Highlighter + Eraser)
enum PenType {
  pen1,       // 펜(Pen)
  pen2,       // 연필(Pencil)
  fountain,   // 만년필(Fountain/Calligraphy)
  brush,      // 브러시(Brush)
  highlighter,
  eraser,
}

/// 선택 도구 종류
enum SelectionTool {
  none,
  lasso,
  rectangle,
}

/// 지우개 모드 (문서 스펙: 획 단위 vs 영역)
enum EraserMode {
  stroke, // 터치한 획 전체 삭제
  area,   // 문지른 영역만 삭제(선분 단위)
}

/// Undo/Redo 항목 종류 (이동 제외, 펜·도형·사진·지우개만)
enum _UndoEntryType { stroke, shape, media }

class _UndoEntry {
  final _UndoEntryType type;
  final String id;
  final bool isAdd; // true=추가(undo시 삭제), false=지우개로 삭제(undo시 복구)
  _UndoEntry(this.type, this.id, this.isAdd);
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
  shape,     // 도형 그리기
}

/// 캔버스 컨트롤러 (실시간 동기화 포함)
class CanvasController extends ChangeNotifier {
  final StrokeService _strokeService = StrokeService();
  final TextService _textService = TextService();
  final ShapeService _shapeService = ShapeService();
  final MediaService _mediaService = MediaService();
  final RoomService _roomService = RoomService();
  StreamSubscription<List<StrokeModel>>? _strokesSubscription;
  StreamSubscription<List<MessageModel>>? _textsSubscription;
  StreamSubscription<List<ShapeModel>>? _shapesSubscription;
  StreamSubscription<List<MediaModel>>? _mediaSubscription;

  bool _disposed = false;
  bool get isDisposed => _disposed;
  void _notifyIfNotDisposed() {
    if (_disposed) return;
    super.notifyListeners();
  }

  String? _roomId;
  String? _userId;
  String? _userName;
  /// 방 설정: 캔버스 확장 방식 (방장이 방 설정에서 지정, 확장 로직에서 사용)
  CanvasExpandMode? _canvasExpandMode;
  CanvasExpandMode get canvasExpandMode =>
      _canvasExpandMode ?? CanvasExpandMode.rectangular;
  /// 차단한 사용자 필터: 해당 사용자가 차단 기간 중 보낸 메시지는 표시하지 않음
  String? _blockedUserId;
  DateTime? _blockedAt;

  // 입력 모드
  InputMode _inputMode = InputMode.pen;
  InputMode get inputMode => _inputMode;

  // 텍스트 목록 (서버)
  List<MessageModel> _serverTexts = [];
  List<MessageModel> get serverTexts => _serverTexts;

  // 빠른 텍스트 마지막 위치
  Offset? _lastTextPosition;

  // 도형 목록 (서버)
  List<ShapeModel> _serverShapes = [];
  List<ShapeModel> get serverShapes => _serverShapes;

  // 현재 그리는 도형
  ShapeType _currentShapeType = ShapeType.rectangle;
  ShapeType get currentShapeType => _currentShapeType;

  // 도형 그리기 중인 데이터
  Offset? _shapeStartPoint;
  Offset? _shapeEndPoint;
  Offset? get shapeStartPoint => _shapeStartPoint;
  Offset? get shapeEndPoint => _shapeEndPoint;

  // 도형 스타일
  String _shapeStrokeColor = '#000000';
  double _shapeStrokeWidth = 2.0;
  String? _shapeFillColor;
  double _shapeFillOpacity = 1.0;
  LineStyle _shapeLineStyle = LineStyle.solid;

  String get shapeStrokeColor => _shapeStrokeColor;
  double get shapeStrokeWidth => _shapeStrokeWidth;
  String? get shapeFillColor => _shapeFillColor;
  double get shapeFillOpacity => _shapeFillOpacity;
  LineStyle get shapeLineStyle => _shapeLineStyle;

  // 선택된 도형
  ShapeModel? _selectedShape;
  ShapeModel? get selectedShape => _selectedShape;

  // 스냅/격자
  bool _snapEnabled = true;
  bool get snapEnabled => _snapEnabled;
  static const double gridSize = 25.0;

  // 미디어 목록 (서버)
  List<MediaModel> _serverMedia = [];
  List<MediaModel> get serverMedia => _serverMedia;

  // 선택된 미디어
  MediaModel? _selectedMedia;
  MediaModel? get selectedMedia => _selectedMedia;

  /// 크기 수정 모드인 미디어 ID (롱프레스 → 크기 수정 선택 시에만 설정)
  String? _mediaInResizeMode;
  bool get isInMediaResizeMode => _mediaInResizeMode != null;
  bool isMediaInResizeMode(String mediaId) => _mediaInResizeMode == mediaId;
  void enterMediaResizeMode(String mediaId) {
    try {
      final media = _serverMedia.firstWhere((m) => m.id == mediaId);
      _mediaInResizeMode = mediaId;
      _selectedMedia = media;
      _notifyIfNotDisposed();
    } catch (_) {}
  }
  void clearMediaResizeMode() {
    if (_mediaInResizeMode != null) {
      _mediaInResizeMode = null;
      _notifyIfNotDisposed();
    }
  }

  // 미디어 업로드 중
  bool _isUploading = false;
  bool get isUploading => _isUploading;

  // 현재 펜
  PenType _currentPen = PenType.pen1;
  PenType get currentPen => _currentPen;

  // 선택 도구
  SelectionTool _selectionTool = SelectionTool.none;
  SelectionTool get selectionTool => _selectionTool;

  // 펜 슬롯별 색상
  final Map<PenType, Color> _penColors = {
    PenType.pen1: Colors.black,
    PenType.pen2: const Color(0xFF5D4037), // 연필 갈색
    PenType.fountain: const Color(0xFF1E88E5),
    PenType.brush: const Color(0xFF2E7D32),
    PenType.highlighter: const Color(0xFFFFEB3B),
    PenType.eraser: Colors.white,
  };

  // 펜 슬롯별 굵기
  final Map<PenType, double> _penWidths = {
    PenType.pen1: 2.0,
    PenType.pen2: 1.5,
    PenType.fountain: 2.5,
    PenType.brush: 8.0,
    PenType.highlighter: 16.0,
    PenType.eraser: 20.0,
  };

  // 색상 슬롯 (6개)
  List<Color> _colorSlots = [
    Colors.black,
    const Color(0xFF1E88E5),
    const Color(0xFFE53935),
    Colors.green,
    Colors.orange,
    Colors.purple,
  ];

  // 굵기 슬롯 (3개)
  final List<double> _widthSlots = [2.0, 4.0, 8.0];

  /// 지우개 크기 (캔버스 좌표, 반경)
  double get eraserSize => _penWidths[PenType.eraser]!;
  static const List<double> eraserSizeOptions = [12.0, 20.0, 28.0, 36.0, 48.0];
  void setEraserSize(double size) {
    _penWidths[PenType.eraser] = size.clamp(8.0, 64.0);
    _notifyIfNotDisposed();
  }

  /// 지우개 모드 (획 지우개 / 영역 지우개)
  EraserMode _eraserMode = EraserMode.stroke;
  EraserMode get eraserMode => _eraserMode;
  void setEraserMode(EraserMode mode) {
    if (_eraserMode == mode) return;
    _eraserMode = mode;
    _notifyIfNotDisposed();
  }

  /// 사용자 지정 색 설정 (파레트 길게 누르기 → 팝업에서 선택 시)
  void setCustomColor(Color color) {
    if (_currentPen == PenType.eraser) return;
    _penColors[_currentPen] = color;
    if (_selectedColorIndex >= 0 && _selectedColorIndex < _colorSlots.length) {
      _colorSlots[_selectedColorIndex] = color;
    }
    _notifyIfNotDisposed();
  }

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

  // Undo/Redo 스택 (로컬) — 이동(pan) 제외, 펜·도형·사진·지우개만. 최대 10단계
  static const int undoRedoLimit = 10;
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // 캔버스 변환
  Offset _canvasOffset = Offset.zero;
  double _canvasScale = 1.0;
  /// 줌 초점 계산용 — 캔버스 뷰포트 크기 (DrawingCanvas에서 설정)
  Size? _viewportSize;
  Size? get viewportSize => _viewportSize;
  void setViewportSize(Size size) {
    if (_viewportSize == size) return;
    _viewportSize = size;
    // 빌드 중 호출될 수 있으므로 notifyListeners는 다음 프레임으로 미룸 (setState during build 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyIfNotDisposed();
    });
  }

  Offset get canvasOffset => _canvasOffset;
  double get canvasScale => _canvasScale;

  // 고스트 라이팅 확정 타이머
  Timer? _confirmTimer;
  static const _confirmDelay = Duration(seconds: 2);

  // 오프라인 대기열 (저장 실패 시 재시도용)
  final List<_PendingStroke> _pendingRetry = [];
  int get pendingQueueCount => _pendingRetry.length;
  bool get hasPendingQueue => _pendingRetry.isNotEmpty;

  /// 전송 중인 스트로크 수 (로컬 고스트 + 대기열)
  int get sendingStrokesCount => _localStrokes.length + _pendingRetry.length;

  /// 업로드(사진/영상 등) 시 사용자 메시지 콜백 (스낵바 등)
  void Function(String message)? uploadMessageCallback;

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
  /// [blockedUserId], [blockedAt]: 1:1에서 상대가 차단된 경우, 해당 시각 이후 상대 메시지는 표시 안 함
  void initialize(String roomId, String userId,
      {String? userName,
      CanvasExpandMode? canvasExpandMode,
      String? blockedUserId,
      DateTime? blockedAt}) {
    _roomId = roomId;
    _userId = userId;
    _userName = userName;
    _canvasExpandMode = canvasExpandMode;
    _blockedUserId = blockedUserId;
    _blockedAt = blockedAt;

    List<StrokeModel> _applyStrokeFilter(List<StrokeModel> strokes) {
      if (_blockedUserId == null || _blockedAt == null) return strokes;
      return strokes
          .where((s) =>
              s.senderId != _blockedUserId! ||
              !s.createdAt.isAfter(_blockedAt!))
          .toList();
    }

    List<MessageModel> _applyTextFilter(List<MessageModel> texts) {
      if (_blockedUserId == null || _blockedAt == null) return texts;
      return texts
          .where((m) =>
              m.senderId != _blockedUserId! ||
              !m.createdAt.isAfter(_blockedAt!))
          .toList();
    }

    // 실시간 스트로크 구독
    _strokesSubscription?.cancel();
    _strokesSubscription = _strokeService.getStrokesStream(roomId).listen(
      (strokes) {
        _serverStrokes = _applyStrokeFilter(strokes);
        // 서버에 반영된 로컬 스트로크만 제거 (사라짐 방지)
        final serverIds = strokes.map((s) => s.id).toSet();
        _localStrokes.removeWhere(
          (s) => s.firestoreId != null && serverIds.contains(s.firestoreId),
        );
        _notifyIfNotDisposed();
      },
      onError: (e) {
        debugPrint('스트로크 스트림 오류: $e');
      },
    );

    // 실시간 텍스트 구독
    _textsSubscription?.cancel();
    _textsSubscription = _textService.getTextsStream(roomId).listen(
      (texts) {
        _serverTexts = _applyTextFilter(texts);
        _notifyIfNotDisposed();
      },
      onError: (e) {
        debugPrint('텍스트 스트림 오류: $e');
      },
    );

    // 실시간 도형 구독
    _shapesSubscription?.cancel();
    _shapesSubscription = _shapeService.getShapesStream(roomId).listen(
      (shapes) {
        _serverShapes = shapes;
        _notifyIfNotDisposed();
      },
      onError: (e) {
        debugPrint('도형 스트림 오류: $e');
      },
    );

    // 실시간 미디어 구독
    _mediaSubscription?.cancel();
    _mediaSubscription = _mediaService.getMediaStream(roomId).listen(
      (media) {
        _serverMedia = media;
        // 선택된 미디어가 이동/리사이즈 등으로 갱신되면 핸들 위치가 따라가도록 최신 객체로 교체
        if (_selectedMedia != null) {
          final updated = media.where((m) => m.id == _selectedMedia!.id).firstOrNull;
          if (updated != null) _selectedMedia = updated;
        }
        _notifyIfNotDisposed();
      },
      onError: (e) {
        debugPrint('미디어 스트림 오류: $e');
      },
    );

    // 스트림 첫 수신이 첫 빌드보다 늦을 수 있어, 알림을 한 번 더 해서 진입 시 캔버스가 바로 보이도록
    Future.microtask(() {
      if (!_disposed) _notifyIfNotDisposed();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_disposed) _notifyIfNotDisposed();
    });
  }

  /// 입력 모드 변경
  void setInputMode(InputMode mode) {
    _inputMode = mode;
    _selectedMedia = null;
    _selectedShape = null;
    _notifyIfNotDisposed();
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
      if (_roomId != null && !_disposed) {
        final preview = content.length > 50 ? '${content.substring(0, 50)}…' : content;
        _roomService.updateLastEvent(_roomId!, eventType: 'text', preview: preview);
      }
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
    await _textService.deleteText(_roomId!, textId, userId: _userId);
  }

  // ===== 도형 관련 =====

  /// 도형 타입 선택
  void selectShapeType(ShapeType type) {
    _currentShapeType = type;
    _inputMode = InputMode.shape;
    _notifyIfNotDisposed();
  }

  /// 도형 스타일 설정
  void setShapeStyle({
    String? strokeColor,
    double? strokeWidth,
    String? fillColor,
    double? fillOpacity,
    LineStyle? lineStyle,
  }) {
    if (strokeColor != null) _shapeStrokeColor = strokeColor;
    if (strokeWidth != null) _shapeStrokeWidth = strokeWidth;
    if (fillColor != null) _shapeFillColor = fillColor;
    if (fillOpacity != null) _shapeFillOpacity = fillOpacity;
    if (lineStyle != null) _shapeLineStyle = lineStyle;
    _notifyIfNotDisposed();
  }

  /// 도형 그리기 시작
  void startShape(Offset point) {
    if (_inputMode != InputMode.shape) return;
    _shapeStartPoint = _snapToGrid(point);
    _shapeEndPoint = _shapeStartPoint;
    _notifyIfNotDisposed();
  }

  /// 도형 그리기 중
  void updateShape(Offset point) {
    if (_shapeStartPoint == null) return;
    _shapeEndPoint = _snapToGrid(point);
    _notifyIfNotDisposed();
  }

  /// 도형 그리기 끝
  Future<void> endShape() async {
    if (_shapeStartPoint == null || _shapeEndPoint == null || _roomId == null || _userId == null) {
      _shapeStartPoint = null;
      _shapeEndPoint = null;
      _notifyIfNotDisposed();
      return;
    }

    // 최소 크기 체크
    final dx = (_shapeEndPoint!.dx - _shapeStartPoint!.dx).abs();
    final dy = (_shapeEndPoint!.dy - _shapeStartPoint!.dy).abs();
    if (dx < 5 && dy < 5) {
      _shapeStartPoint = null;
      _shapeEndPoint = null;
      _notifyIfNotDisposed();
      return;
    }

    final shape = ShapeModel(
      id: '',
      roomId: _roomId!,
      senderId: _userId!,
      type: _currentShapeType,
      startX: _shapeStartPoint!.dx,
      startY: _shapeStartPoint!.dy,
      endX: _shapeEndPoint!.dx,
      endY: _shapeEndPoint!.dy,
      strokeColor: _shapeStrokeColor,
      strokeWidth: _shapeStrokeWidth,
      fillColor: _shapeFillColor,
      fillOpacity: _shapeFillOpacity,
      lineStyle: _shapeLineStyle,
      zIndex: _serverShapes.isEmpty ? 0 : _serverShapes.map((s) => s.zIndex).reduce((a, b) => a > b ? a : b) + 1,
      createdAt: DateTime.now(),
    );

    try {
      final shapeId = await _shapeService.saveShape(shape);
      if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
      _undoStack.add(_UndoEntry(_UndoEntryType.shape, shapeId, true));
      _redoStack.clear();
    } catch (e) {
      debugPrint('도형 저장 오류: $e');
    }

    _shapeStartPoint = null;
    _shapeEndPoint = null;
    _notifyIfNotDisposed();
  }

  /// 스냅 토글
  void toggleSnap() {
    _snapEnabled = !_snapEnabled;
    _notifyIfNotDisposed();
  }

  /// 격자에 스냅
  Offset _snapToGrid(Offset point) {
    if (!_snapEnabled) return point;
    return Offset(
      (point.dx / gridSize).round() * gridSize,
      (point.dy / gridSize).round() * gridSize,
    );
  }

  /// 도형 선택
  void selectShape(ShapeModel? shape) {
    _selectedShape = shape;
    _notifyIfNotDisposed();
  }

  /// 선택된 도형 이동
  Future<void> moveSelectedShape(Offset delta) async {
    if (_selectedShape == null || _roomId == null || _selectedShape!.isLocked) return;

    await _shapeService.updateShape(
      _roomId!,
      _selectedShape!.id,
      startX: _selectedShape!.startX + delta.dx,
      startY: _selectedShape!.startY + delta.dy,
      endX: _selectedShape!.endX + delta.dx,
      endY: _selectedShape!.endY + delta.dy,
    );
  }

  /// 도형 삭제 (롱프레스 등 — Undo 가능)
  Future<void> deleteShape(String shapeId) async {
    if (_roomId == null) return;
    await _shapeService.deleteShape(_roomId!, shapeId, userId: _userId);
    if (_selectedShape?.id == shapeId) {
      _selectedShape = null;
    }
    _redoStack.clear();
    if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
    _undoStack.add(_UndoEntry(_UndoEntryType.shape, shapeId, false));
    _notifyIfNotDisposed();
  }

  /// 캔버스 좌표에 있는 도형 반환 (손 터치 롱프레스 삭제용). 없으면 null.
  /// 역순 검사로 위에 그려진 도형 우선.
  ShapeModel? getShapeAtPoint(Offset canvasPoint) {
    const hitMargin = 20.0;
    for (final shape in _serverShapes.reversed) {
      if (shape.isDeleted) continue;
      if (_shapeContainsPoint(shape, canvasPoint, hitMargin)) return shape;
    }
    return null;
  }

  static bool _shapeContainsPoint(ShapeModel shape, Offset p, double margin) {
    final sx = shape.startX;
    final sy = shape.startY;
    final ex = shape.endX;
    final ey = shape.endY;
    final m = shape.strokeWidth / 2 + margin;

    switch (shape.type) {
      case ShapeType.line:
      case ShapeType.arrow:
        return _distanceToSegment(p, Offset(sx, sy), Offset(ex, ey)) <= m;
      case ShapeType.rectangle:
        final left = (sx < ex ? sx : ex) - m;
        final right = (sx > ex ? sx : ex) + m;
        final top = (sy < ey ? sy : ey) - m;
        final bottom = (sy > ey ? sy : ey) + m;
        return p.dx >= left && p.dx <= right && p.dy >= top && p.dy <= bottom;
      case ShapeType.ellipse:
        final cx = (sx + ex) / 2;
        final cy = (sy + ey) / 2;
        final rx = (ex - sx).abs() / 2 + m;
        final ry = (ey - sy).abs() / 2 + m;
        if (rx <= 0 || ry <= 0) return false;
        final nx = (p.dx - cx) / rx;
        final ny = (p.dy - cy) / ry;
        return nx * nx + ny * ny <= 1;
    }
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLen = ab.distance;
    if (abLen == 0) return ap.distance;
    double t = (ap.dx * ab.dx + ap.dy * ab.dy) / (abLen * abLen);
    t = t.clamp(0.0, 1.0);
    final q = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - q).distance;
  }

  /// 도형 잠금 토글
  Future<void> toggleShapeLock(String shapeId, bool isLocked) async {
    if (_roomId == null) return;
    await _shapeService.updateShape(_roomId!, shapeId, isLocked: isLocked);
  }

  /// 도형 앞으로
  Future<void> bringShapeToFront(String shapeId) async {
    if (_roomId == null) return;
    final maxZ = _serverShapes.isEmpty ? 0 : _serverShapes.map((s) => s.zIndex).reduce((a, b) => a > b ? a : b);
    await _shapeService.bringToFront(_roomId!, shapeId, maxZ);
  }

  /// 도형 뒤로
  Future<void> sendShapeToBack(String shapeId) async {
    if (_roomId == null) return;
    await _shapeService.sendToBack(_roomId!, shapeId);
  }

  // ===== 미디어 관련 =====

  /// 이미지 업로드
  Future<void> uploadImage(Offset position) async {
    if (_roomId == null || _userId == null) {
      uploadMessageCallback?.call('채팅방에 연결된 후 다시 시도해 주세요.');
      return;
    }

    // 탭 직후 바로 로딩 표시 (갤러리 열리기 전에 반응 있음)
    _isUploading = true;
    _notifyIfNotDisposed();

    XFile? file;
    try {
      file = await _mediaService.pickImage();
    } catch (e) {
      debugPrint('갤러리 열기 오류: $e');
      _isUploading = false;
      _notifyIfNotDisposed();
      uploadMessageCallback?.call('사진 선택 중 오류가 났습니다. 권한을 확인해 주세요.');
      return;
    }

    if (file == null) {
      _isUploading = false;
      _notifyIfNotDisposed();
      uploadMessageCallback?.call('사진 선택이 취소되었습니다.');
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      final fileName = file.name.isNotEmpty ? file.name : 'image.jpg';

      int width = 200;
      int height = 200;
      try {
        final dims = await MediaService.getImageDimensions(bytes);
        width = dims.width;
        height = dims.height;
      } catch (_) {
        // 크기 조회 실패 시 기본값 유지
      }

      const double maxSide = 600;
      double displayW = width.toDouble();
      double displayH = height.toDouble();
      if (width > 0 && height > 0 && (width > maxSide || height > maxSide)) {
        final scale = maxSide / (width > height ? width : height);
        displayW = width * scale;
        displayH = height * scale;
      }

      final url = await _mediaService.uploadImageBytes(
        roomId: _roomId!,
        bytes: bytes,
        fileName: fileName,
      );

      final media = MediaModel(
        id: '',
        roomId: _roomId!,
        senderId: _userId!,
        type: MediaType.image,
        url: url,
        fileName: fileName,
        x: position.dx,
        y: position.dy,
        width: displayW,
        height: displayH,
        zIndex: _getMaxMediaZIndex() + 1,
        createdAt: DateTime.now(),
      );

      final mediaId = await _mediaService.saveMedia(media);
      if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
      _undoStack.add(_UndoEntry(_UndoEntryType.media, mediaId, true));
      _redoStack.clear();
      if (_roomId != null && !_disposed) {
        _roomService.updateLastEvent(
          _roomId!,
          eventType: 'image',
          preview: fileName,
          url: url,
        );
      }
      uploadMessageCallback?.call('사진이 추가되었습니다.');
    } catch (e) {
      debugPrint('이미지 업로드 오류: $e');
      final msg = e.toString().toLowerCase();
      final isStorageRule = msg.contains('permission') ||
          msg.contains('403') ||
          msg.contains('unauthorized') ||
          msg.contains('security') ||
          msg.contains('rules');
      if (isStorageRule) {
        uploadMessageCallback?.call(
          'Storage 보안 규칙 오류일 수 있습니다. Firebase 콘솔 → Storage → 규칙에서 로그인 사용자 허용 규칙을 적용해 주세요.',
        );
      } else {
        uploadMessageCallback?.call('업로드에 실패했습니다. 네트워크를 확인해 주세요.');
      }
    }

    _isUploading = false;
    _notifyIfNotDisposed();
  }

  /// 영상 업로드
  Future<void> uploadVideo(Offset position) async {
    if (_roomId == null || _userId == null) return;

    final file = await _mediaService.pickVideo();
    if (file == null) return;

    _isUploading = true;
    _notifyIfNotDisposed();

    try {
      final url = await _mediaService.uploadFile(
        roomId: _roomId!,
        filePath: file.path,
        fileName: file.name,
        type: MediaType.video,
      );

      final media = MediaModel(
        id: '',
        roomId: _roomId!,
        senderId: _userId!,
        type: MediaType.video,
        url: url,
        fileName: file.name,
        x: position.dx,
        y: position.dy,
        width: 300,
        height: 200,
        zIndex: _getMaxMediaZIndex() + 1,
        createdAt: DateTime.now(),
      );

      final mediaId = await _mediaService.saveMedia(media);
      if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
      _undoStack.add(_UndoEntry(_UndoEntryType.media, mediaId, true));
      _redoStack.clear();
      if (_roomId != null && !_disposed) {
        _roomService.updateLastEvent(
          _roomId!,
          eventType: 'video',
          preview: file.name,
          url: url,
        );
      }
    } catch (e) {
      debugPrint('영상 업로드 오류: $e');
    }

    _isUploading = false;
    _notifyIfNotDisposed();
  }

  /// PDF 업로드
  Future<void> uploadPdf(Offset position) async {
    if (_roomId == null || _userId == null) return;

    final file = await _mediaService.pickPdf();
    if (file == null || file.path == null) return;

    _isUploading = true;
    _notifyIfNotDisposed();

    try {
      final url = await _mediaService.uploadFile(
        roomId: _roomId!,
        filePath: file.path!,
        fileName: file.name,
        type: MediaType.pdf,
      );

      final media = MediaModel(
        id: '',
        roomId: _roomId!,
        senderId: _userId!,
        type: MediaType.pdf,
        url: url,
        fileName: file.name,
        fileSize: file.size,
        x: position.dx,
        y: position.dy,
        width: 250,
        height: 350,
        zIndex: _getMaxMediaZIndex() + 1,
        createdAt: DateTime.now(),
      );

      final mediaId = await _mediaService.saveMedia(media);
      if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
      _undoStack.add(_UndoEntry(_UndoEntryType.media, mediaId, true));
      _redoStack.clear();
      if (_roomId != null && !_disposed) {
        _roomService.updateLastEvent(
          _roomId!,
          eventType: 'pdf',
          preview: file.name,
          url: url,
        );
      }
    } catch (e) {
      debugPrint('PDF 업로드 오류: $e');
    }

    _isUploading = false;
    _notifyIfNotDisposed();
  }

  int _getMaxMediaZIndex() {
    if (_serverMedia.isEmpty) return 0;
    return _serverMedia.map((m) => m.zIndex).reduce((a, b) => a > b ? a : b);
  }

  /// 미디어 선택 (다른 미디어 선택 또는 선택 해제 시 크기 수정 모드 해제)
  void selectMedia(MediaModel? media) {
    _selectedMedia = media;
    _selectedShape = null;
    if (media == null || _mediaInResizeMode != media.id) {
      _mediaInResizeMode = null;
    }
    _notifyIfNotDisposed();
  }

  /// 미디어 이동
  Future<void> moveMedia(String mediaId, Offset delta) async {
    if (_roomId == null) return;
    final media = _serverMedia.firstWhere((m) => m.id == mediaId);
    await _mediaService.updateMedia(
      _roomId!,
      mediaId,
      x: media.x + delta.dx,
      y: media.y + delta.dy,
    );
  }

  /// 미디어 크기 조절 (왼쪽/위쪽 핸들 시 x, y 함께 전달)
  Future<void> resizeMedia(String mediaId, double width, double height, {double? x, double? y}) async {
    if (_roomId == null) return;
    await _mediaService.updateMedia(
      _roomId!,
      mediaId,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  /// 미디어 회전 (도 단위, 오브젝트 중심 기준)
  Future<void> rotateMedia(String mediaId, double angleDegrees) async {
    if (_roomId == null) return;
    await _mediaService.updateMedia(_roomId!, mediaId, angleDegrees: angleDegrees);
  }

  /// 미디어 기울이기 (도 단위)
  Future<void> skewMedia(String mediaId, double skewXDegrees, double skewYDegrees) async {
    if (_roomId == null) return;
    await _mediaService.updateMedia(_roomId!, mediaId, skewXDegrees: skewXDegrees, skewYDegrees: skewYDegrees);
  }

  /// 미디어 좌/우·상/하 반전 (탭 시 180° 반전 토글)
  Future<void> setMediaFlip(String mediaId, {bool? flipH, bool? flipV}) async {
    if (_roomId == null) return;
    await _mediaService.updateMedia(_roomId!, mediaId, flipHorizontal: flipH, flipVertical: flipV);
  }

  /// 미디어 투명도 설정
  Future<void> setMediaOpacity(String mediaId, double opacity) async {
    if (_roomId == null) return;
    await _mediaService.updateMedia(_roomId!, mediaId, opacity: opacity);
  }

  /// 미디어 잠금/해제
  Future<void> setMediaLocked(String mediaId, bool locked) async {
    if (_roomId == null) return;
    await _mediaService.updateMedia(_roomId!, mediaId, isLocked: locked);
  }

  /// 미디어 삭제 (Undo 가능)
  Future<void> deleteMedia(String mediaId) async {
    if (_roomId == null) return;
    await _mediaService.deleteMedia(_roomId!, mediaId, userId: _userId);
    if (_selectedMedia?.id == mediaId) {
      _selectedMedia = null;
    }
    _redoStack.clear();
    if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
    _undoStack.add(_UndoEntry(_UndoEntryType.media, mediaId, false));
    _notifyIfNotDisposed();
  }

  /// 미디어 앞으로
  Future<void> bringMediaToFront(String mediaId) async {
    if (_roomId == null) return;
    await _mediaService.bringToFront(_roomId!, mediaId, _getMaxMediaZIndex());
  }

  /// 미디어 뒤로
  Future<void> sendMediaToBack(String mediaId) async {
    if (_roomId == null) return;
    await _mediaService.sendToBack(_roomId!, mediaId);
  }

  /// 미디어 복사 (동일 URL·속성, 위치만 살짝 이동하여 새로 생성)
  Future<void> duplicateMedia(String mediaId) async {
    if (_roomId == null || _userId == null) return;
    final idx = _serverMedia.indexWhere((m) => m.id == mediaId);
    if (idx < 0) return;
    final media = _serverMedia[idx];
    const offset = 24.0;
    final copy = MediaModel(
      id: '',
      roomId: _roomId!,
      senderId: _userId!,
      type: media.type,
      url: media.url,
      fileName: media.fileName,
      fileSize: media.fileSize,
      thumbnailUrl: media.thumbnailUrl,
      x: media.x + offset,
      y: media.y + offset,
      width: media.width,
      height: media.height,
      angleDegrees: media.angleDegrees,
      skewXDegrees: media.skewXDegrees,
      skewYDegrees: media.skewYDegrees,
      flipHorizontal: media.flipHorizontal,
      flipVertical: media.flipVertical,
      opacity: media.opacity,
      zIndex: _getMaxMediaZIndex() + 1,
      totalPages: media.totalPages,
      createdAt: DateTime.now(),
    );
    await _mediaService.saveMedia(copy);
    _notifyIfNotDisposed();
  }

  /// 펜 선택 (도형/텍스트 모드 해제 → 손글씨 그리기로 전환)
  void selectPen(PenType pen) {
    _currentPen = pen;
    _inputMode = InputMode.pen;
    _selectionTool = SelectionTool.none;
    _notifyIfNotDisposed();
  }

  /// 선택 도구 선택
  void selectSelectionTool(SelectionTool tool) {
    _selectionTool = tool;
    _notifyIfNotDisposed();
  }

  /// 색상 선택
  void selectColor(int index) {
    if (index >= 0 && index < _colorSlots.length) {
      _selectedColorIndex = index;
      if (_currentPen != PenType.eraser) {
        _penColors[_currentPen] = _colorSlots[index];
      }
      _isAutoColor = false;
      _notifyIfNotDisposed();
    }
  }

  /// 색상 변경 (팔레트에서)
  void setSlotColor(int index, Color color) {
    if (index >= 0 && index < _colorSlots.length) {
      _colorSlots[index] = color;
      if (_selectedColorIndex == index && _currentPen != PenType.eraser) {
        _penColors[_currentPen] = color;
      }
      _notifyIfNotDisposed();
    }
  }

  /// 굵기 선택
  void selectWidth(int index) {
    if (index >= 0 && index < _widthSlots.length) {
      _selectedWidthIndex = index;
      _penWidths[_currentPen] = _widthSlots[index];
      _notifyIfNotDisposed();
    }
  }

  /// 현재 펜 굵기 직접 설정 (속성 패널 슬라이더용)
  void setCurrentPenWidth(double width) {
    if (_currentPen == PenType.eraser) return;
    final clamped = width.clamp(1.0, 30.0);
    _penWidths[_currentPen] = clamped;
    _notifyIfNotDisposed();
  }

  /// 설정에서 저장한 기본 펜(펜1) 색·굵기 적용 (캔버스 진입 시 호출)
  void applyDefaultPenSettings({Color? color, double? width}) {
    if (color != null) {
      _penColors[PenType.pen1] = color;
      _colorSlots[0] = color;
      if (_currentPen == PenType.pen1) _selectedColorIndex = 0;
    }
    if (width != null) {
      _penWidths[PenType.pen1] = width.clamp(1.0, 24.0);
    }
    _notifyIfNotDisposed();
  }

  /// AUTO 모드 토글
  void toggleAutoColor() {
    _isAutoColor = !_isAutoColor;
    _notifyIfNotDisposed();
  }

  /// 그리기 시작 (forceEraser: 펜 옆 버튼 눌렀을 때 지우개로 전환)
  void startStroke(Offset point, {bool forceEraser = false}) {
    if (_userId == null || _roomId == null) return;

    if (_currentPen == PenType.eraser || forceEraser) {
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
    _notifyIfNotDisposed();
  }

  /// 그리기 중 (forceEraser: 펜 옆 버튼 눌렀을 때 지우개로 전환)
  void updateStroke(Offset point, {bool forceEraser = false}) {
    if (_currentPen == PenType.eraser || forceEraser) {
      _eraseAtPoint(point);
      return;
    }

    if (_currentStroke != null) {
      _currentStroke!.points.add(point);
      _notifyIfNotDisposed();
    }
  }

  /// 그리기 끝
  Future<void> endStroke() async {
    if (_currentStroke == null || _roomId == null) return;

    final stroke = _currentStroke!;
    _currentStroke = null;

    // 최소 2점 이상일 때만 저장
    if (stroke.points.length < 2) {
      _notifyIfNotDisposed();
      return;
    }

    // 로컬에 추가 (고스트 상태)
    _localStrokes.add(stroke);
    _notifyIfNotDisposed();

    final points = stroke.points.map((p) {
      return StrokePoint(
        x: p.dx,
        y: p.dy,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
    // epsilon 작을수록 원본에 가깝게 유지 (원·곡선이 각지지 않도록)
    final simplifiedPoints = StrokeService.simplifyPoints(points, 0.4);
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

    try {
      final firestoreId = await _strokeService.saveStroke(strokeModel);
      stroke.firestoreId = firestoreId;
      if (_roomId != null && !_disposed) {
        _roomService.updateLastEvent(_roomId!, eventType: 'stroke', preview: '손글씨');
      }

      _confirmTimer?.cancel();
      _confirmTimer = Timer(_confirmDelay, () {
        _confirmStroke(stroke);
      });

      if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
      _undoStack.add(_UndoEntry(_UndoEntryType.stroke, firestoreId, true));
      _redoStack.clear();
      _notifyIfNotDisposed();
    } catch (e) {
      debugPrint('스트로크 저장 오류: $e');
      _pendingRetry.add(_PendingStroke(stroke: stroke, model: strokeModel));
      _notifyIfNotDisposed();
    }
  }

  /// 대기열 스트로크 재전송 (재연결 후 호출)
  Future<void> retryPendingStrokes() async {
    if (_pendingRetry.isEmpty || _roomId == null) return;

    final toRetry = List<_PendingStroke>.from(_pendingRetry);
    _pendingRetry.clear();
    _notifyIfNotDisposed();

    for (final item in toRetry) {
      try {
        final firestoreId = await _strokeService.saveStroke(item.model);
        item.stroke.firestoreId = firestoreId;
        if (_roomId != null && !_disposed) {
          _roomService.updateLastEvent(_roomId!, eventType: 'stroke', preview: '손글씨');
        }
        _confirmTimer?.cancel();
        _confirmTimer = Timer(_confirmDelay, () {
          _confirmStroke(item.stroke);
        });
        if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
        _undoStack.add(_UndoEntry(_UndoEntryType.stroke, firestoreId, true));
        _redoStack.clear();
      } catch (e) {
        debugPrint('재전송 실패: $e');
        _pendingRetry.add(item);
      }
      _notifyIfNotDisposed();
    }
  }

  /// 스트로크 확정 (Firestore에 isConfirmed 업데이트)
  /// 로컬 제거는 스트림에서 서버 반영 확인 후 처리
  Future<void> _confirmStroke(LocalStrokeData stroke) async {
    if (stroke.firestoreId == null || _roomId == null) return;

    stroke.isConfirmed = true;
    await _strokeService.confirmStroke(_roomId!, stroke.firestoreId!);
    _notifyIfNotDisposed();
  }

  /// 지우개 반경 (캔버스 좌표)
  double get _eraserRadius => _penWidths[PenType.eraser]!;

  /// 점과 선분(직선) 사이 거리 (캔버스 좌표)
  static double _distancePointToSegment(Offset point, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) return (point - a).distance;
    final t = ((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) / (dx * dx + dy * dy);
    final tClamped = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + tClamped * dx, a.dy + tClamped * dy);
    return (point - proj).distance;
  }

  /// 지우기 (포인트 + 선분 기준으로 스트로크 전체 삭제)
  Future<void> _eraseAtPoint(Offset point) async {
    if (_roomId == null) return;

    final radius = _eraserRadius;
    final strokesToDelete = <String>[];

    // 서버 스트로크: 포인트 또는 선분에 닿으면 해당 스트로크 삭제
    for (final stroke in _serverStrokes) {
      final pts = stroke.points;
      if (pts.isEmpty) continue;
      bool hit = false;
      for (var i = 0; i < pts.length; i++) {
        final o = Offset(pts[i].x, pts[i].y);
        if ((o - point).distance <= radius) {
          hit = true;
          break;
        }
        if (i < pts.length - 1) {
          final next = Offset(pts[i + 1].x, pts[i + 1].y);
          if (_distancePointToSegment(point, o, next) <= radius) {
            hit = true;
            break;
          }
        }
      }
      if (hit) strokesToDelete.add(stroke.id);
    }

    // 로컬 스트로크
    final localToRemove = <LocalStrokeData>[];
    for (final stroke in _localStrokes) {
      final pts = stroke.points;
      if (pts.isEmpty) continue;
      bool hit = false;
      for (var i = 0; i < pts.length; i++) {
        if ((pts[i] - point).distance <= radius) {
          hit = true;
          break;
        }
        if (i < pts.length - 1) {
          if (_distancePointToSegment(point, pts[i], pts[i + 1]) <= radius) {
            hit = true;
            break;
          }
        }
      }
      if (hit) {
        if (stroke.firestoreId != null) strokesToDelete.add(stroke.firestoreId!);
        localToRemove.add(stroke);
      }
    }

    if (strokesToDelete.isNotEmpty) {
      await _strokeService.deleteStrokes(_roomId!, strokesToDelete, userId: _userId);
      _redoStack.clear();
      for (final id in strokesToDelete) {
        if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
        _undoStack.add(_UndoEntry(_UndoEntryType.stroke, id, false));
      }
    }
    _localStrokes.removeWhere((s) => localToRemove.contains(s));
    _notifyIfNotDisposed();
  }

  /// Undo (이동 제외, 펜·도형·사진·지우개만)
  Future<void> undo() async {
    if (_undoStack.isEmpty || _roomId == null) return;

    final entry = _undoStack.removeLast();
    try {
      if (entry.isAdd) {
        await _performDelete(entry);
      } else {
        await _performRestore(entry);
      }
      if (_redoStack.length >= undoRedoLimit) _redoStack.removeAt(0);
      _redoStack.add(entry);
    } catch (e) {
      debugPrint('Undo 오류: $e');
      _undoStack.add(entry);
    }
    _notifyIfNotDisposed();
  }

  /// Redo
  Future<void> redo() async {
    if (_redoStack.isEmpty || _roomId == null) return;

    final entry = _redoStack.removeLast();
    try {
      if (entry.isAdd) {
        await _performRestore(entry);
      } else {
        await _performDelete(entry);
      }
      if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
      _undoStack.add(entry);
    } catch (e) {
      debugPrint('Redo 오류: $e');
      _redoStack.add(entry);
    }
    _notifyIfNotDisposed();
  }

  Future<void> _performDelete(_UndoEntry entry) async {
    switch (entry.type) {
      case _UndoEntryType.stroke:
        await _strokeService.deleteStroke(_roomId!, entry.id, userId: _userId);
        break;
      case _UndoEntryType.shape:
        await _shapeService.deleteShape(_roomId!, entry.id, userId: _userId);
        if (_selectedShape?.id == entry.id) {
          _selectedShape = null;
        }
        break;
      case _UndoEntryType.media:
        await _mediaService.deleteMedia(_roomId!, entry.id, userId: _userId);
        break;
    }
  }

  Future<void> _performRestore(_UndoEntry entry) async {
    switch (entry.type) {
      case _UndoEntryType.stroke:
        await _strokeService.restoreStroke(_roomId!, entry.id);
        break;
      case _UndoEntryType.shape:
        await _shapeService.restoreShape(_roomId!, entry.id);
        break;
      case _UndoEntryType.media:
        await _mediaService.restoreMedia(_roomId!, entry.id);
        break;
    }
  }

  /// 캔버스 이동
  void pan(Offset delta) {
    _canvasOffset += delta;
    _notifyIfNotDisposed();
  }

  /// 캔버스 확대/축소 (scale: 배율, focalPoint: 화면상의 초점)
  void zoom(double scale, Offset focalPoint) {
    final newScale = (_canvasScale * scale).clamp(0.1, 5.0);

    final focalPointDelta = focalPoint - _canvasOffset;
    _canvasOffset = focalPoint - focalPointDelta * (newScale / _canvasScale);
    _canvasScale = newScale;

    _notifyIfNotDisposed();
  }

  /// 버튼으로 확대 (우측 하단 + 버튼용)
  void zoomIn(Offset viewportCenter) {
    zoom(1.25, viewportCenter);
  }

  /// 버튼으로 축소 (우측 하단 - 버튼용)
  void zoomOut(Offset viewportCenter) {
    zoom(0.8, viewportCenter);
  }

  /// 줌 버튼용 뷰포트 중심 (캔버스 뷰포트와 동일 좌표계 — 사진 어긋남 방지)
  Offset getZoomFocalPoint(Size fallbackScreenSize) {
    final s = _viewportSize;
    if (s != null && s.width > 0 && s.height > 0) {
      return Offset(s.width / 2, s.height / 2);
    }
    return Offset(fallbackScreenSize.width / 2, fallbackScreenSize.height / 2);
  }

  /// 특정 위치로 점프 (시간순 네비게이션용)
  void jumpToPosition(Offset canvasPosition, Size viewportSize) {
    // 해당 위치가 화면 중앙에 오도록 오프셋 계산
    _canvasOffset = Offset(
      -canvasPosition.dx * _canvasScale + viewportSize.width / 2,
      -canvasPosition.dy * _canvasScale + viewportSize.height / 2,
    );
    _notifyIfNotDisposed();
  }

  /// 캔버스 리셋
  void resetView() {
    _canvasOffset = Offset.zero;
    _canvasScale = 1.0;
    _notifyIfNotDisposed();
  }

  /// 작성자 색상 가져오기
  Color getAuthorColor(String senderId) {
    return UserAutoColor.getColor(senderId);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _strokesSubscription?.cancel();
    _textsSubscription?.cancel();
    _shapesSubscription?.cancel();
    _mediaSubscription?.cancel();
    _confirmTimer?.cancel();
    super.dispose();
  }
}

class _PendingStroke {
  final LocalStrokeData stroke;
  final StrokeModel model;
  _PendingStroke({required this.stroke, required this.model});
}
