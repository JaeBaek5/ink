import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// 모아보기(태그함) 탭
class TagsTab extends StatelessWidget {
  const TagsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('모아보기'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: 태그 검색
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: 필터
              _showFilterSheet(context);
            },
          ),
        ],
      ),
      body: _buildEmptyTagsList(),
    );
  }

  Widget _buildEmptyTagsList() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_outline,
            size: 64,
            color: AppColors.mutedGray,
          ),
          SizedBox(height: 16),
          Text(
            '태그된 항목이 없습니다',
            style: TextStyle(
              color: AppColors.mutedGray,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '채팅방에서 @친구 태그를 하면\n여기에 모아볼 수 있습니다',
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

  void _showFilterSheet(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '유형',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip('전체', true),
                  _buildFilterChip('손글씨', false),
                  _buildFilterChip('사진', false),
                  _buildFilterChip('영상', false),
                ],
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '정렬',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip('최신순', true),
                  _buildFilterChip('오래된순', false),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppColors.gold.withValues(alpha: 0.2),
        checkmarkColor: AppColors.gold,
        onSelected: (value) {
          // TODO: 필터 적용
        },
      ),
    );
  }
}
