import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/room_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/room_provider.dart';
import '../../../services/export_service.dart';
import '../../../widgets/chat/puzzle_card.dart';
import '../../canvas/canvas_screen.dart';
import '../../chat/create_chat_screen.dart';

/// 채팅 탭
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  /// true: 목록형, false: 2열 정사각형 박스형(마지막 손글씨 보기)
  bool _isListView = true;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final roomProvider = context.watch<RoomProvider>();
    final userId = authProvider.user?.uid ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          roomProvider.roomCount > 0
              ? '채팅 ${roomProvider.roomCount}'
              : '채팅',
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isListView ? Icons.grid_view : Icons.view_list,
              color: colorScheme.onSurface,
            ),
            tooltip: _isListView ? '박스형 보기' : '목록형 보기',
            onPressed: () => setState(() => _isListView = !_isListView),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            color: AppColors.gold,
            onPressed: () => _showNewChatSheet(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (authProvider.user != null) {
            await roomProvider.initialize(authProvider.user!.uid);
          }
        },
        child: _buildScrollableBody(roomProvider, userId),
      ),
    );
  }

  /// RefreshIndicator는 스크롤 가능한 자식이 필요함. 빈 목록일 때도 스크롤 가능하게.
  Widget _buildScrollableBody(RoomProvider roomProvider, String userId) {
    final displayRooms = roomProvider.rooms
        .where((r) => r.name != '테스트용 채팅방')
        .toList();
    if (displayRooms.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height - 150,
          child: _buildEmptyChatList(),
        ),
      );
    }
    if (_isListView) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: displayRooms.length,
        itemBuilder: (context, index) {
          final room = displayRooms[index];
          return PuzzleCard(
            room: room,
            displayName: roomProvider.getRoomDisplayName(room, userId),
            displayImage: roomProvider.getRoomDisplayImage(room, userId),
            currentUserId: userId,
            onTap: () => _openRoom(room),
            onLongPress: () => _showRoomOptionsSheet(context, room, userId),
          );
        },
      );
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: displayRooms.length,
      itemBuilder: (context, index) {
        final room = displayRooms[index];
        return _buildChatGridTile(
          context,
          room,
          roomProvider.getRoomDisplayName(room, userId),
          roomProvider.getRoomDisplayImage(room, userId),
          userId,
          () => _openRoom(room),
          () => _showRoomOptionsSheet(context, room, userId),
        );
      },
    );
  }

  /// 2열 박스형: 위쪽 채팅방 이름·프로필, 아래쪽 마지막 손글씨 영역(여백·중앙 정렬)
  Widget _buildChatGridTile(
    BuildContext context,
    RoomModel room,
    String displayName,
    String? displayImage,
    String currentUserId,
    VoidCallback onTap,
    VoidCallback onLongPress,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final unreadCount = room.members[currentUserId]?.unreadCount ?? 0;
    final lastType = room.lastEventType;
    final lastUrl = room.lastEventUrl;
    final lastPreview = room.lastEventPreview;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 위쪽: 채팅방 이름 + 프로필 사진
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        displayImage != null ? NetworkImage(displayImage) : null,
                    backgroundColor: room.type == RoomType.group
                        ? AppColors.gold
                        : colorScheme.surfaceContainerHighest,
                    child: displayImage == null
                        ? Icon(
                            room.type == RoomType.group
                                ? Icons.group
                                : Icons.person,
                            color: room.type == RoomType.group
                                ? Colors.white
                                : colorScheme.onSurfaceVariant,
                            size: 18,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // 아래쪽: 마지막 손글씨 영역 (좌우·위아래 여백, 중앙 정렬)
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Center(
                    child: _buildLastEventPreview(
                      context,
                      eventType: lastType,
                      previewUrl: lastUrl,
                      previewText: lastPreview,
                      colorScheme: colorScheme,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 마지막 기록 1개 미리보기: 손글씨·사진·영상·PDF·텍스트
  Widget _buildLastEventPreview(
    BuildContext context, {
    required String? eventType,
    required String? previewUrl,
    required String? previewText,
    required ColorScheme colorScheme,
  }) {
    // 사진: URL 있으면 이미지 표시
    if (eventType == 'image' && previewUrl != null && previewUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          previewUrl,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _placeholderIcon(
            colorScheme,
            Icons.image_outlined,
            '사진',
          ),
        ),
      );
    }
    // 영상: 썸네일 URL 있으면 표시, 없으면 아이콘
    if (eventType == 'video') {
      if (previewUrl != null && previewUrl.isNotEmpty) {
        return Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                previewUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => _placeholderIcon(
                  colorScheme,
                  Icons.videocam_outlined,
                  '영상',
                ),
              ),
            ),
            Icon(Icons.play_circle_fill, color: Colors.white70, size: 28),
          ],
        );
      }
      return _placeholderIcon(colorScheme, Icons.videocam_outlined, '영상');
    }
    // PDF
    if (eventType == 'pdf') {
      if (previewUrl != null && previewUrl.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            previewUrl,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) =>
                _placeholderIcon(colorScheme, Icons.picture_as_pdf_outlined, 'PDF'),
          ),
        );
      }
      return _placeholderIcon(
          colorScheme, Icons.picture_as_pdf_outlined, 'PDF');
    }
    // 손글씨
    if (eventType == 'stroke') {
      return _placeholderIcon(colorScheme, Icons.gesture, '손글씨');
    }
    // 텍스트 / 기타 / 빈 채팅방
    return Text(
      previewText ?? '새 채팅방',
      style: TextStyle(
        fontSize: 11,
        color: colorScheme.onSurfaceVariant,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }

  Widget _placeholderIcon(
      ColorScheme colorScheme, IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 32, color: AppColors.gold),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyChatList() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '채팅이 없습니다',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '우측 상단의 + 버튼을 눌러\n새 채팅을 시작해보세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRoom(RoomModel room) async {
    final roomProvider = context.read<RoomProvider>();
    final authProvider = context.read<AuthProvider>();

    // 서버에서 방 존재 확인 (캐시만 있던 삭제된 방이면 진입 방지)
    final existing = await roomProvider.getRoomFromServer(room.id);
    if (existing == null || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방이 더 이상 존재하지 않습니다.')),
        );
      }
      return;
    }

    roomProvider.selectRoom(existing);
    if (authProvider.user != null) {
      roomProvider.markAsRead(existing.id, authProvider.user!.uid);
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CanvasScreen(room: existing),
      ),
    );
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('채팅 검색'),
          content: TextField(
            decoration: const InputDecoration(
              hintText: '채팅방 이름 검색',
              prefixIcon: Icon(Icons.search),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  void _showNewChatSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
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
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.person, color: colorScheme.onSurface),
                title: const Text('1:1 채팅'),
                subtitle: const Text('친구와 대화하기'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToCreateChat(isGroup: false);
                },
              ),
              ListTile(
                leading: Icon(Icons.group, color: colorScheme.onSurface),
                title: const Text('그룹 채팅'),
                subtitle: const Text('여러 명과 대화하기'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToCreateChat(isGroup: true);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _navigateToCreateChat({required bool isGroup}) async {
    final result = await Navigator.push<RoomModel>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateChatScreen(isGroupChat: isGroup),
      ),
    );

    if (result != null && mounted) {
      _openRoom(result);
    }
  }

  void _showRoomOptionsSheet(BuildContext context, RoomModel room, String userId) {
    final roomProvider = context.read<RoomProvider>();
    final myRole = room.members[userId]?.role;
    final scaffoldContext = context;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
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
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.chat_bubble_outline, color: colorScheme.onSurface),
                title: const Text('채팅방 열기'),
                onTap: () {
                  Navigator.pop(context);
                  _openRoom(room);
                },
              ),
              ListTile(
                leading: Icon(Icons.notifications_outlined, color: colorScheme.onSurface),
                title: const Text('알림 설정'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 알림 설정
                },
              ),
              if (room.type == RoomType.group) ...[
                ListTile(
                  leading: Icon(Icons.link, color: colorScheme.onSurface),
                  title: const Text('초대 링크 생성'),
                  onTap: () async {
                    Navigator.pop(context);
                    final authProvider = context.read<AuthProvider>();
                    final link = await ExportService().createShareLink(
                      roomId: room.id,
                      userId: authProvider.user?.uid ?? '',
                    );
                    if (link != null && context.mounted) {
                      await ExportService().shareLink(
                        link,
                        message: '${room.name ?? 'INK 채팅방'}에 초대합니다!\n$link',
                      );
                    }
                  },
                ),
                if (myRole == MemberRole.owner || myRole == MemberRole.admin)
                  ListTile(
                    leading: Icon(Icons.person_add_outlined, color: colorScheme.onSurface),
                    title: const Text('멤버 초대'),
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: 멤버 초대
                    },
                  ),
                if (myRole == MemberRole.owner)
                  ListTile(
                    leading: Icon(Icons.settings_outlined, color: colorScheme.onSurface),
                    title: const Text('채팅방 설정'),
                    onTap: () {
                      Navigator.pop(context);
                      _showRoomSettingsSheet(context, room);
                    },
                  ),
              ],

              const Divider(),

              // 나가기
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: Text(
                  room.type == RoomType.direct ? '채팅방 삭제' : '채팅방 나가기',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await _showConfirmDialog(
                    scaffoldContext,
                    room.type == RoomType.direct ? '채팅방 삭제' : '채팅방 나가기',
                    room.type == RoomType.direct
                        ? '이 채팅방을 삭제하시겠습니까?\n대화 내용이 모두 삭제됩니다.'
                        : '이 채팅방을 나가시겠습니까?',
                  );
                  if (confirm && scaffoldContext.mounted) {
                    final success = await roomProvider.leaveRoom(room.id, userId);
                    if (scaffoldContext.mounted) {
                      if (success) {
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          const SnackBar(content: Text('채팅방을 나갔습니다.')),
                        );
                      } else {
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          SnackBar(
                            content: Text(roomProvider.errorMessage ?? '나가기 실패'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showRoomSettingsSheet(BuildContext context, RoomModel room) {
    final nameController = TextEditingController(text: room.name);
    final authProvider = context.read<AuthProvider>();
    final myUserId = authProvider.user?.uid ?? '';
    final myRole = room.members[myUserId]?.role;
    final isHost = myRole == MemberRole.owner || myRole == MemberRole.admin;
    final colorScheme = Theme.of(context).colorScheme;

    bool exportAllowed = room.exportAllowed;
    bool watermarkForced = room.watermarkForced;
    bool logPublic = room.logPublic;
    bool canEditShapes = room.canEditShapes;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
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
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '채팅방 설정',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: '채팅방 이름',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 역할 관리
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings_outlined),
                        title: const Text('멤버 역할 관리'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(context);
                          _showMemberRolesSheet(context, room);
                        },
                      ),

                      // 방장 설정 (owner, admin만)
                      if (isHost) ...[
                        const Divider(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.settings_outlined, size: 20, color: AppColors.gold),
                              const SizedBox(width: 8),
                              const Text(
                                '방장 설정',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('내보내기 허용'),
                          subtitle: const Text('멤버가 캔버스를 이미지/PDF로 내보낼 수 있음'),
                          value: exportAllowed,
                          activeColor: AppColors.gold,
                          onChanged: (v) => setModalState(() => exportAllowed = v),
                        ),
                        SwitchListTile(
                          title: const Text('워터마크 강제'),
                          subtitle: const Text('내보내기 시 워터마크를 반드시 포함'),
                          value: watermarkForced,
                          activeColor: AppColors.gold,
                          onChanged: (v) => setModalState(() => watermarkForced = v),
                        ),
                        SwitchListTile(
                          title: const Text('로그 공개'),
                          subtitle: const Text('시간순 로그(타임라인)를 멤버에게 공개'),
                          value: logPublic,
                          activeColor: AppColors.gold,
                          onChanged: (v) => setModalState(() => logPublic = v),
                        ),
                        SwitchListTile(
                          title: const Text('도형 수정 허용'),
                          subtitle: const Text('멤버가 도형을 추가·수정·삭제할 수 있음'),
                          value: canEditShapes,
                          activeColor: AppColors.gold,
                          onChanged: (v) => setModalState(() => canEditShapes = v),
                        ),
                      ],

                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              final roomProvider = context.read<RoomProvider>();
                              await roomProvider.updateRoom(
                                room.id,
                                name: nameController.text.trim(),
                                exportAllowed: isHost ? exportAllowed : null,
                                watermarkForced: isHost ? watermarkForced : null,
                                logPublic: isHost ? logPublic : null,
                                canEditShapes: isHost ? canEditShapes : null,
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: const Text('저장'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMemberRolesSheet(BuildContext context, RoomModel room) {
    final roomProvider = context.read<RoomProvider>();
    final authProvider = context.read<AuthProvider>();
    final myUserId = authProvider.user?.uid ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
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
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '멤버 역할 관리',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              ...room.members.entries.map((entry) {
                final memberId = entry.key;
                final member = entry.value;
                final memberUser = roomProvider.getMemberUser(memberId);
                final isMe = memberId == myUserId;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: memberUser?.photoUrl != null
                        ? NetworkImage(memberUser!.photoUrl!)
                        : null,
                    child: memberUser?.photoUrl == null
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  title: Text(
                    memberUser?.displayName ?? '알 수 없음',
                    style: TextStyle(
                      fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(_getRoleName(member.role)),
                  trailing: isMe
                      ? const Text('나', style: TextStyle(color: AppColors.gold))
                      : PopupMenuButton<MemberRole>(
                          onSelected: (newRole) async {
                            await roomProvider.updateMemberRole(
                              room.id,
                              memberId,
                              newRole,
                            );
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: MemberRole.admin,
                              child: Text('관리자'),
                            ),
                            const PopupMenuItem(
                              value: MemberRole.member,
                              child: Text('멤버'),
                            ),
                            const PopupMenuItem(
                              value: MemberRole.viewer,
                              child: Text('보기 전용'),
                            ),
                          ],
                        ),
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _getRoleName(MemberRole role) {
    switch (role) {
      case MemberRole.owner:
        return '방장';
      case MemberRole.admin:
        return '관리자';
      case MemberRole.member:
        return '멤버';
      case MemberRole.viewer:
        return '보기 전용';
    }
  }

  Future<bool> _showConfirmDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(title, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
