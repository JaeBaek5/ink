import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/room_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/canvas/drawing_canvas.dart';
import '../../widgets/canvas/pen_toolbar.dart';
import 'canvas_controller.dart';

/// 캔버스(채팅방) 화면
class CanvasScreen extends StatefulWidget {
  final RoomModel room;

  const CanvasScreen({
    super.key,
    required this.room,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  late CanvasController _canvasController;

  @override
  void initState() {
    super.initState();
    _canvasController = CanvasController();
  }

  @override
  void dispose() {
    _canvasController.dispose();
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
      body: Column(
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
    );
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
                  // TODO: 내보내기
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
