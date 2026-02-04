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
import '../../services/settings_service.dart';

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
  shape,     // 도형 그리기
}

/// 캔버스 컨트롤러 (실시간 동기화 포함)
class CanvasController extends ChangeNotifier {
  final StrokeService _strokeService = StrokeService();
  final TextService _textService = TextService();
  final ShapeService _shapeService = ShapeService();
  final MediaService _mediaService = MediaService();
  StreamSubscription<List<StrokeModel>>? _strokesSubscription;
  StreamSubscription<List<MessageModel>>? _textsSubscription;
  StreamSubscription<List<ShapeModel>>? _shapesSubscription;
  StreamSubscription<List<MediaModel>>? _mediaSubscription;

  String? _roomId;
  String? _userId;
  String? _userName;
  /// 방 설정: 캔버스 확장 방식 (방장이 방 설정에서 지정, 확장 로직에서 사용)
  CanvasExpandMode? _canvasExpandMode;
  CanvasExpandMode get canvasExpandMode =>
      _canvasExpandMode ?? CanvasExpandMode.rectangular;

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
  bool isMediaInResizeMode(String mediaId) => _mediaInResizeMode == mediaId;
  void enterMediaResizeMode(String mediaId) {
    try {
      final media = _serverMedia.firstWhere((m) => m.id == mediaId);
      _mediaInResizeMode = mediaId;
      _selectedMedia = media;
      notifyListeners();
    } catch (_) {}
  }
  void clearMediaResizeMode() {
    if (_mediaInResizeMode != null) {
      _mediaInResizeMode = null;
      notifyListeners();
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
  void initialize(String roomId, String userId,
      {String? userName, CanvasExpandMode? canvasExpandMode}) {
    _roomId = roomId;
    _userId = userId;
    _userName = userName;
    _canvasExpandMode = canvasExpandMode;

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

    // 실시간 도형 구독
    _shapesSubscription?.cancel();
    _shapesSubscription = _shapeService.getShapesStream(roomId).listen(
      (shapes) {
        _serverShapes = shapes;
        notifyListeners();
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
        notifyListeners();
      },
      onError: (e) {
        debugPrint('미디어 스트림 오류: $e');
      },
    );
  }

  /// 입력 모드 변경
  void setInputMode(InputMode mode) {
    _inputMode = mode;
    _selectedMedia = null;
    _selectedShape = null;
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

  // ===== 도형 관련 =====

  /// 도형 타입 선택
  void selectShapeType(ShapeType type) {
    _currentShapeType = type;
    _inputMode = InputMode.shape;
    notifyListeners();
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
    notifyListeners();
  }

  /// 도형 그리기 시작
  void startShape(Offset point) {
    if (_inputMode != InputMode.shape) return;
    _shapeStartPoint = _snapToGrid(point);
    _shapeEndPoint = _shapeStartPoint;
    notifyListeners();
  }

  /// 도형 그리기 중
  void updateShape(Offset point) {
    if (_shapeStartPoint == null) return;
    _shapeEndPoint = _snapToGrid(point);
    notifyListeners();
  }

  /// 도형 그리기 끝
  Future<void> endShape() async {
    if (_shapeStartPoint == null || _shapeEndPoint == null || _roomId == null || _userId == null) {
      _shapeStartPoint = null;
      _shapeEndPoint = null;
      notifyListeners();
      return;
    }

    // 최소 크기 체크
    final dx = (_shapeEndPoint!.dx - _shapeStartPoint!.dx).abs();
    final dy = (_shapeEndPoint!.dy - _shapeStartPoint!.dy).abs();
    if (dx < 5 && dy < 5) {
      _shapeStartPoint = null;
      _shapeEndPoint = null;
      notifyListeners();
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
      await _shapeService.saveShape(shape);
    } catch (e) {
      debugPrint('도형 저장 오류: $e');
    }

    _shapeStartPoint = null;
    _shapeEndPoint = null;
    notifyListeners();
  }

  /// 스냅 토글
  void toggleSnap() {
    _snapEnabled = !_snapEnabled;
    notifyListeners();
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
    notifyListeners();
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

  /// 도형 삭제
  Future<void> deleteShape(String shapeId) async {
    if (_roomId == null) return;
    await _shapeService.deleteShape(_roomId!, shapeId);
    if (_selectedShape?.id == shapeId) {
      _selectedShape = null;
      notifyListeners();
    }
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
    notifyListeners();

    XFile? file;
    try {
      file = await _mediaService.pickImage();
    } catch (e) {
      debugPrint('갤러리 열기 오류: $e');
      _isUploading = false;
      notifyListeners();
      uploadMessageCallback?.call('사진 선택 중 오류가 났습니다. 권한을 확인해 주세요.');
      return;
    }

    if (file == null) {
      _isUploading = false;
      notifyListeners();
      uploadMessageCallback?.call('사진 선택이 취소되었습니다.');
      return;
    }

    try {
      final url = await _mediaService.uploadImageFile(
        roomId: _roomId!,
        imageFile: file,
      );

      final fileName = file.name.isNotEmpty ? file.name : 'image.jpg';
      final media = MediaModel(
        id: '',
        roomId: _roomId!,
        senderId: _userId!,
        type: MediaType.image,
        url: url,
        fileName: fileName,
        x: position.dx,
        y: position.dy,
        width: 200,
        height: 200,
        zIndex: _getMaxMediaZIndex() + 1,
        createdAt: DateTime.now(),
      );

      await _mediaService.saveMedia(media);
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
    notifyListeners();
  }

  /// 영상 업로드
  Future<void> uploadVideo(Offset position) async {
    if (_roomId == null || _userId == null) return;

    final file = await _mediaService.pickVideo();
    if (file == null) return;

    _isUploading = true;
    notifyListeners();

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

      await _mediaService.saveMedia(media);
    } catch (e) {
      debugPrint('영상 업로드 오류: $e');
    }

    _isUploading = false;
    notifyListeners();
  }

  /// PDF 업로드
  Future<void> uploadPdf(Offset position) async {
    if (_roomId == null || _userId == null) return;

    final file = await _mediaService.pickPdf();
    if (file == null || file.path == null) return;

    _isUploading = true;
    notifyListeners();

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

      await _mediaService.saveMedia(media);
    } catch (e) {
      debugPrint('PDF 업로드 오류: $e');
    }

    _isUploading = false;
    notifyListeners();
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
    notifyListeners();
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

  /// 미디어 삭제
  Future<void> deleteMedia(String mediaId) async {
    if (_roomId == null) return;
    await _mediaService.deleteMedia(_roomId!, mediaId);
    if (_selectedMedia?.id == mediaId) {
      _selectedMedia = null;
      notifyListeners();
    }
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

    final points = stroke.points.map((p) {
      return StrokePoint(
        x: p.dx,
        y: p.dy,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
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

    try {
      final firestoreId = await _strokeService.saveStroke(strokeModel);
      stroke.firestoreId = firestoreId;

      _confirmTimer?.cancel();
      _confirmTimer = Timer(_confirmDelay, () {
        _confirmStroke(stroke);
      });

      _undoStack.add(firestoreId);
      _redoStack.clear();
    } catch (e) {
      debugPrint('스트로크 저장 오류: $e');
      _pendingRetry.add(_PendingStroke(stroke: stroke, model: strokeModel));
      notifyListeners();
    }
  }

  /// 대기열 스트로크 재전송 (재연결 후 호출)
  Future<void> retryPendingStrokes() async {
    if (_pendingRetry.isEmpty || _roomId == null) return;

    final toRetry = List<_PendingStroke>.from(_pendingRetry);
    _pendingRetry.clear();
    notifyListeners();

    for (final item in toRetry) {
      try {
        final firestoreId = await _strokeService.saveStroke(item.model);
        item.stroke.firestoreId = firestoreId;
        _confirmTimer?.cancel();
        _confirmTimer = Timer(_confirmDelay, () {
          _confirmStroke(item.stroke);
        });
        _undoStack.add(firestoreId);
        _redoStack.clear();
      } catch (e) {
        debugPrint('재전송 실패: $e');
        _pendingRetry.add(item);
      }
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

  /// 캔버스 확대/축소 (scale: 배율, focalPoint: 화면상의 초점)
  void zoom(double scale, Offset focalPoint) {
    final newScale = (_canvasScale * scale).clamp(0.1, 5.0);

    final focalPointDelta = focalPoint - _canvasOffset;
    _canvasOffset = focalPoint - focalPointDelta * (newScale / _canvasScale);
    _canvasScale = newScale;

    notifyListeners();
  }

  /// 버튼으로 확대 (우측 하단 + 버튼용)
  void zoomIn(Offset viewportCenter) {
    zoom(1.25, viewportCenter);
  }

  /// 버튼으로 축소 (우측 하단 - 버튼용)
  void zoomOut(Offset viewportCenter) {
    zoom(0.8, viewportCenter);
  }

  /// 특정 위치로 점프 (시간순 네비게이션용)
  void jumpToPosition(Offset canvasPosition, Size viewportSize) {
    // 해당 위치가 화면 중앙에 오도록 오프셋 계산
    _canvasOffset = Offset(
      -canvasPosition.dx * _canvasScale + viewportSize.width / 2,
      -canvasPosition.dy * _canvasScale + viewportSize.height / 2,
    );
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
