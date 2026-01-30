import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/friend_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/room_provider.dart';

/// 채팅 생성 화면 (친구 선택)
class CreateChatScreen extends StatefulWidget {
  final bool isGroupChat;

  const CreateChatScreen({
    super.key,
    this.isGroupChat = false,
  });

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final Set<String> _selectedFriendIds = {};
  final TextEditingController _groupNameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friendProvider = context.watch<FriendProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isGroupChat ? '그룹 채팅 만들기' : '대화 상대 선택'),
        actions: [
          if (widget.isGroupChat && _selectedFriendIds.isNotEmpty)
            TextButton(
              onPressed: _isCreating ? null : _createGroupChat,
              child: _isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('만들기'),
            ),
        ],
      ),
      body: Column(
        children: [
          // 그룹 이름 입력 (그룹 채팅만)
          if (widget.isGroupChat && _selectedFriendIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: TextField(
                controller: _groupNameController,
                decoration: InputDecoration(
                  hintText: '그룹 이름 입력',
                  prefixIcon: const Icon(Icons.group),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

          // 선택된 친구 (그룹 채팅만)
          if (widget.isGroupChat && _selectedFriendIds.isNotEmpty)
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedFriendIds.length,
                itemBuilder: (context, index) {
                  final friendId = _selectedFriendIds.elementAt(index);
                  final friendUser = friendProvider.getFriendUser(friendId);
                  return _buildSelectedFriendChip(friendId, friendUser);
                },
              ),
            ),

          // 친구 목록
          Expanded(
            child: friendProvider.friends.isEmpty
                ? _buildEmptyFriends()
                : ListView.builder(
                    itemCount: friendProvider.friends.length,
                    itemBuilder: (context, index) {
                      final friend = friendProvider.friends[index];
                      final friendUser =
                          friendProvider.getFriendUser(friend.friendId);
                      return _buildFriendTile(friend, friendUser);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFriends() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppColors.mutedGray),
          SizedBox(height: 16),
          Text(
            '친구가 없습니다',
            style: TextStyle(color: AppColors.mutedGray, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            '먼저 친구를 추가해주세요',
            style: TextStyle(color: AppColors.mutedGray, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendTile(FriendModel friend, UserModel? friendUser) {
    final isSelected = _selectedFriendIds.contains(friend.friendId);

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: friendUser?.photoUrl != null
            ? NetworkImage(friendUser!.photoUrl!)
            : null,
        backgroundColor: AppColors.mutedGray,
        child: friendUser?.photoUrl == null
            ? const Icon(Icons.person, color: Colors.white)
            : null,
      ),
      title: Text(
        friend.nickname ?? friendUser?.displayName ?? '알 수 없음',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: friendUser?.statusMessage != null
          ? Text(
              friendUser!.statusMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: widget.isGroupChat
          ? Checkbox(
              value: isSelected,
              onChanged: (value) => _toggleSelection(friend.friendId),
              activeColor: AppColors.gold,
            )
          : const Icon(Icons.chevron_right, color: AppColors.mutedGray),
      onTap: () {
        if (widget.isGroupChat) {
          _toggleSelection(friend.friendId);
        } else {
          _createDirectChat(friend.friendId);
        }
      },
    );
  }

  Widget _buildSelectedFriendChip(String friendId, UserModel? friendUser) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: friendUser?.photoUrl != null
                    ? NetworkImage(friendUser!.photoUrl!)
                    : null,
                backgroundColor: AppColors.mutedGray,
                child: friendUser?.photoUrl == null
                    ? const Icon(Icons.person, color: Colors.white, size: 20)
                    : null,
              ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () => _toggleSelection(friendId),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.ink,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            friendUser?.displayName ?? '',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String friendId) {
    setState(() {
      if (_selectedFriendIds.contains(friendId)) {
        _selectedFriendIds.remove(friendId);
      } else {
        _selectedFriendIds.add(friendId);
      }
    });
  }

  Future<void> _createDirectChat(String friendId) async {
    setState(() => _isCreating = true);

    final authProvider = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    final userId = authProvider.user?.uid;

    if (userId == null) return;

    final room = await roomProvider.createDirectRoom(userId, friendId);

    setState(() => _isCreating = false);

    if (room != null && mounted) {
      Navigator.pop(context, room);
    }
  }

  Future<void> _createGroupChat() async {
    if (_selectedFriendIds.isEmpty) return;

    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('그룹 이름을 입력하세요')),
      );
      return;
    }

    setState(() => _isCreating = true);

    final authProvider = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    final userId = authProvider.user?.uid;

    if (userId == null) return;

    final room = await roomProvider.createGroupRoom(
      ownerId: userId,
      memberIds: _selectedFriendIds.toList(),
      name: groupName,
    );

    setState(() => _isCreating = false);

    if (room != null && mounted) {
      Navigator.pop(context, room);
    }
  }
}
