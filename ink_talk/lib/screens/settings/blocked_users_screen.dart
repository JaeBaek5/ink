import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/friend_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/friend_provider.dart';
import '../../../providers/room_provider.dart';
import '../../../services/stroke_service.dart';
import '../../../services/text_service.dart';

/// 친구 차단 관리 화면
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  String? _unblockingFriendId;

  @override
  void initState() {
    super.initState();
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
        title: const Text('친구 차단 관리'),
      ),
      body: authProvider.user == null
          ? const Center(child: Text('로그인이 필요합니다.'))
          : friendProvider.blockedUsers.isEmpty
              ? Center(child: _buildEmptyContent())
              : RefreshIndicator(
              onRefresh: () async {
                if (authProvider.user != null) {
                  friendProvider.initialize(authProvider.user!.uid);
                }
              },
              child: ListView.builder(
                      itemCount: friendProvider.blockedUsers.length,
                      itemBuilder: (itemContext, index) {
                        final blocked = friendProvider.blockedUsers[index];
                        final user = friendProvider.getFriendUser(blocked.friendId);
                        return _buildBlockedTile(
                          scaffoldContext: context,
                          itemContext: itemContext,
                          blocked: blocked,
                          user: user,
                          friendProvider: friendProvider,
                          userId: authProvider.user!.uid,
                          isUnblocking: _unblockingFriendId == blocked.friendId,
                        );
                      },
                    ),
            ),
    );
  }

  /// 가로·세로 중앙에 빈 상태 문구 표시
  Widget _buildEmptyContent() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.block_outlined,
          size: 64,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          '차단한 사용자가 없습니다',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Future<int> _getBlockedPendingCount(
    BuildContext context,
    String userId,
    FriendModel blocked,
  ) async {
    if (blocked.blockedAt == null) return 0;
    if (!context.mounted) return 0;
    final roomProvider = context.read<RoomProvider>();
    final room = await roomProvider.getDirectRoom(userId, blocked.friendId);
    if (room == null) return 0;
    final strokeCount = await StrokeService().countStrokesFromSenderAfter(
      room.id,
      blocked.friendId,
      blocked.blockedAt!,
    );
    final textCount = await TextService().countTextsFromSenderAfter(
      room.id,
      blocked.friendId,
      blocked.blockedAt!,
    );
    return strokeCount + textCount;
  }

  Widget _buildBlockedTile(
    {required BuildContext scaffoldContext,
    required BuildContext itemContext,
    required FriendModel blocked,
    required UserModel? user,
    required FriendProvider friendProvider,
    required String userId,
    bool isUnblocking = false,
  }) {
    final colorScheme = Theme.of(itemContext).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundImage:
            user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
        backgroundColor: AppColors.mutedGray,
        child: user?.photoUrl == null
            ? const Icon(Icons.person, color: Colors.white)
            : null,
      ),
      title: Text(
        user?.displayName ?? blocked.friendId,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: FutureBuilder<int>(
        future: _getBlockedPendingCount(itemContext, userId, blocked),
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          final lines = <String>[];
          final email = user?.email;
          if (email != null && email.isNotEmpty) {
            lines.add(email);
          }
          if (count > 0) {
            lines.add('차단 기간 중 받은 메시지 ${count}건 (해제 시 채팅에 표시됨)');
          }
          if (lines.isEmpty) return const SizedBox.shrink();
          return Text(
            lines.join(' · '),
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
        },
      ),
      trailing: isUnblocking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: () => _unblock(
                scaffoldContext,
                friendProvider,
                userId,
                blocked.friendId,
                user?.displayName,
              ),
              child: const Text('차단 해제'),
            ),
    );
  }

  Future<void> _unblock(
    BuildContext scaffoldContext,
    FriendProvider friendProvider,
    String userId,
    String friendId,
    String? displayName,
  ) async {
    setState(() => _unblockingFriendId = friendId);
    final ok = await friendProvider.unblockFriend(userId, friendId);
    if (!mounted) return;
    setState(() => _unblockingFriendId = null);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.maybeOf(scaffoldContext)?.showSnackBar(
        SnackBar(content: Text('${displayName ?? "사용자"}님의 차단을 해제했습니다.')),
      );
    } else {
      ScaffoldMessenger.maybeOf(scaffoldContext)?.showSnackBar(
        SnackBar(
          content: Text(friendProvider.errorMessage ?? '차단 해제에 실패했습니다.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
