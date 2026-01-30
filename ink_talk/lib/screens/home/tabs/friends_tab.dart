import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// 친구 탭
class FriendsTab extends StatelessWidget {
  const FriendsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('친구'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: 친구 검색
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            color: AppColors.gold,
            onPressed: () {
              // TODO: 친구 추가
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          // 내 프로필 섹션
          _buildMyProfileSection(context),
          
          const Divider(),
          
          // 친구 목록 (빈 상태)
          _buildEmptyFriendsList(),
        ],
      ),
    );
  }

  Widget _buildMyProfileSection(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: const CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.gold,
        child: Icon(Icons.person, color: Colors.white, size: 28),
      ),
      title: const Text(
        '내 프로필',
        style: TextStyle(
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
}
