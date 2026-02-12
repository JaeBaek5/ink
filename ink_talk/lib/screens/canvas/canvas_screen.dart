import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/room_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/room_provider.dart';
import '../../services/export_service.dart';
import '../../services/network_connectivity_service.dart';
import '../../widgets/canvas/drawing_canvas.dart';
import '../../widgets/canvas/pen_toolbar.dart';
import '../../services/settings_service.dart';
import '../../widgets/room/room_host_settings_sheet.dart';
import 'canvas_controller.dart';

/// 캔버스(채팅방) 화면
class CanvasScreen extends StatefulWidget {
  final RoomModel room;
  final Offset? jumpToPosition; // 태그 원본 점프용
  final Rect? highlightTagArea; // 태그 영역 하이라이트 (원본 점프 시)

  const CanvasScreen({
    super.key,
    required this.room,
    this.jumpToPosition,
    this.highlightTagArea,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  late CanvasController _canvasController;
  final TextEditingController _quickTextController = TextEditingController();
  final GlobalKey _canvasRepaintKey = GlobalKey();
  bool _isInitialized = false;
  Rect? _highlightTagArea; // 3초 후 자동 해제
  void _onNetworkChanged() {
    if (!mounted) return;
    final net = context.read<NetworkConnectivityService>();
    if (net.isOnline && _canvasController.hasPendingQueue) {
      _canvasController.retryPendingStrokes();
    }
  }

  Future<void> _applyDefaultPenSettings() async {
    final settings = SettingsService();
    final colorValue = await settings.getDefaultPenColorValue();
    final width = await settings.getDefaultPenWidth();
    if (!mounted) return;
    Color? color;
    if (colorValue != null) color = Color(colorValue);
    _canvasController.applyDefaultPenSettings(
      color: color,
      width: width,
    );
  }

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
        final expandMode = widget.room.canvasExpandMode == 'free'
            ? CanvasExpandMode.free
            : CanvasExpandMode.rectangular;
        String? blockedUserId;
        DateTime? blockedAt;
        if (widget.room.type == RoomType.direct &&
            widget.room.memberIds.length == 2) {
          final otherId = widget.room.memberIds
              .firstWhere((id) => id != userId, orElse: () => '');
          if (otherId.isNotEmpty) {
            final blockedList = context
                .read<FriendProvider>()
                .blockedUsers
                .where((b) => b.friendId == otherId)
                .toList();
            final blocked = blockedList.isNotEmpty ? blockedList.first : null;
            if (blocked != null && blocked.blockedAt != null) {
              blockedUserId = otherId;
              blockedAt = blocked.blockedAt;
            }
          }
        }
        _canvasController.initialize(
          widget.room.id,
          userId,
          userName: userName,
          canvasExpandMode: expandMode,
          blockedUserId: blockedUserId,
          blockedAt: blockedAt,
        );
        _isInitialized = true;
        context.read<NetworkConnectivityService>().addListener(_onNetworkChanged);
        // 저장된 기본 펜 설정 적용
        _applyDefaultPenSettings();

        // 태그 원본 점프
        if (widget.jumpToPosition != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final size = MediaQuery.of(context).size;
            _canvasController.jumpToPosition(widget.jumpToPosition!, size);
          });
        }
        // 태그 영역 하이라이트 (3초 후 해제)
        if (widget.highlightTagArea != null) {
          setState(() => _highlightTagArea = widget.highlightTagArea);
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _highlightTagArea = null);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    try {
      context.read<NetworkConnectivityService>().removeListener(_onNetworkChanged);
    } catch (_) {}
    _canvasController.dispose();
    _quickTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final roomProvider = context.watch<RoomProvider>();
    final network = context.watch<NetworkConnectivityService>();
    final userId = authProvider.user?.uid ?? '';

