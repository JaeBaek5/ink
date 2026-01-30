import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// 채팅 탭
class ChatTab extends StatelessWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: 채팅 검색
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            color: AppColors.gold,
            onPressed: () {
              // TODO: 새 채팅 생성
              _showNewChatSheet(context);
            },
          ),
        ],
      ),
      body: _buildEmptyChatList(),
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
                  // TODO: 1:1 채팅 생성
                },
              ),
              ListTile(
                leading: const Icon(Icons.group, color: AppColors.ink),
                title: const Text('그룹 채팅'),
                subtitle: const Text('여러 명과 대화하기'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 그룹 채팅 생성
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
