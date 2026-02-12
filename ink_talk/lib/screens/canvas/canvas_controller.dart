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
import '../../services/rtdb_room_service.dart';
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

/// PDF 보기 방식 (길게 누르기 메뉴에서 선택)
enum PdfViewMode {
  /// 한 페이지 + 좌우 화살표
  singlePage,
  /// 여러 페이지 우측·아래로 동시 표시 (그리드)
  grid,
}

/// Undo/Redo 항목 종류 (이동 제외, 펜·도형·사진·지우개만)
enum _UndoEntryType { stroke, shape, media }

/// 방별 캔버스 뷰 상태 (나갔다 들어와도 비율·위치 유지)
class _SavedCanvasView {
  final Offset offset;
  final double scale;
  _SavedCanvasView(this.offset, this.scale);
}

class _UndoEntry {
  final _UndoEntryType type;
  final String id;
  final bool isAdd; // true=추가(undo시 삭제), false=지우개로 삭제(undo시 복구)
  _UndoEntry(this.type, this.id, this.isAdd);
}

/// 업로드 중 캔버스에 표시할 플레이스홀더 (박스 + 로딩)
class UploadingPlaceholder {
  final String tempId;
  final double x;
  final double y;
  final double width;
  final double height;
  final MediaType type;
  UploadingPlaceholder({
    required this.tempId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.type,
  });
}

/// 로컬 스트로크 포인트 (x, y, 필압력, 타임스탬프)
class LocalStrokePoint {
  final double x;
  final double y;
  final double pressure;
  final int timestamp;

  LocalStrokePoint({
    required this.x,
    required this.y,
    this.pressure = 1.0,
    required this.timestamp,
  });

  Offset get offset => Offset(x, y);
}

/// 로컬 스트로크 데이터 (그리는 중)
class LocalStrokeData {
  final String id;
  final String senderId;
  final String? senderName;
  final List<LocalStrokePoint> points;
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
  final RtdbRoomService _rtdbRoom = RtdbRoomService();
  StreamSubscription<List<StrokeModel>>? _strokesSubscription;
  StreamSubscription<List<MessageModel>>? _textsSubscription;
  StreamSubscription<List<ShapeModel>>? _shapesSubscription;
  StreamSubscription<List<MediaModel>>? _mediaSubscription;
  StreamSubscription<RoomEventBatch>? _rtdbSubscription;
  int _rtdbJoinTime = 0;

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

  // 빠른 텍스트: 마지막으로 쓴 위치 아래(다음 줄)
  Offset? _lastTextPosition;
  /// 빠른 텍스트에서 손가락으로 탭한 위치 또는 전송 후 다음 줄 위치. null이면 탭 전(커서 미표시)
  Offset? _quickTextCursorPosition;
  Offset? get quickTextCursorPosition => _quickTextCursorPosition;
  void setQuickTextCursorPosition(Offset? position) {
    if (_quickTextCursorPosition == position) return;
    _quickTextCursorPosition = position;
    _notifyIfNotDisposed();
  }