    // 사진/영상 업로드 시 스낵바 안내
    _canvasController.uploadMessageCallback = (message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    };

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roomProvider.getRoomDisplayName(widget.room, userId),
              style: const TextStyle(fontSize: 16),
            ),
            ListenableBuilder(
              listenable: _canvasController,
              builder: (context, _) {
                final sending = _canvasController.sendingStrokesCount;
                final uploading = _canvasController.isUploading;
                if (sending == 0 && !uploading) return const SizedBox.shrink();
                return Text(
                  sending > 0 && uploading
                      ? '전송 중 ${sending}건 · 업로드 중'
                      : sending > 0
                          ? '전송 중 ${sending}건'
                          : '업로드 중',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedGray,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          // Undo / Redo (문서 스펙: 상단 바)
          ListenableBuilder(
            listenable: _canvasController,
            builder: (_, __) {
              final canUndo = _canvasController.canUndo;
              final canRedo = _canvasController.canRedo;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: canUndo ? () => _canvasController.undo() : null,
                    tooltip: '되돌리기',
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo),
                    onPressed: canRedo ? () => _canvasController.redo() : null,
                    tooltip: '다시 실행',
                  ),
                ],
              );
            },
          ),
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
          // 재연결 중 배너 / 대기열
          if (!network.isOnline || _canvasController.hasPendingQueue)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Material(
                color: !network.isOnline
                    ? Colors.orange.shade700
                    : AppColors.ink.withValues(alpha: 0.9),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          !network.isOnline
                              ? Icons.wifi_off
                              : Icons.schedule,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            !network.isOnline
                                ? '네트워크 연결이 불안정합니다. 재연결 중...'
                                : '대기열 ${_canvasController.pendingQueueCount}건 전송 대기',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (network.isOnline &&
                            _canvasController.hasPendingQueue)
                          TextButton(
                            onPressed: () {
                              _canvasController.retryPendingStrokes();
                            },
                            child: const Text(
                              '재시도',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          Column(
            children: [
              ListenableBuilder(
                listenable: _canvasController,
                builder: (_, __) {
                  final showBanner = !network.isOnline || _canvasController.hasPendingQueue;
                  return SizedBox(height: showBanner ? 52 : 0);
                },
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _canvasController,
                  builder: (context, _) => DrawingCanvas(
                    controller: _canvasController,
                    userId: userId,
                    roomId: widget.room.id,
                    logPublic: widget.room.logPublic,
                    repaintBoundaryKey: _canvasRepaintKey,
                    highlightTagArea: _highlightTagArea,
                  ),
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

          // 확대/축소 비율 조절 (좌측 하단, 빠른 텍스트 시에는 숨김)
          Positioned(
            left: 16,
            bottom: 16,
            child: ListenableBuilder(
              listenable: _canvasController,
              builder: (context, _) {
                if (_canvasController.inputMode == InputMode.quickText) {
                  return const SizedBox.shrink();
                }
                return _buildZoomControl(context);
              },
            ),
          ),

          // 펜 툴바 — 맨 위 레이어로 그리기 (다른 오버레이에 가리지 않도록)
          ListenableBuilder(
            listenable: _canvasController,
            builder: (_, __) {
              final showBanner = !network.isOnline || _canvasController.hasPendingQueue;
              return Positioned(
                left: 0,
                right: 0,
                top: showBanner ? 52 : 0,
                child: PenToolbar(
                  controller: _canvasController,
                  canEditShapes: widget.room.canEditShapes,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 좌측 하단 확대/축소 버튼 (- 100% +)
  Widget _buildZoomControl(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    // 캔버스 뷰포트 중심을 초점으로 사용해야 줌 시 사진이 어긋나지 않음
    final viewportCenter = _canvasController.getZoomFocalPoint(screenSize);

    return ListenableBuilder(
      listenable: _canvasController,
      builder: (context, _) {
        final scalePercent = (_canvasController.canvasScale * 100).round();
        return Material(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(24),
          elevation: 2,
          shadowColor: Colors.black26,
          child: SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      icon: const Icon(Icons.remove, color: AppColors.ink, size: 18),
                      onPressed: _canvasController.canvasScale <= 0.1
                          ? null
                          : () => _canvasController.zoomOut(viewportCenter),
                      tooltip: '축소',
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    height: 28,
                    child: Center(
                      child: Text(
                        '$scalePercent%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      icon: const Icon(Icons.add, color: AppColors.ink, size: 18),
                      onPressed: _canvasController.canvasScale >= 5.0
                          ? null
                          : () => _canvasController.zoomIn(viewportCenter),
                      tooltip: '확대',
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                keyboardType: TextInputType.multiline,
                maxLines: 3,
                style: const TextStyle(color: AppColors.ink, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: '빠른 텍스트 입력... (엔터: 다음 줄)',
                  hintStyle: TextStyle(color: AppColors.mutedGray),
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
                  showRoomHostSettingsSheet(
                    context,
                    widget.room,
                    onCanvasReset: () => _canvasController.clearLocalCanvasState(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('내보내기'),
                onTap: () {
                  Navigator.pop(context);
                  if (!widget.room.exportAllowed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('방장이 내보내기를 제한했습니다.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  _showExportDialog();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: Text(
                  widget.room.type == RoomType.direct ? '채팅방 삭제' : '채팅방 나가기',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showLeaveRoomConfirm(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// 채팅방 나가기 확인 후 실행
  Future<void> _showLeaveRoomConfirm(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    final userId = authProvider.user?.uid;
    if (userId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.room.type == RoomType.direct ? '채팅방 삭제' : '채팅방 나가기',
        ),
        content: Text(
          widget.room.type == RoomType.direct
              ? '이 채팅방을 삭제하시겠습니까?\n대화 내용이 모두 삭제됩니다.'
              : '이 채팅방을 나가시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              widget.room.type == RoomType.direct ? '삭제' : '나가기',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final success = await roomProvider.leaveRoom(widget.room.id, userId);
    if (!context.mounted) return;
    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('채팅방을 나갔습니다.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(roomProvider.errorMessage ?? '나가기 실패'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
    final watermarkForced = widget.room.watermarkForced;
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
                      watermarkForced
                          ? '방장이 워터마크를 필수로 설정했습니다 · ${authProvider.user?.displayName ?? '사용자'} · INK'
                          : '${authProvider.user?.displayName ?? '사용자'} · INK',
                      style: const TextStyle(fontSize: 12, color: AppColors.mutedGray),
                    ),
                    value: includeWatermark,
                    activeColor: AppColors.gold,
                    onChanged: watermarkForced ? null : (value) => setState(() => includeWatermark = value ?? true),
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
                    final useWatermark = widget.room.watermarkForced || includeWatermark;
                    _exportCanvas(selectedFormat, useWatermark);
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

  /// 캔버스 내보내기 실행 (실제 캔버스 캡처)
  void _exportCanvas(ExportFormat format, bool includeWatermark) async {
    final authProvider = context.read<AuthProvider>();
    final exportService = ExportService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      ),
    );

    try {
      final imageData = await exportService.captureCanvas(_canvasRepaintKey);
      if (!mounted) return;
      Navigator.pop(context);

      if (imageData == null || imageData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('캔버스 캡처에 실패했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final fileName = 'ink_${DateTime.now().millisecondsSinceEpoch}';
      final watermarkText = includeWatermark
          ? '${authProvider.user?.displayName ?? '사용자'} · INK'
          : null;

      File? file;
      switch (format) {
        case ExportFormat.png:
          file = await exportService.exportToPng(
            imageData: imageData,
            fileName: fileName,
            watermarkText: watermarkText,
          );
          break;
        case ExportFormat.jpg:
          file = await exportService.exportToJpg(
            imageData: imageData,
            fileName: fileName,
            watermarkText: watermarkText,
          );
          break;
        case ExportFormat.pdf:
          file = await exportService.exportToPdf(
            imageData: imageData,
            fileName: fileName,
            watermarkText: watermarkText,
          );
          break;
      }

      if (mounted && file != null) {
        await exportService.shareFile(file, subject: 'INK 캔버스');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${format.name.toUpperCase()}로 내보내기 완료'),
            backgroundColor: AppColors.gold,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('내보내기 실패'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('내보내기 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
