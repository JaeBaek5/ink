import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/friend_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/friend_provider.dart';
import '../../../providers/room_provider.dart';
import '../../canvas/canvas_screen.dart';
import '../../friends/contact_sync_screen.dart';

/// 친구 탭
class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final friendProvider = context.watch<FriendProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('친구 ${friendProvider.friendCount > 0 ? "(${friendProvider.friendCount})" : ""}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            color: AppColors.gold,
            onPressed: () => _showAddFriendSheet(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (authProvider.user != null) {
            await friendProvider.initialize(authProvider.user!.uid);
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // 내 프로필 섹션
            _buildMyProfileSection(context, authProvider),

            const Divider(),

            // 1. 보낸 친구 요청 (내용 있을 때만)
            if (friendProvider.sentCount > 0) ...[
              _buildSentRequestsSection(friendProvider),
              const Divider(),
            ],

            // 2. 받은 친구 요청 (내용 있을 때만)
            if (friendProvider.pendingCount > 0) ...[
              _buildPendingRequestsSection(friendProvider),
              const Divider(),
            ],

            // 3. 친구 목록
            if (friendProvider.friends.isEmpty)
              _buildEmptyFriendsList()
            else
              _buildFriendsList(friendProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildMyProfileSection(BuildContext context, AuthProvider authProvider) {
    final user = authProvider.user;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
        backgroundColor: AppColors.gold,
        child: user?.photoURL == null
            ? const Icon(Icons.person, color: Colors.white, size: 28)
            : null,
      ),
      title: Text(
        user?.displayName ?? '내 프로필',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        '상태 메시지를 입력하세요',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      onTap: () {
        // TODO: 프로필 편집
      },
    );
  }

  Widget _buildPendingRequestsSection(FriendProvider friendProvider) {
    final pending = friendProvider.pendingRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            '받은 친구 요청 (${friendProvider.pendingCount})',
            style: const TextStyle(
              color: AppColors.mutedGray,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              '받은 요청이 없습니다',
              style: TextStyle(color: AppColors.mutedGray, fontSize: 14),
            ),
          )
        else
          ...pending.map((request) {
            final requesterUser = friendProvider.getFriendUser(request.userId);
            return ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    requesterUser?.photoUrl != null ? NetworkImage(requesterUser!.photoUrl!) : null,
                backgroundColor: AppColors.gold,
                child: requesterUser?.photoUrl == null
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              title: Text(
                requesterUser?.displayName ?? request.userId,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: friendProvider.isLoading
                        ? null
                        : () async {
                            final authProvider = context.read<AuthProvider>();
                            if (authProvider.user == null) return;
                            final success = await friendProvider.acceptFriendRequest(
                              authProvider.user!.uid,
                              request.id,
                            );
                            if (context.mounted) {
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('친구가 추가되었습니다.')),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(friendProvider.errorMessage ?? '오류가 발생했습니다.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: friendProvider.isLoading
                        ? null
                        : () async {
                            final authProvider = context.read<AuthProvider>();
                            if (authProvider.user == null) return;
                            await friendProvider.rejectFriendRequest(
                              authProvider.user!.uid,
                              request.id,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('친구 요청을 거절했습니다.')),
                              );
                            }
                          },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSentRequestsSection(FriendProvider friendProvider) {
    final sent = friendProvider.sentRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            '보낸 친구 요청 (${friendProvider.sentCount})',
            style: const TextStyle(
              color: AppColors.mutedGray,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (sent.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              '보낸 요청이 없습니다',
              style: TextStyle(color: AppColors.mutedGray, fontSize: 14),
            ),
          )
        else
          ...sent.map((s) {
            final targetUser = friendProvider.getFriendUser(s.friendId);
            final isRejected = s.status == FriendStatus.rejected;
            return ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    targetUser?.photoUrl != null ? NetworkImage(targetUser!.photoUrl!) : null,
                backgroundColor: AppColors.mutedGray,
                child: targetUser?.photoUrl == null
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              title: Text(
                targetUser?.displayName ?? s.friendId,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                isRejected ? '거절됨' : '대기중',
                style: TextStyle(
                  fontSize: 12,
                  color: isRejected ? Colors.red : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEmptyFriendsList() {
    return const Padding(
      padding: EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: AppColors.mutedGray,
          ),
          SizedBox(height: 16),
          Text(
            '아직 친구가 없습니다',
            style: TextStyle(
              color: AppColors.mutedGray,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '우측 상단의 + 버튼을 눌러\n친구를 추가해보세요',
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

  Widget _buildFriendsList(FriendProvider friendProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            '친구 (${friendProvider.friendCount})',
            style: const TextStyle(
              color: AppColors.mutedGray,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...friendProvider.friends.map((friend) {
          final friendUser = friendProvider.getFriendUser(friend.friendId);
          return _buildFriendTile(friend, friendUser);
        }),
      ],
    );
  }

  Widget _buildFriendTile(FriendModel friend, UserModel? friendUser) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = friend.nickname ?? friendUser?.displayName ?? '알 수 없음';
    final statusMessage = friendUser?.statusMessage;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            friendUser?.photoUrl != null ? NetworkImage(friendUser!.photoUrl!) : null,
        backgroundColor: AppColors.mutedGray,
        child: friendUser?.photoUrl == null
            ? const Icon(Icons.person, color: Colors.white)
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (statusMessage != null && statusMessage.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                statusMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ],
      ),
      onLongPress: () => _showFriendOptionsSheet(context, friend, friendUser),
    );
  }

  /// 친구 추가 바텀 시트
  void _showAddFriendSheet(BuildContext context) {
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
                leading: Icon(Icons.alternate_email, color: colorScheme.onSurface),
                title: const Text('ID로 추가'),
                subtitle: const Text('친구의 INK ID를 입력하세요'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddByIdDialog(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.phone, color: colorScheme.onSurface),
                title: const Text('전화번호로 추가'),
                subtitle: const Text('친구의 전화번호를 입력하세요'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddByPhoneDialog(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.contacts, color: AppColors.gold),
                title: const Text('연락처에서 찾기'),
                subtitle: const Text('연락처에서 INK 사용자를 찾습니다'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ContactSyncScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// ID로 친구 추가 다이얼로그
  void _showAddByIdDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ID로 친구 추가'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'ink_xxxxxxxx',
              prefixIcon: Icon(Icons.alternate_email),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            Consumer2<AuthProvider, FriendProvider>(
              builder: (context, authProvider, friendProvider, _) {
                return TextButton(
                  onPressed: friendProvider.isLoading
                      ? null
                      : () async {
                          if (controller.text.trim().isEmpty) return;

                          final success = await friendProvider.addFriendById(
                            authProvider.user!.uid,
                            controller.text.trim(),
                          );

                          if (context.mounted) {
                            if (success) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('친구 요청을 보냈습니다.')),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(friendProvider.errorMessage ?? '오류가 발생했습니다.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: friendProvider.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('추가'),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// 전화번호로 친구 추가 다이얼로그
  void _showAddByPhoneDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('전화번호로 친구 추가'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '010-1234-5678',
              prefixIcon: Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            Consumer2<AuthProvider, FriendProvider>(
              builder: (context, authProvider, friendProvider, _) {
                return TextButton(
                  onPressed: friendProvider.isLoading
                      ? null
                      : () async {
                          if (controller.text.trim().isEmpty) return;

                          final success = await friendProvider.addFriendByPhone(
                            authProvider.user!.uid,
                            controller.text.trim(),
                          );

                          if (context.mounted) {
                            if (success) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('친구 요청을 보냈습니다.')),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(friendProvider.errorMessage ?? '오류가 발생했습니다.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: friendProvider.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('추가'),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// 친구 검색 다이얼로그
  void _showSearchDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('친구 검색'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '이름 또는 ID 검색',
              prefixIcon: Icon(Icons.search),
            ),
            autofocus: true,
            onChanged: (value) {
              // TODO: 실시간 검색
            },
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

  /// 친구 옵션 바텀 시트
  void _showFriendOptionsSheet(BuildContext context, FriendModel friend, UserModel? friendUser) {
    final authProvider = context.read<AuthProvider>();
    final friendProvider = context.read<FriendProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final scaffoldContext = context; // 시트 닫힌 후에도 유효한 context

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
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
                title: const Text('채팅하기'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openChatWithFriend(scaffoldContext, friend);
                },
              ),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: colorScheme.onSurface),
                title: const Text('별명 설정'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showNicknameDialog(scaffoldContext, friend, friendUser);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.orange),
                title: const Text('친구 삭제', style: TextStyle(color: Colors.orange)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirm = await _showConfirmDialog(
                    scaffoldContext,
                    '친구 삭제',
                    '${friendUser?.displayName ?? "이 친구"}님을 친구 목록에서 삭제하시겠습니까?',
                  );
                  if (confirm && scaffoldContext.mounted) {
                    final ok = await friendProvider.removeFriend(
                      authProvider.user!.uid,
                      friend.friendId,
                    );
                    if (scaffoldContext.mounted) {
                      if (ok) {
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          const SnackBar(content: Text('친구 목록에서 삭제했습니다.')),
                        );
                      } else {
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          SnackBar(
                            content: Text(friendProvider.errorMessage ?? '삭제에 실패했습니다.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('차단', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirm = await _showConfirmDialog(
                    scaffoldContext,
                    '친구 차단',
                    '${friendUser?.displayName ?? "이 친구"}님을 차단하시겠습니까?\n친구 목록에서 차단 관리로 이동하며, 이후 알림만 받지 않습니다.',
                  );
                  if (confirm && scaffoldContext.mounted) {
                    final ok = await friendProvider.blockFriend(
                      authProvider.user!.uid,
                      friend.friendId,
                    );
                    if (scaffoldContext.mounted) {
                      if (ok) {
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          const SnackBar(content: Text('차단했습니다. 설정 > 친구 차단 관리에서 확인할 수 있습니다.')),
                        );
                      } else {
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          SnackBar(
                            content: Text(friendProvider.errorMessage ?? '차단에 실패했습니다.'),
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

  /// 친구와 1:1 채팅 열기
  Future<void> _openChatWithFriend(BuildContext context, FriendModel friend) async {
    final authProvider = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    final userId = authProvider.user?.uid;
    if (userId == null) return;

    final room = await roomProvider.createDirectRoom(userId, friend.friendId);
    if (room == null || !context.mounted) return;

    roomProvider.selectRoom(room);
    if (authProvider.user != null) {
      roomProvider.markAsRead(room.id, authProvider.user!.uid);
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CanvasScreen(room: room),
      ),
    );
  }

  /// 별명 설정 다이얼로그
  void _showNicknameDialog(BuildContext context, FriendModel friend, UserModel? friendUser) {
    final controller = TextEditingController(text: friend.nickname ?? friendUser?.displayName ?? '');
    final friendProvider = context.read<FriendProvider>();
    final authProvider = context.read<AuthProvider>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('별명 설정'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '표시할 이름을 입력하세요',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                final nickname = controller.text.trim();
                final ok = await friendProvider.updateFriendNickname(
                  authProvider.user!.uid,
                  friend.friendId,
                  nickname.isEmpty ? null : nickname,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('별명이 저장되었습니다.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(friendProvider.errorMessage ?? '저장에 실패했습니다.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
  }

  /// 확인 다이얼로그
  Future<bool> _showConfirmDialog(BuildContext context, String title, String message) async {
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
