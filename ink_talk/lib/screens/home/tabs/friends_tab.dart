import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/friend_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/friend_provider.dart';

/// 친구 탭
class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  @override
  void initState() {
    super.initState();
    // 친구 목록 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.user != null) {
        context.read<FriendProvider>().initialize(authProvider.user!.uid);
      }
    });
  }

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
            friendProvider.initialize(authProvider.user!.uid);
          }
        },
        child: ListView(
          children: [
            // 내 프로필 섹션
            _buildMyProfileSection(context, authProvider),

            const Divider(),

            // 받은 친구 요청
            if (friendProvider.pendingCount > 0) ...[
              _buildPendingRequestsSection(friendProvider),
              const Divider(),
            ],

            // 친구 목록
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
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.ink,
        ),
      ),
      subtitle: const Text(
        '상태 메시지를 입력하세요',
        style: TextStyle(color: AppColors.mutedGray),
      ),
      onTap: () {
        // TODO: 프로필 편집
      },
    );
  }

  Widget _buildPendingRequestsSection(FriendProvider friendProvider) {
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
        ...friendProvider.pendingRequests.map((request) {
          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.gold,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text(request.userId),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () {
                    // TODO: 수락
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () {
                    // TODO: 거절
                  },
                ),
              ],
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
    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            friendUser?.photoUrl != null ? NetworkImage(friendUser!.photoUrl!) : null,
        backgroundColor: AppColors.mutedGray,
        child: friendUser?.photoUrl == null
            ? const Icon(Icons.person, color: Colors.white)
            : null,
      ),
      title: Text(
        friend.nickname ?? friendUser?.displayName ?? '알 수 없음',
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
      ),
      subtitle: friendUser?.statusMessage != null
          ? Text(
              friendUser!.statusMessage!,
              style: const TextStyle(color: AppColors.mutedGray),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: () {
        // TODO: 친구 프로필 보기 / 채팅 시작
      },
      onLongPress: () => _showFriendOptionsSheet(context, friend, friendUser),
    );
  }

  /// 친구 추가 바텀 시트
  void _showAddFriendSheet(BuildContext context) {
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
                leading: const Icon(Icons.alternate_email, color: AppColors.ink),
                title: const Text('ID로 추가'),
                subtitle: const Text('친구의 INK ID를 입력하세요'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddByIdDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.phone, color: AppColors.ink),
                title: const Text('전화번호로 추가'),
                subtitle: const Text('친구의 전화번호를 입력하세요'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddByPhoneDialog(context);
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
                                const SnackBar(content: Text('친구가 추가되었습니다!')),
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
                                const SnackBar(content: Text('친구가 추가되었습니다!')),
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
                leading: const Icon(Icons.chat_bubble_outline, color: AppColors.ink),
                title: const Text('채팅하기'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 채팅 시작
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.ink),
                title: const Text('별명 설정'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 별명 설정
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.orange),
                title: const Text('친구 삭제', style: TextStyle(color: Colors.orange)),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await _showConfirmDialog(
                    context,
                    '친구 삭제',
                    '${friendUser?.displayName ?? "이 친구"}님을 친구 목록에서 삭제하시겠습니까?',
                  );
                  if (confirm && context.mounted) {
                    await friendProvider.removeFriend(
                      authProvider.user!.uid,
                      friend.friendId,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('차단', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await _showConfirmDialog(
                    context,
                    '친구 차단',
                    '${friendUser?.displayName ?? "이 친구"}님을 차단하시겠습니까?\n차단하면 메시지를 주고받을 수 없습니다.',
                  );
                  if (confirm && context.mounted) {
                    await friendProvider.blockFriend(
                      authProvider.user!.uid,
                      friend.friendId,
                    );
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
