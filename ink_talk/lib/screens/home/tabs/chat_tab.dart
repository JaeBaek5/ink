import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/room_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/room_provider.dart';
import '../../../widgets/chat/puzzle_card.dart';
import '../../chat/create_chat_screen.dart';

/// 채팅 탭
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.user != null) {
        context.read<RoomProvider>().initialize(authProvider.user!.uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final roomProvider = context.watch<RoomProvider>();
    final userId = authProvider.user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('채팅 ${roomProvider.roomCount > 0 ? "(${roomProvider.roomCount})" : ""}'),
        actions: [
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
            roomProvider.initialize(authProvider.user!.uid);
          }
        },
        child: roomProvider.rooms.isEmpty
            ? _buildEmptyChatList()
            : _buildChatList(roomProvider, userId),
      ),
    );
  }

  Widget _buildEmptyChatList() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppColors.mutedGray,
          ),
          SizedBox(height: 16),
          Text(
            '채팅이 없습니다',
            style: TextStyle(
              color: AppColors.mutedGray,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '우측 상단의 + 버튼을 눌러\n새 채팅을 시작해보세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.mutedGray,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(RoomProvider roomProvider, String userId) {
    return ListView.builder(
      itemCount: roomProvider.rooms.length,
      itemBuilder: (context, index) {
        final room = roomProvider.rooms[index];
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

  void _openRoom(RoomModel room) {
    final roomProvider = context.read<RoomProvider>();
    roomProvider.selectRoom(room);
    
    // TODO: 채팅방 화면으로 이동
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${room.name ?? "채팅방"} 열기 (준비 중)')),
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
                leading: const Icon(Icons.person, color: AppColors.ink),
                title: const Text('1:1 채팅'),
                subtitle: const Text('친구와 대화하기'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToCreateChat(isGroup: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.group, color: AppColors.ink),
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

              // 채팅방 열기
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: AppColors.ink),
                title: const Text('채팅방 열기'),
                onTap: () {
                  Navigator.pop(context);
                  _openRoom(room);
                },
              ),

              // 알림 설정
              ListTile(
                leading: const Icon(Icons.notifications_outlined, color: AppColors.ink),
                title: const Text('알림 설정'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 알림 설정
                },
              ),

              // 그룹 채팅 전용 옵션
              if (room.type == RoomType.group) ...[
                // 멤버 초대 (Admin 이상)
                if (myRole == MemberRole.owner || myRole == MemberRole.admin)
                  ListTile(
                    leading: const Icon(Icons.person_add_outlined, color: AppColors.ink),
                    title: const Text('멤버 초대'),
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: 멤버 초대
                    },
                  ),

                // 채팅방 설정 (Owner만)
                if (myRole == MemberRole.owner)
                  ListTile(
                    leading: const Icon(Icons.settings_outlined, color: AppColors.ink),
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
                    context,
                    room.type == RoomType.direct ? '채팅방 삭제' : '채팅방 나가기',
                    room.type == RoomType.direct
                        ? '이 채팅방을 삭제하시겠습니까?\n대화 내용이 모두 삭제됩니다.'
                        : '이 채팅방을 나가시겠습니까?',
                  );
                  if (confirm && context.mounted) {
                    await roomProvider.leaveRoom(room.id, userId);
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

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
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
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.paper,
                      ),
                      child: const Text('저장'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMemberRolesSheet(BuildContext context, RoomModel room) {
    final roomProvider = context.read<RoomProvider>();
    final authProvider = context.read<AuthProvider>();
    final myUserId = authProvider.user?.uid ?? '';

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
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '멤버 역할 관리',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
