import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/room_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../services/export_service.dart';
import '../../widgets/canvas/drawing_canvas.dart';
import '../../widgets/canvas/pen_toolbar.dart';
import 'canvas_controller.dart';

/// 캔버스(채팅방) 화면
class CanvasScreen extends StatefulWidget {
  final RoomModel room;
  final Offset? jumpToPosition; // 태그 원본 점프용

  const CanvasScreen({
    super.key,
    required this.room,
    this.jumpToPosition,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  late CanvasController _canvasController;
  final TextEditingController _quickTextController = TextEditingController();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _canvasController = CanvasController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.user?.uid;
      final userName = authProvider.user?.displayName;
      
      if (userId != null) {
        _canvasController.initialize(
          widget.room.id,
          userId,
          userName: userName,
        );
        _isInitialized = true;

        // 태그 원본 점프
        if (widget.jumpToPosition != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final size = MediaQuery.of(context).size;
            _canvasController.jumpToPosition(widget.jumpToPosition!, size);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _canvasController.dispose();
    _quickTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final roomProvider = context.watch<RoomProvider>();
    final userId = authProvider.user?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Text(
          roomProvider.getRoomDisplayName(widget.room, userId),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          // 멤버 수
          if (widget.room.type == RoomType.group)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '${widget.room.memberIds.length}명',
                  style: const TextStyle(
                    color: AppColors.mutedGray,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          // 검색
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: 검색
            },
          ),
          // 자료
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            onPressed: () {
              // TODO: 공유 파일/미디어
            },
          ),
          // 더보기
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMoreOptions(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 펜 툴바 (상단 중앙)
              ListenableBuilder(
                listenable: _canvasController,
                builder: (context, _) {
                  return PenToolbar(
                    controller: _canvasController,
                  );
                },
              ),

              // 캔버스
              Expanded(
                child: ListenableBuilder(
                  listenable: _canvasController,
                  builder: (context, _) {
                    return DrawingCanvas(
                      controller: _canvasController,
                      userId: userId,
                      roomId: widget.room.id,
                    );
                  },
                ),
              ),
            ],
          ),

          // 빠른 텍스트 입력 (우측 하단)
          ListenableBuilder(
            listenable: _canvasController,
            builder: (context, _) {
              if (_canvasController.inputMode == InputMode.quickText) {
                return _buildQuickTextInput();
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  /// 빠른 텍스트 입력 UI
  Widget _buildQuickTextInput() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _quickTextController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '빠른 텍스트 입력...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                onSubmitted: _submitQuickText,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: AppColors.gold),
              onPressed: () => _submitQuickText(_quickTextController.text),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.mutedGray),
              onPressed: () {
                _canvasController.setInputMode(InputMode.pen);
                _quickTextController.clear();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _submitQuickText(String text) {
    if (text.isNotEmpty) {
      _canvasController.addQuickText(text);
      _quickTextController.clear();
    }
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('링크 공유'),
                onTap: () {
                  Navigator.pop(context);
                  _shareLink();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('멤버 보기'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 멤버 보기
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('채팅방 설정'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 설정
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('내보내기'),
                onTap: () {
                  Navigator.pop(context);
                  _showExportDialog();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// 링크 공유
  void _shareLink() async {
    final authProvider = context.read<AuthProvider>();
    final exportService = ExportService();

    final link = await exportService.createShareLink(
      roomId: widget.room.id,
      userId: authProvider.user?.uid ?? '',
    );

    if (link != null) {
      await exportService.shareLink(
        link,
        message: '${widget.room.name ?? 'INK 채팅방'}에 초대합니다!\n$link',
      );
    }
  }

  /// 내보내기 다이얼로그
  void _showExportDialog() {
    final authProvider = context.read<AuthProvider>();
    ExportFormat selectedFormat = ExportFormat.png;
    bool includeWatermark = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.paper,
              title: const Text('내보내기'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('포맷', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('PNG'),
                        selected: selectedFormat == ExportFormat.png,
                        selectedColor: AppColors.gold.withValues(alpha: 0.2),
                        onSelected: (_) => setState(() => selectedFormat = ExportFormat.png),
                      ),
                      ChoiceChip(
                        label: const Text('JPG'),
                        selected: selectedFormat == ExportFormat.jpg,
                        selectedColor: AppColors.gold.withValues(alpha: 0.2),
                        onSelected: (_) => setState(() => selectedFormat = ExportFormat.jpg),
                      ),
                      ChoiceChip(
                        label: const Text('PDF'),
                        selected: selectedFormat == ExportFormat.pdf,
                        selectedColor: AppColors.gold.withValues(alpha: 0.2),
                        onSelected: (_) => setState(() => selectedFormat = ExportFormat.pdf),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('워터마크 포함'),
                    subtitle: Text(
                      '${authProvider.user?.displayName ?? '사용자'} · INK',
                      style: const TextStyle(fontSize: 12, color: AppColors.mutedGray),
                    ),
                    value: includeWatermark,
                    activeColor: AppColors.gold,
                    onChanged: (value) => setState(() => includeWatermark = value ?? true),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _exportCanvas(selectedFormat, includeWatermark);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('내보내기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 캔버스 내보내기 실행
  void _exportCanvas(ExportFormat format, bool includeWatermark) async {
    // TODO: 실제 캔버스 캡처 구현 시 사용
    // final authProvider = context.read<AuthProvider>();
    // final exportService = ExportService();

    // 로딩 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      ),
    );

    try {
      // 캔버스 캡처 (TODO: 실제 캔버스 캡처 구현 필요)
      // 현재는 데모용 메시지
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        Navigator.pop(context); // 로딩 닫기
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${format.name.toUpperCase()} 형식으로 내보내기 준비 중...'),
            backgroundColor: AppColors.gold,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('내보내기 실패'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