  /// 위치 지정 텍스트 모드에서 손가락으로 누른 위치(캔버스 좌표). 여기에 커서 표시·글 배치
  Offset? _textCursorPosition;
  Offset? get textCursorPosition => _textCursorPosition;
  void setTextCursorPosition(Offset? position) {
    if (_textCursorPosition == position) return;
    _textCursorPosition = position;
    _notifyIfNotDisposed();
  }
  void clearTextCursorPosition() => setTextCursorPosition(null);

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
    final id = _mediaInResizeMode;
    _mediaInResizeMode = null;
    if (id != null) {
      _persistMediaGeometry(id);
      _notifyIfNotDisposed();
    } else {
      _notifyIfNotDisposed();
    }
  }

  // 미디어 업로드 중
  bool _isUploading = false;
  bool get isUploading => _isUploading;

  /// 업로드 중 표시용 플레이스홀더 (박스 먼저 만들고 로딩 표시)
  final List<UploadingPlaceholder> _uploadingPlaceholders = [];
  List<UploadingPlaceholder> get uploadingPlaceholders => List.unmodifiable(_uploadingPlaceholders);

  /// 뷰포트 캔버스 크기 (화면 비율에 맞게 미디어 크기용). null이면 기본값 사용.
  Size? _getViewportCanvasSize() {
    final s = _viewportSize;
    if (s == null || s.width <= 0 || s.height <= 0) return null;
    return Size(s.width / _canvasScale, s.height / _canvasScale);
  }

  /// 화면(뷰포트) 중앙의 캔버스 좌표. 업로드 위치용.
  Offset? _getViewportCenterInCanvas() {
    final s = _viewportSize;
    if (s == null || s.width <= 0 || s.height <= 0) return null;
    final screenCenter = Offset(s.width / 2, s.height / 2);
    return (screenCenter - _canvasOffset) / _canvasScale;
  }

  /// PDF 보기 방식 (미디어 ID별, 기본: 한 페이지 + 화살표)
  final Map<String, PdfViewMode> _pdfViewModes = {};
  PdfViewMode getPdfViewMode(String mediaId) =>
      _pdfViewModes[mediaId] ?? PdfViewMode.singlePage;
  void setPdfViewMode(String mediaId, PdfViewMode mode) {
    if (_pdfViewModes[mediaId] == mode) return;
    _pdfViewModes[mediaId] = mode;
    _notifyIfNotDisposed();
  }

  /// PDF 현재 페이지 (미디어 ID별, 1-based). 화살표는 캔버스 오버레이에서 사용.
  final Map<String, int> _pdfCurrentPage = {};
  int getPdfPage(String mediaId) => _pdfCurrentPage[mediaId] ?? 1;
  void setPdfPage(String mediaId, int page) {
    final count = _pdfPageCount[mediaId];
    final clamped = count != null ? page.clamp(1, count) : page.clamp(1, 9999);
    if (_pdfCurrentPage[mediaId] == clamped) return;
    _pdfCurrentPage[mediaId] = clamped;
    _notifyIfNotDisposed();
  }

  /// PDF 총 페이지 수 (로드 후 MediaWidget에서 설정)
  final Map<String, int> _pdfPageCount = {};
  int? getPdfPageCount(String mediaId) => _pdfPageCount[mediaId];
  void setPdfPageCount(String mediaId, int count) {
    if (_pdfPageCount[mediaId] == count) return;
    _pdfPageCount[mediaId] = count;
    _notifyIfNotDisposed();
  }

  /// 이미지 자르기 영역 (미디어 ID별, 정규화 0~1). null이면 전체 표시.
  final Map<String, Rect> _mediaCropRects = {};
  Rect? getMediaCropRect(String mediaId) => _mediaCropRects[mediaId];
  void setMediaCropRect(String mediaId, Rect? rect) {
    if (rect == null) {
      _mediaCropRects.remove(mediaId);
    } else {
      _mediaCropRects[mediaId] = rect;
    }
    _notifyIfNotDisposed();
    if (_roomId == null) return;
    if (rect != null) {
      _mediaService.updateMedia(_roomId!, mediaId, cropRect: rect);
    } else {
      _mediaService.updateMedia(_roomId!, mediaId, clearCrop: true);
    }
  }

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
  /// 방별 캔버스 뷰 저장 (나갔다 들어와도 비율·위치 유지)
  static final Map<String, _SavedCanvasView> _roomCanvasViewState = {};
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

  /// 캔버스 초기화 시 로컬 상태 비우기 (서버 삭제 후 호출)
  void clearLocalCanvasState() {
    _localStrokes.clear();
    _pendingRetry.clear();
    _ghostStrokes.clear();
    _currentStroke = null;
    _undoStack.clear();
    _redoStack.clear();
    _selectedShape = null;
    _selectedMedia = null;
    _notifyIfNotDisposed();
  }

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

    // 이전에 나갈 때 저장해 둔 뷰 상태 복원
    final saved = _roomCanvasViewState[roomId];
    if (saved != null) {
      _canvasOffset = saved.offset;
      _canvasScale = saved.scale.clamp(0.1, 5.0);
    }

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

    // Firestore 1회 로드 (실시간은 RTDB로 전환하여 Read 비용 절감)
    _strokesSubscription?.cancel();
    _textsSubscription?.cancel();
    _shapesSubscription?.cancel();
    _mediaSubscription?.cancel();
    _rtdbSubscription?.cancel();

    Future(() async {
      final strokes = await _strokeService.getStrokes(roomId);
      final texts = await _textService.getTexts(roomId);
      final shapes = await _shapeService.getShapes(roomId);
      final media = await _mediaService.getMedia(roomId);
      if (_disposed) return;
      _serverStrokes = _applyStrokeFilter(strokes);
      _serverTexts = _applyTextFilter(texts);
      _serverShapes = shapes;
      _serverMedia = media;
      _mediaCropRects.clear();
      for (final m in media) {
        if (m.cropRect != null) _mediaCropRects[m.id] = m.cropRect!;
      }
      _rtdbJoinTime = DateTime.now().millisecondsSinceEpoch - 10000;
      if (_userId != null) {
        await _rtdbRoom.setRoomMember(roomId, _userId!, true);
      }
      _rtdbSubscription = _rtdbRoom.roomEventsStream(roomId, sinceMs: _rtdbJoinTime).listen(
        (batch) {
          if (_disposed) return;
          for (final e in batch.events) {
            _applyRtdbEvent(e);
          }
          _notifyIfNotDisposed();
        },
        onError: (err) => debugPrint('RTDB 스트림 오류: $err'),
      );
      _notifyIfNotDisposed();
    });
    Future.microtask(() {
      if (!_disposed) _notifyIfNotDisposed();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_disposed) _notifyIfNotDisposed();
    });
  }

  void _applyRtdbEvent(RoomDeltaEvent e) {
    switch (e.type) {
      case 'stroke_delta':
        final id = e.payload['id']?.toString();
        if (id == null) return;
        if (e.op == 'remove') {
          _serverStrokes = _serverStrokes.where((s) => s.id != id).toList();
          _localStrokes.removeWhere((s) => s.firestoreId == id);
          return;
        }
        try {
          if (e.op == 'update') {
            final idx = _serverStrokes.indexWhere((s) => s.id == id);
            if (idx >= 0) {
              final existing = _serverStrokes[idx];
              final updated = StrokeModel(
                id: existing.id,
                roomId: existing.roomId,
                senderId: existing.senderId,
                points: existing.points,
                style: existing.style,
                createdAt: existing.createdAt,
                isConfirmed: e.payload['isConfirmed'] as bool? ?? existing.isConfirmed,
                isDeleted: existing.isDeleted,
              );
              _serverStrokes = List.from(_serverStrokes)..[idx] = updated;
            }
          } else {
            final stroke = StrokeModel.fromRtdbMap(e.payload);
            final idx = _serverStrokes.indexWhere((s) => s.id == id);
            if (idx >= 0) {
              _serverStrokes = List.from(_serverStrokes)..[idx] = stroke;
            } else {
              _serverStrokes = [..._serverStrokes, stroke];
              _serverStrokes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            }
          }
        } catch (_) {}
        break;
      case 'text_delta':
        final id = e.payload['id']?.toString();
        if (id == null) return;
        if (e.op == 'remove') {
          _serverTexts = _serverTexts.where((t) => t.id != id).toList();
          return;
        }
        try {
          final text = MessageModel.fromRtdbMap(e.payload);
          final idx = _serverTexts.indexWhere((t) => t.id == id);
          if (idx >= 0) {
            _serverTexts = List.from(_serverTexts)..[idx] = text;
          } else {
            _serverTexts = [..._serverTexts, text];
            _serverTexts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          }
        } catch (_) {}
        break;
      case 'shape_delta':
        final id = e.payload['id']?.toString();
        if (id == null) return;
        if (e.op == 'remove') {
          _serverShapes = _serverShapes.where((s) => s.id != id).toList();
          if (_selectedShape?.id == id) _selectedShape = null;
          return;
        }
        try {
          final shape = ShapeModel.fromRtdbMap(e.payload);
          final idx = _serverShapes.indexWhere((s) => s.id == id);
          if (idx >= 0) {
            _serverShapes = List.from(_serverShapes)..[idx] = shape;
          } else {
            _serverShapes = [..._serverShapes, shape];
            _serverShapes.sort((a, b) => a.zIndex.compareTo(b.zIndex));
          }
          if (_selectedShape?.id == id) _selectedShape = shape;
        } catch (_) {}
        break;
      case 'media_delta':
        final id = e.payload['id']?.toString();
        if (id == null) return;
        if (e.op == 'remove') {
          _serverMedia = _serverMedia.where((m) => m.id != id).toList();
          _mediaCropRects.remove(id);
          if (_selectedMedia?.id == id) _selectedMedia = null;
          return;
        }
        try {
          final media = MediaModel.fromRtdbMap(e.payload);
          final idx = _serverMedia.indexWhere((m) => m.id == id);
          if (idx >= 0) {
            _serverMedia = List.from(_serverMedia)..[idx] = media;
          } else {
            _serverMedia = [..._serverMedia, media];
            _serverMedia.sort((a, b) => a.zIndex.compareTo(b.zIndex));
          }
          if (media.cropRect != null) _mediaCropRects[media.id] = media.cropRect!;
          if (_selectedMedia?.id == id) _selectedMedia = media;
        } catch (_) {}
        break;
      default:
        break;
    }
  }

  /// 입력 모드 변경 (텍스트/도형 선택 시 선택 도구 해제 → 툴바에서 모두 선택 가능)
  void setInputMode(InputMode mode) {
    _inputMode = mode;
    _selectedMedia = null;
    _selectedShape = null;
    if (mode == InputMode.text || mode == InputMode.quickText || mode == InputMode.shape) {
      _selectionTool = SelectionTool.none;
    }
    // 빠른 텍스트: 들어올 때 커서 비움(탭 후 표시), 나갈 때도 비움
    if (mode == InputMode.quickText || mode == InputMode.pen) {
      _quickTextCursorPosition = null;
    }
    _notifyIfNotDisposed();
  }

  /// 툴바/위치 지정/빠른 입력 공통 텍스트 크기(pt)
  double _textFontSize = 16.0;
  double get textFontSize => _textFontSize;
  void setTextFontSize(double pt) {
    if (_textFontSize == pt) return;
    _textFontSize = pt;
    _notifyIfNotDisposed();
  }

  /// 텍스트 추가 (위치 지정형)
  Future<void> addText(String content, Offset position, {
    Color? color,
    double? fontSize,
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
      fontSize: fontSize ?? _textFontSize,
      createdAt: DateTime.now(),
    );

    try {
      final textId = await _textService.saveText(text);
      _lastTextPosition = Offset(position.dx, position.dy + 30); // 다음 위치
      if (_roomId != null && !_disposed) {
        final preview = content.length > 50 ? '${content.substring(0, 50)}…' : content;
        _roomService.updateLastEvent(_roomId!, eventType: 'text', preview: preview);
        final payload = text.toRtdbPayload()..['id'] = textId;
        _rtdbRoom.pushEvent(_roomId!, 'text_delta', 'add', payload);
      }
    } catch (e) {
      debugPrint('텍스트 추가 오류: $e');
    }
  }

  /// 빠른 텍스트 추가 (커서 위치에 배치, 전송 후 커서는 아랫줄로)
  Future<void> addQuickText(String content, {Color? color}) async {
    final position = _quickTextCursorPosition ?? _lastTextPosition ?? const Offset(50, 100);
    await addText(content, position, color: color);
    _quickTextCursorPosition = _lastTextPosition;
    _notifyIfNotDisposed();
  }

  /// 텍스트 삭제
  Future<void> deleteText(String textId) async {
    if (_roomId == null) return;
    _rtdbRoom.pushEvent(_roomId!, 'text_delta', 'remove', {'id': textId});
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

  /// 도형 그리기 끝 (완료 후 도형 모드 비활성화)
  Future<void> endShape() async {
    if (_shapeStartPoint == null || _shapeEndPoint == null || _roomId == null || _userId == null) {
      _shapeStartPoint = null;
      _shapeEndPoint = null;
      setInputMode(InputMode.pen);
      _notifyIfNotDisposed();
      return;
    }

    // 최소 크기 체크
    final dx = (_shapeEndPoint!.dx - _shapeStartPoint!.dx).abs();
    final dy = (_shapeEndPoint!.dy - _shapeStartPoint!.dy).abs();
    if (dx < 5 && dy < 5) {
      _shapeStartPoint = null;
      _shapeEndPoint = null;
      setInputMode(InputMode.pen);
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
      if (_roomId != null && !_disposed) {
        final payload = shape.toRtdbPayload()..['id'] = shapeId;
        _rtdbRoom.pushEvent(_roomId!, 'shape_delta', 'add', payload);
      }
    } catch (e) {
      debugPrint('도형 저장 오류: $e');
    }

    _shapeStartPoint = null;
    _shapeEndPoint = null;
    // 그리기 완료 후 도형 기능 비활성화 → 펜으로 전환
    setInputMode(InputMode.pen);
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
    _rtdbRoom.pushEvent(_roomId!, 'shape_delta', 'remove', {'id': shapeId});
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

  /// 이미지 업로드 (이미지 중앙이 화면 중앙에 오도록 배치)
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

    final tempId = 'upload-image-${DateTime.now().millisecondsSinceEpoch}';

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

      final viewSize = _getViewportCanvasSize();
      // 화면 비율에 맞게: 뷰포트 캔버스 크기 안에 맞추기 (100%면 뷰포트, 50%면 그 비율)
      double displayW = width.toDouble();
      double displayH = height.toDouble();
      if (viewSize != null && width > 0 && height > 0) {
        final scaleW = viewSize.width / width;
        final scaleH = viewSize.height / height;
        final scale = scaleW < scaleH ? scaleW : scaleH;
        displayW = width * scale;
        displayH = height * scale;
      } else if (width > 0 && height > 0) {
        const double maxSide = 600;
        if (width > maxSide || height > maxSide) {
          final scale = maxSide / (width > height ? width : height);
          displayW = width * scale;
          displayH = height * scale;
        }
      }
      // 사진 크기를 1/3로 (너무 크지 않게)
      displayW /= 3;
      displayH /= 3;

      // 이미지 중앙이 보이는 화면 중앙과 일치하도록 위치 계산 (좌상단 = 화면중앙 - 크기/2)
      final viewportCenter = _getViewportCenterInCanvas();
      if (viewportCenter != null) {
        position = viewportCenter - Offset(displayW / 2, displayH / 2);
      }

      // 플레이스홀더: 최종 이미지와 같은 크기로 생성 (너무 크지 않게)
      _uploadingPlaceholders.add(UploadingPlaceholder(
        tempId: tempId,
        x: position.dx,
        y: position.dy,
        width: displayW,
        height: displayH,
        type: MediaType.image,
      ));
      _notifyIfNotDisposed();

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
        final payload = media.toRtdbPayload()..['id'] = mediaId;
        _rtdbRoom.pushEvent(_roomId!, 'media_delta', 'add', payload);
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
    } finally {
      _uploadingPlaceholders.removeWhere((p) => p.tempId == tempId);
      _isUploading = false;
      _notifyIfNotDisposed();
    }
  }

  /// 영상 업로드 (영상 중앙이 화면 중앙에 오도록 배치)
  Future<void> uploadVideo(Offset position) async {
    if (_roomId == null || _userId == null) return;

    final file = await _mediaService.pickVideo();
    if (file == null) return;

    final viewSize = _getViewportCanvasSize();
    final placeW = viewSize?.width ?? 300.0;
    final placeH = viewSize?.height ?? 200.0;
    final viewportCenter = _getViewportCenterInCanvas();
    if (viewportCenter != null) {
      position = viewportCenter - Offset(placeW / 2, placeH / 2);
    }
    final tempId = 'upload-video-${DateTime.now().millisecondsSinceEpoch}';
    _uploadingPlaceholders.add(UploadingPlaceholder(
      tempId: tempId,
      x: position.dx,
      y: position.dy,
      width: placeW,
      height: placeH,
      type: MediaType.video,
    ));
    _isUploading = true;
    _notifyIfNotDisposed();

    try {
      final url = await _mediaService.uploadFile(
        roomId: _roomId!,
        filePath: file.path,
        fileName: file.name,
        type: MediaType.video,
      );

      // 영상 썸네일 생성·업로드 (캔버스에서 영상 확인 가능하도록)
      String? thumbnailUrl;
      final thumbBytes = await MediaService.getVideoThumbnailBytes(file.path);
      if (thumbBytes != null && thumbBytes.isNotEmpty) {
        try {
          thumbnailUrl = await _mediaService.uploadImageBytes(
            roomId: _roomId!,
            bytes: thumbBytes,
            fileName: 'thumb_${file.name}.jpg',
          );
        } catch (_) {
          // 썸네일 업로드 실패해도 영상은 저장
        }
      }

      final media = MediaModel(
        id: '',
        roomId: _roomId!,
        senderId: _userId!,
        type: MediaType.video,
        url: url,
        fileName: file.name,
        thumbnailUrl: thumbnailUrl,
        x: position.dx,
        y: position.dy,
        width: placeW,
        height: placeH,
        zIndex: _getMaxMediaZIndex() + 1,
        createdAt: DateTime.now(),
      );

      final mediaId = await _mediaService.saveMedia(media);
      if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
      _undoStack.add(_UndoEntry(_UndoEntryType.media, mediaId, true));
      _redoStack.clear();
      if (_roomId != null && !_disposed) {
        // 채팅 목록에서 영상 썸네일로 확인 가능하도록 thumbnailUrl 전달
        _roomService.updateLastEvent(
          _roomId!,
          eventType: 'video',
          preview: file.name,
          url: thumbnailUrl ?? url,
        );
        final payload = media.toRtdbPayload()..['id'] = mediaId;
        _rtdbRoom.pushEvent(_roomId!, 'media_delta', 'add', payload);
      }
    } catch (e) {
      debugPrint('영상 업로드 오류: $e');
    } finally {
      _uploadingPlaceholders.removeWhere((p) => p.tempId == tempId);
      _isUploading = false;
      _notifyIfNotDisposed();
    }
  }

  /// PDF 업로드 (PDF 중앙이 화면 중앙에 오도록 배치)
  Future<void> uploadPdf(Offset position) async {
    if (_roomId == null || _userId == null) return;

    final file = await _mediaService.pickPdf();
    if (file == null || file.path == null) return;

    // 플레이스홀더·최종 PDF 동일 크기 (A4 비율 210:297)
    const placeW = 210.0;
    const placeH = 297.0;
    final viewportCenter = _getViewportCenterInCanvas();
    if (viewportCenter != null) {
      position = viewportCenter - Offset(placeW / 2, placeH / 2);
    }
    final tempId = 'upload-pdf-${DateTime.now().millisecondsSinceEpoch}';
    _uploadingPlaceholders.add(UploadingPlaceholder(
      tempId: tempId,
      x: position.dx,
      y: position.dy,
      width: placeW,
      height: placeH,
      type: MediaType.pdf,
    ));
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
        width: placeW,
        height: placeH,
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
        final payload = media.toRtdbPayload()..['id'] = mediaId;
        _rtdbRoom.pushEvent(_roomId!, 'media_delta', 'add', payload);
      }
    } catch (e) {
      debugPrint('PDF 업로드 오류: $e');
    } finally {
      _uploadingPlaceholders.removeWhere((p) => p.tempId == tempId);
      _isUploading = false;
      _notifyIfNotDisposed();
    }
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

  /// 미디어 이동 (드래그 중에는 로컬만 반영, Firestore write는 드래그 종료 시 1회만)
  void moveMedia(String mediaId, Offset delta) {
    final idx = _serverMedia.indexWhere((m) => m.id == mediaId);
    if (idx < 0) return;
    final media = _serverMedia[idx];
    final newX = media.x + delta.dx;
    final newY = media.y + delta.dy;
    _serverMedia = List<MediaModel>.from(_serverMedia);
    _serverMedia[idx] = media.copyWith(x: newX, y: newY);
    if (_selectedMedia?.id == mediaId) _selectedMedia = _serverMedia[idx];
    _notifyIfNotDisposed();
  }

  /// 드래그 종료 시 호출: 현재 위치를 Firestore에 1회만 저장 (요금 절감)
  Future<void> moveMediaEnd(String mediaId) async {
    if (_roomId == null) return;
    final idx = _serverMedia.indexWhere((m) => m.id == mediaId);
    if (idx < 0) return;
    final media = _serverMedia[idx];
    await _mediaService.updateMedia(_roomId!, mediaId, x: media.x, y: media.y);
  }

  /// 미디어 크기 조절 (드래그 중에는 로컬만 반영, Firestore write는 리사이즈 종료 시 1회만)
  void resizeMedia(String mediaId, double width, double height, {double? x, double? y}) {
    final idx = _serverMedia.indexWhere((m) => m.id == mediaId);
    if (idx < 0) return;
    final media = _serverMedia[idx];
    _serverMedia = List<MediaModel>.from(_serverMedia);
    _serverMedia[idx] = media.copyWith(
      width: width,
      height: height,
      x: x ?? media.x,
      y: y ?? media.y,
    );
    if (_selectedMedia?.id == mediaId) _selectedMedia = _serverMedia[idx];
    _notifyIfNotDisposed();
  }

  /// 리사이즈/이동 종료 시 현재 미디어 위치·크기를 Firestore에 1회 저장
  Future<void> _persistMediaGeometry(String mediaId) async {
    if (_roomId == null) return;
    final idx = _serverMedia.indexWhere((m) => m.id == mediaId);
    if (idx < 0) return;
    final media = _serverMedia[idx];
    await _mediaService.updateMedia(
      _roomId!,
      mediaId,
      x: media.x,
      y: media.y,
      width: media.width,
      height: media.height,
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
    _rtdbRoom.pushEvent(_roomId!, 'media_delta', 'remove', {'id': mediaId});
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
    final newId = await _mediaService.saveMedia(copy);
    if (_roomId != null && !_disposed) {
      final payload = copy.toRtdbPayload()..['id'] = newId;
      _rtdbRoom.pushEvent(_roomId!, 'media_delta', 'add', payload);
    }
    _notifyIfNotDisposed();
  }

  /// 펜 선택 (도형/텍스트 모드 해제 → 손글씨 그리기로 전환)
  void selectPen(PenType pen) {
    _currentPen = pen;
    _inputMode = InputMode.pen;
    _selectionTool = SelectionTool.none;
    _notifyIfNotDisposed();
  }

  /// 선택 도구 선택 (자유형/사각형 선택 시 펜 모드로 전환 → 툴바에서 모두 선택 가능)
  void selectSelectionTool(SelectionTool tool) {
    _selectionTool = tool;
    if (tool == SelectionTool.lasso || tool == SelectionTool.rectangle) {
      _inputMode = InputMode.pen;
    }
    _notifyIfNotDisposed();
  }

  // ===== 손글씨 선택 (자유형/사각형, 다중 선택, 이동/삭제/복사) =====

  final Set<String> _selectedStrokeIds = {};
  Set<String> get selectedStrokeIds => Set.unmodifiable(_selectedStrokeIds);
  bool get hasSelectedStrokes => _selectedStrokeIds.isNotEmpty;

  /// 자유형/사각형 선택으로 선택된 미디어(사진·영상·PDF) ID
  final Set<String> _selectedMediaIds = {};
  Set<String> get selectedMediaIds => Set.unmodifiable(_selectedMediaIds);
  bool get hasSelectedMedia => _selectedMediaIds.isNotEmpty;

  /// 자유형/사각형 선택으로 선택된 텍스트 ID
  final Set<String> _selectedTextIds = {};
  Set<String> get selectedTextIds => Set.unmodifiable(_selectedTextIds);
  bool get hasSelectedTexts => _selectedTextIds.isNotEmpty;

  /// 손글씨·미디어·텍스트 중 하나라도 선택됐는지
  bool get hasSelectedStrokesOrMediaOrText =>
      hasSelectedStrokes || hasSelectedMedia || hasSelectedTexts;

  /// 선택 그리기 중 경로 (올가미) 또는 null
  List<Offset>? _selectionPath;
  List<Offset>? get selectionPath => _selectionPath;

  /// 선택 그리기 중 사각형 (시작점, 현재점) 또는 null
  (Offset, Offset)? _selectionRect;
  (Offset, Offset)? get selectionRect => _selectionRect;

  bool _isDrawingSelection = false;
  bool get isDrawingSelection => _isDrawingSelection;

  /// 선택 영역 이동 모드
  bool _isMovingSelection = false;
  Offset? _moveSelectionStart;
  bool get isMovingSelection => _isMovingSelection;

  void startSelection(Offset point) {
    if (_selectionTool == SelectionTool.none) return;
    _isDrawingSelection = true;
    if (_selectionTool == SelectionTool.lasso) {
      _selectionPath = [point];
    } else {
      _selectionRect = (point, point);
    }
    _notifyIfNotDisposed();
  }

  void updateSelection(Offset point) {
    if (!_isDrawingSelection) return;
    if (_selectionTool == SelectionTool.lasso && _selectionPath != null) {
      _selectionPath!.add(point);
    } else if (_selectionTool == SelectionTool.rectangle && _selectionRect != null) {
      _selectionRect = (_selectionRect!.$1, point);
    }
    _notifyIfNotDisposed();
  }

  void endSelection() {
    if (!_isDrawingSelection) return;
    _isDrawingSelection = false;

    final strokeIds = _strokeIdsInSelection();
    final mediaIds = _mediaIdsInSelection();
    final textIds = _textIdsInSelection();
    _selectionPath = null;
    _selectionRect = null;

    _selectedStrokeIds.clear();
    _selectedMediaIds.clear();
    _selectedTextIds.clear();
    if (strokeIds.isNotEmpty) _selectedStrokeIds.addAll(strokeIds);
    if (mediaIds.isNotEmpty) _selectedMediaIds.addAll(mediaIds);
    if (textIds.isNotEmpty) _selectedTextIds.addAll(textIds);
    _notifyIfNotDisposed();
  }

  /// 선택 영역 내 스트로크 ID 목록
  Set<String> _strokeIdsInSelection() {
    final result = <String>{};
    final allStrokes = _getAllStrokesForSelection();

    if (_selectionTool == SelectionTool.lasso && _selectionPath != null && _selectionPath!.length >= 3) {
      final path = _selectionPath!;
      for (final stroke in allStrokes) {
        if (_strokeIntersectsLasso(stroke, path)) result.add(_getStrokeId(stroke));
      }
    } else if (_selectionTool == SelectionTool.rectangle && _selectionRect != null) {
      final (a, b) = _selectionRect!;
      final rect = Rect.fromPoints(a, b);
      for (final stroke in allStrokes) {
        if (_strokeIntersectsRect(stroke, rect)) result.add(_getStrokeId(stroke));
      }
    }
    return result;
  }

  List<dynamic> _getAllStrokesForSelection() {
    final list = <dynamic>[];
    for (final s in _serverStrokes) {
      if (!s.isDeleted) list.add(s);
    }
    for (final s in _localStrokes) {
      list.add(s);
    }
    return list;
  }

  String _getStrokeId(dynamic s) {
    if (s is StrokeModel) return s.id;
    if (s is LocalStrokeData) return s.firestoreId ?? s.id;
    return '';
  }

  Rect _strokeBoundingBox(dynamic s) {
    List<Offset> points;
    if (s is StrokeModel) {
      points = s.points.map((p) => Offset(p.x, p.y)).toList();
    } else if (s is LocalStrokeData) {
      points = s.points.map((p) => p.offset).toList();
    } else {
      return Rect.zero;
    }
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _strokeIntersectsRect(dynamic stroke, Rect rect) {
    return rect.overlaps(_strokeBoundingBox(stroke));
  }

  static bool _pointInPolygon(Offset p, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  bool _strokeIntersectsLasso(dynamic stroke, List<Offset> path) {
    final bbox = _strokeBoundingBox(stroke);
    final center = bbox.center;
    return _pointInPolygon(center, path);
  }

  /// 선택 영역 내 미디어(사진·영상·PDF) ID 목록
  Set<String> _mediaIdsInSelection() {
    final result = <String>{};
    if (_selectionTool == SelectionTool.lasso && _selectionPath != null && _selectionPath!.length >= 3) {
      final path = _selectionPath!;
      final pathRect = _rectFromPoints(path);
      for (final media in _serverMedia) {
        final rect = Rect.fromLTWH(media.x, media.y, media.width, media.height);
        if (!pathRect.overlaps(rect)) continue;
        if (_pointInPolygon(rect.center, path)) result.add(media.id);
      }
    } else if (_selectionTool == SelectionTool.rectangle && _selectionRect != null) {
      final (a, b) = _selectionRect!;
      final selRect = Rect.fromPoints(a, b);
      for (final media in _serverMedia) {
        final rect = Rect.fromLTWH(media.x, media.y, media.width, media.height);
        if (selRect.overlaps(rect)) result.add(media.id);
      }
    }
    return result;
  }

  /// 선택 영역 내 텍스트 ID 목록
  Set<String> _textIdsInSelection() {
    final result = <String>{};
    if (_selectionTool == SelectionTool.lasso && _selectionPath != null && _selectionPath!.length >= 3) {
      final path = _selectionPath!;
      final pathRect = _rectFromPoints(path);
      for (final text in _serverTexts) {
        final x = text.positionX ?? 0.0;
        final y = text.positionY ?? 0.0;
        final w = (text.width != null && text.width! > 0)
            ? text.width!
            : ((text.content?.length ?? 0) * 10.0).clamp(40.0, 400.0);
        final h = text.height ?? 24.0;
        final rect = Rect.fromLTWH(x, y, w, h);
        if (!pathRect.overlaps(rect)) continue;
        if (_pointInPolygon(rect.center, path)) result.add(text.id);
      }
    } else if (_selectionTool == SelectionTool.rectangle && _selectionRect != null) {
      final (a, b) = _selectionRect!;
      final selRect = Rect.fromPoints(a, b);
      for (final text in _serverTexts) {
        final x = text.positionX ?? 0.0;
        final y = text.positionY ?? 0.0;
        final w = (text.width != null && text.width! > 0)
            ? text.width!
            : ((text.content?.length ?? 0) * 10.0).clamp(40.0, 400.0);
        final h = text.height ?? 24.0;
        final rect = Rect.fromLTWH(x, y, w, h);
        if (selRect.overlaps(rect)) result.add(text.id);
      }
    }
    return result;
  }

  Rect _rectFromPoints(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void clearStrokeSelection() {
    _selectedStrokeIds.clear();
    _selectedMediaIds.clear();
    _selectedTextIds.clear();
    _selectedMedia = null;
    _notifyIfNotDisposed();
  }

  void toggleStrokeInSelection(String id) {
    if (_selectedStrokeIds.contains(id)) {
      _selectedStrokeIds.remove(id);
    } else {
      _selectedStrokeIds.add(id);
    }
    _notifyIfNotDisposed();
  }

  /// 선택된 스트로크 삭제
  Future<void> deleteSelectedStrokes() async {
    if (_roomId == null || _selectedStrokeIds.isEmpty) return;
    final ids = List<String>.from(_selectedStrokeIds);
    await _strokeService.deleteStrokes(_roomId!, ids, userId: _userId);
    for (final id in ids) {
      _rtdbRoom.pushEvent(_roomId!, 'stroke_delta', 'remove', {'id': id});
    }
    _selectedStrokeIds.clear();
    for (final id in ids) {
      if (_undoStack.length >= undoRedoLimit) _undoStack.removeAt(0);
      _undoStack.add(_UndoEntry(_UndoEntryType.stroke, id, false));
    }
    _redoStack.clear();
    _notifyIfNotDisposed();
  }

  /// 선택된 항목 전체 삭제 (손글씨·미디어·텍스트)
  Future<void> deleteSelection() async {
    if (_roomId == null) return;
    final strokeIds = List<String>.from(_selectedStrokeIds);
    final mediaIds = List<String>.from(_selectedMediaIds);
    final textIds = List<String>.from(_selectedTextIds);
    if (strokeIds.isNotEmpty) await deleteSelectedStrokes();
    for (final id in mediaIds) {
      await deleteMedia(id);
    }
    _selectedMediaIds.clear();
    if (_selectedMedia != null && mediaIds.contains(_selectedMedia!.id)) {
      _selectedMedia = null;
    }
    for (final id in textIds) {
      _rtdbRoom.pushEvent(_roomId!, 'text_delta', 'remove', {'id': id});
      await _textService.deleteText(_roomId!, id, userId: _userId);
    }
    _selectedTextIds.clear();
    _notifyIfNotDisposed();
  }

  /// 선택된 항목 전체 복사 (손글씨 오프셋 저장, 미디어·텍스트 복제)
  Future<void> copySelection({Offset offset = const Offset(24, 24)}) async {
    if (_roomId == null || _userId == null) return;
    if (_selectedStrokeIds.isNotEmpty) await copySelectedStrokes(offset: offset);
    for (final id in _selectedMediaIds) {
      await duplicateMedia(id);
    }
    for (final id in _selectedTextIds) {
      final idx = _serverTexts.indexWhere((t) => t.id == id);
      if (idx >= 0) {
        final text = _serverTexts[idx];
        if (text.content != null && text.content!.isNotEmpty) {
          final px = text.positionX ?? 0.0;
          final py = text.positionY ?? 0.0;
          await addText(text.content!, Offset(px + offset.dx, py + offset.dy));
        }
      }
    }
    _notifyIfNotDisposed();
  }

  /// 선택된 스트로크 복사 (오프셋 적용 후 새로 저장)
  Future<void> copySelectedStrokes({Offset offset = const Offset(24, 24)}) async {
    if (_roomId == null || _userId == null || _selectedStrokeIds.isEmpty) return;
    final allStrokes = _getAllStrokesForSelection();
    for (final s in allStrokes) {
      final id = _getStrokeId(s);
      if (!_selectedStrokeIds.contains(id)) continue;

      List<StrokePoint> points;
      PenStyle style;
      if (s is StrokeModel) {
        points = s.points.map((p) => StrokePoint(
          x: p.x + offset.dx,
          y: p.y + offset.dy,
          pressure: p.pressure,
          timestamp: p.timestamp,
        )).toList();
        style = s.style;
      } else if (s is LocalStrokeData) {
        points = s.points.map((p) => StrokePoint(
          x: p.x + offset.dx,
          y: p.y + offset.dy,
          pressure: p.pressure,
          timestamp: p.timestamp,
        )).toList();
        final hex = s.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
        style = PenStyle(color: '#$hex', width: s.strokeWidth, penType: s.penType.name);
      } else {
        continue;
      }

      final model = StrokeModel(
        id: '',
        roomId: _roomId!,
        senderId: _userId!,
        points: points,
        style: style,
        createdAt: DateTime.now(),
      );
      await _strokeService.saveStroke(model);
    }
    _notifyIfNotDisposed();
  }

  /// 선택된 스트로크·미디어·텍스트 이동
  void startMovingSelection(Offset point) {
    if (!hasSelectedStrokesOrMediaOrText) return;
    _isMovingSelection = true;
    _moveSelectionStart = point;
    _notifyIfNotDisposed();
  }

  void updateMovingSelection(Offset point) {
    if (!_isMovingSelection || _moveSelectionStart == null) return;
    final delta = point - _moveSelectionStart!;
    _moveSelectionStart = point;
    _applyMoveDeltaToSelectedStrokes(delta);
    _applyMoveDeltaToSelectedMedia(delta);
    _applyMoveDeltaToSelectedTexts(delta);
    _notifyIfNotDisposed();
  }

  Future<void> endMovingSelection() async {
    if (!_isMovingSelection || _roomId == null) return;
    _isMovingSelection = false;
    _moveSelectionStart = null;
    await _persistMovedStrokes();
    for (final id in _selectedMediaIds) {
      await moveMediaEnd(id);
    }
    await _persistMovedTexts();
    _notifyIfNotDisposed();
  }

  void _applyMoveDeltaToSelectedMedia(Offset delta) {
    for (final id in _selectedMediaIds) {
      moveMedia(id, delta);
    }
  }

  void _applyMoveDeltaToSelectedTexts(Offset delta) {
    _serverTexts = _serverTexts.map((text) {
      if (!_selectedTextIds.contains(text.id)) return text;
      final nx = (text.positionX ?? 0) + delta.dx;
      final ny = (text.positionY ?? 0) + delta.dy;
      return MessageModel(
        id: text.id,
        roomId: text.roomId,
        senderId: text.senderId,
        type: text.type,
        content: text.content,
        fileUrl: text.fileUrl,
        fileName: text.fileName,
        fileSize: text.fileSize,
        thumbnailUrl: text.thumbnailUrl,
        positionX: nx,
        positionY: ny,
        width: text.width,
        height: text.height,
        fontSize: text.fontSize,
        opacity: text.opacity,
        createdAt: text.createdAt,
        isDeleted: text.isDeleted,
      );
    }).toList();
  }

  Future<void> _persistMovedTexts() async {
    if (_roomId == null) return;
    for (final id in _selectedTextIds) {
      final idx = _serverTexts.indexWhere((t) => t.id == id);
      if (idx >= 0) {
        final text = _serverTexts[idx];
        await _textService.updateText(
          _roomId!,
          id,
          positionX: text.positionX,
          positionY: text.positionY,
        );
      }
    }
  }

  void _applyMoveDeltaToSelectedStrokes(Offset delta) {
    for (final s in _serverStrokes) {
      if (!_selectedStrokeIds.contains(s.id)) continue;
      final idx = _serverStrokes.indexWhere((x) => x.id == s.id);
      if (idx < 0) continue;
      final updated = StrokeModel(
        id: s.id,
        roomId: s.roomId,
        senderId: s.senderId,
        points: s.points.map((p) => StrokePoint(
          x: p.x + delta.dx,
          y: p.y + delta.dy,
          pressure: p.pressure,
          timestamp: p.timestamp,
        )).toList(),
        style: s.style,
        createdAt: s.createdAt,
        isConfirmed: s.isConfirmed,
        isDeleted: s.isDeleted,
      );
      _serverStrokes = List<StrokeModel>.from(_serverStrokes);
      _serverStrokes[idx] = updated;
    }
    for (final s in _localStrokes) {
      if (!_selectedStrokeIds.contains(s.firestoreId ?? s.id)) continue;
      for (int i = 0; i < s.points.length; i++) {
        s.points[i] = LocalStrokePoint(
          x: s.points[i].x + delta.dx,
          y: s.points[i].y + delta.dy,
          pressure: s.points[i].pressure,
          timestamp: s.points[i].timestamp,
        );
      }
    }
  }

  Future<void> _persistMovedStrokes() async {
    if (_roomId == null) return;
    for (final s in _serverStrokes) {
      if (!_selectedStrokeIds.contains(s.id)) continue;
      await _strokeService.updateStrokePoints(_roomId!, s.id, s.points);
    }
  }

  /// 포인트가 선택된 스트로크 위에 있는지
  bool isPointOnSelectedStroke(Offset canvasPoint) {
    const margin = 16.0;
    for (final s in _serverStrokes) {
      if (!_selectedStrokeIds.contains(s.id)) continue;
      final bbox = _strokeBoundingBox(s);
      if (bbox.inflate(margin).contains(canvasPoint)) return true;
    }
    for (final s in _localStrokes) {
      final id = s.firestoreId ?? s.id;
      if (!_selectedStrokeIds.contains(id)) continue;
      final bbox = _strokeBoundingBox(s);
      if (bbox.inflate(margin).contains(canvasPoint)) return true;
    }
    return false;
  }

  /// 포인트가 선택된 영역(손글씨·미디어·텍스트) 위에 있는지 (이동 제스처용)
  bool isPointOnSelectedSelection(Offset canvasPoint) {
    if (isPointOnSelectedStroke(canvasPoint)) return true;
    for (final id in _selectedMediaIds) {
      final idx = _serverMedia.indexWhere((m) => m.id == id);
      if (idx < 0) continue;
      final media = _serverMedia[idx];
      final rect = Rect.fromLTWH(media.x, media.y, media.width, media.height);
      if (rect.contains(canvasPoint)) return true;
    }
    for (final id in _selectedTextIds) {
      final idx = _serverTexts.indexWhere((t) => t.id == id);
      if (idx < 0) continue;
      final text = _serverTexts[idx];
      final x = text.positionX ?? 0.0;
      final y = text.positionY ?? 0.0;
      final w = (text.width != null && text.width! > 0)
          ? text.width!
          : ((text.content?.length ?? 0) * 10.0).clamp(40.0, 400.0);
      final h = text.height ?? 24.0;
      if (Rect.fromLTWH(x, y, w, h).contains(canvasPoint)) return true;
    }
    return false;
  }

  void cancelSelectionDrawing() {
    _isDrawingSelection = false;
    _selectionPath = null;
    _selectionRect = null;
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
  void startStroke(Offset point, {bool forceEraser = false, double pressure = 1.0, int? timestamp}) {
    if (_userId == null || _roomId == null) return;

    if (_currentPen == PenType.eraser || forceEraser) {
      _eraseAtPoint(point);
      return;
    }

    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final id = '${_userId}_${ts}';
    _currentStroke = LocalStrokeData(
      id: id,
      senderId: _userId!,
      senderName: _userName,
      points: [LocalStrokePoint(x: point.dx, y: point.dy, pressure: pressure, timestamp: ts)],
      color: currentColor,
      strokeWidth: currentWidth,
      penType: _currentPen,
      createdAt: DateTime.now(),
    );
    _notifyIfNotDisposed();
  }

  /// 그리기 중 (forceEraser: 펜 옆 버튼 눌렀을 때 지우개로 전환)
  void updateStroke(Offset point, {bool forceEraser = false, double pressure = 1.0, int? timestamp}) {
    if (_currentPen == PenType.eraser || forceEraser) {
      _eraseAtPoint(point);
      return;
    }

    if (_currentStroke != null) {
      final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
      _currentStroke!.points.add(LocalStrokePoint(x: point.dx, y: point.dy, pressure: pressure, timestamp: ts));
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

    // 압축 없이 원본 포인트 그대로 저장, 필압력 포함
    final points = stroke.points.map((p) {
      return StrokePoint(
        x: p.x,
        y: p.y,
        pressure: p.pressure,
        timestamp: p.timestamp,
      );
    }).toList();
    final strokeModel = StrokeModel(
      id: stroke.id,
      roomId: _roomId!,
      senderId: stroke.senderId,
      points: points,
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
        final payload = strokeModel.toRtdbPayload()..['id'] = firestoreId;
        _rtdbRoom.pushEvent(_roomId!, 'stroke_delta', 'add', payload);
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
          final payload = item.model.toRtdbPayload()..['id'] = firestoreId;
          _rtdbRoom.pushEvent(_roomId!, 'stroke_delta', 'add', payload);
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
    if (_roomId != null) {
      _rtdbRoom.pushEvent(_roomId!, 'stroke_delta', 'update', {'id': stroke.firestoreId!, 'isConfirmed': true});
    }
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
        if ((pts[i].offset - point).distance <= radius) {
          hit = true;
          break;
        }
        if (i < pts.length - 1) {
          if (_distancePointToSegment(point, pts[i].offset, pts[i + 1].offset) <= radius) {
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
    if (_roomId != null) {
      switch (entry.type) {
        case _UndoEntryType.stroke:
          _rtdbRoom.pushEvent(_roomId!, 'stroke_delta', 'remove', {'id': entry.id});
          await _strokeService.deleteStroke(_roomId!, entry.id, userId: _userId);
          break;
        case _UndoEntryType.shape:
          _rtdbRoom.pushEvent(_roomId!, 'shape_delta', 'remove', {'id': entry.id});
          await _shapeService.deleteShape(_roomId!, entry.id, userId: _userId);
          if (_selectedShape?.id == entry.id) {
            _selectedShape = null;
          }
          break;
        case _UndoEntryType.media:
          _rtdbRoom.pushEvent(_roomId!, 'media_delta', 'remove', {'id': entry.id});
          await _mediaService.deleteMedia(_roomId!, entry.id, userId: _userId);
          break;
      }
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
    if (_roomId != null) {
      _roomCanvasViewState[_roomId!] = _SavedCanvasView(_canvasOffset, _canvasScale);
    }
    if (_roomId != null && _userId != null) {
      _rtdbRoom.setRoomMember(_roomId!, _userId!, false);
    }
    _strokesSubscription?.cancel();
    _textsSubscription?.cancel();
    _shapesSubscription?.cancel();
    _mediaSubscription?.cancel();
    _rtdbSubscription?.cancel();
    _confirmTimer?.cancel();
    super.dispose();
  }
}

class _PendingStroke {
  final LocalStrokeData stroke;
  final StrokeModel model;
  _PendingStroke({required this.stroke, required this.model});
}
