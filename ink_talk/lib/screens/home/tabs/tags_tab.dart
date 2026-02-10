import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/tag_model.dart';
import '../../../models/room_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tag_provider.dart';
import '../../../providers/room_provider.dart';
import '../../canvas/canvas_screen.dart';

/// 모아보기(태그함) 탭
class TagsTab extends StatefulWidget {
  const TagsTab({super.key});

  @override
  State<TagsTab> createState() => _TagsTabState();
}

class _TagsTabState extends State<TagsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTags();
    });
  }

  void _initTags() {
    final authProvider = context.read<AuthProvider>();
    final tagProvider = context.read<TagProvider>();
    
    if (authProvider.user != null) {
      tagProvider.subscribeToMyTags(authProvider.user!.uid);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('모아보기'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: Consumer<TagProvider>(
        builder: (context, tagProvider, _) {
          if (tagProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final tags = _filterBySearch(tagProvider.tags);

          if (tags.isEmpty) {
            return _buildEmptyTagsList();
          }

          return RefreshIndicator(
            onRefresh: () async => _initTags(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tags.length,
              itemBuilder: (context, index) {
                return _buildTagCard(tags[index]);
              },
            ),
          );
        },
      ),
    );
  }

  List<TagModel> _filterBySearch(List<TagModel> tags) {
    if (_searchQuery.isEmpty) return tags;
    // 검색어로 필터 (방 ID나 태거 ID 포함)
    return tags.where((t) => 
      t.roomId.contains(_searchQuery) || 
      t.taggerId.contains(_searchQuery)
    ).toList();
  }

  Widget _buildTagCard(TagModel tag) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: tag.isRead ? colorScheme.surface : AppColors.gold.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: tag.isRead ? colorScheme.outline : AppColors.gold,
          width: tag.isRead ? 1 : 2,
        ),
      ),
      child: InkWell(
        onTap: () => _jumpToOriginal(tag),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 아이콘
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getTypeColor(context, tag.targetType).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getTypeIcon(tag.targetType),
                  color: _getTypeColor(context, tag.targetType),
                ),
              ),
              const SizedBox(width: 12),
              // 내용
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getTypeName(tag.targetType),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '채팅방: ${tag.roomId.substring(0, 8)}...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _formatDateTime(tag.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // 화살표
              const Icon(
                Icons.chevron_right,
                color: AppColors.mutedGray,
              ),
            ],
          ),
        ),
      ),
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

  void _showSearchDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          title: const Text('검색'),
          content: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '검색어 입력',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              setState(() => _searchQuery = value);
              Navigator.pop(context);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                });
                Navigator.pop(context);
              },
              child: const Text('초기화'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _searchQuery = _searchController.text);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
              ),
              child: const Text('검색'),
            ),
          ],
        );
      },
    );
  }

  void _showFilterSheet(BuildContext context) {
    final tagProvider = context.read<TagProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '유형',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _buildFilterChip('전체', tagProvider.filterType == null, () {
                          tagProvider.setFilter(type: null);
                          setState(() {});
                        }),
                        _buildFilterChip('손글씨', tagProvider.filterType == TagTargetType.stroke, () {
                          tagProvider.setFilter(type: TagTargetType.stroke);
                          setState(() {});
                        }),
                        _buildFilterChip('사진', tagProvider.filterType == TagTargetType.image, () {
                          tagProvider.setFilter(type: TagTargetType.image);
                          setState(() {});
                        }),
                        _buildFilterChip('영상', tagProvider.filterType == TagTargetType.video, () {
                          tagProvider.setFilter(type: TagTargetType.video);
                          setState(() {});
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton(
                      onPressed: () {
                        tagProvider.clearFilters();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('필터 초기화'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.gold.withValues(alpha: 0.2),
      checkmarkColor: AppColors.gold,
      onSelected: (_) => onTap(),
    );
  }

  /// 원본으로 점프
  void _jumpToOriginal(TagModel tag) async {
    final tagProvider = context.read<TagProvider>();
    final roomProvider = context.read<RoomProvider>();

    // 서버에서 방 존재 확인 (삭제된 방이면 진입 방지)
    final room = await roomProvider.getRoomFromServer(tag.roomId);
    if (room == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방이 더 이상 존재하지 않습니다.')),
        );
      }
      return;
    }

    if (!tag.isRead) {
      tagProvider.markAsRead(tag.id);
    }

    try {
      if (mounted) {
        // 캔버스 화면으로 이동
        final highlightTagArea = tag.areaX != null &&
                tag.areaY != null &&
                tag.areaWidth != null &&
                tag.areaHeight != null
            ? Rect.fromLTWH(
                tag.areaX!,
                tag.areaY!,
                tag.areaWidth!,
                tag.areaHeight!,
              )
            : null;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CanvasScreen(
              room: room,
              jumpToPosition: tag.areaX != null && tag.areaY != null
                  ? Offset(tag.areaX!, tag.areaY!)
                  : null,
              highlightTagArea: highlightTagArea,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방을 찾을 수 없습니다')),
        );
      }
    }
  }

  Future<RoomModel?> _getRoomById(String roomId) async {
    final roomProvider = context.read<RoomProvider>();
    // 이미 로드된 방에서 찾기
    try {
      final room = roomProvider.rooms.firstWhere((r) => r.id == roomId);
      return room;
    } catch (e) {
      return null;
    }
  }

  IconData _getTypeIcon(TagTargetType type) {
    switch (type) {
      case TagTargetType.stroke:
        return Icons.edit;
      case TagTargetType.image:
        return Icons.image;
      case TagTargetType.video:
        return Icons.videocam;
      case TagTargetType.text:
        return Icons.text_fields;
    }
  }

  Color _getTypeColor(BuildContext context, TagTargetType type) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (type) {
      case TagTargetType.stroke:
        return colorScheme.primary;
      case TagTargetType.image:
        return Colors.green;
      case TagTargetType.video:
        return Colors.purple;
      case TagTargetType.text:
        return Colors.blue;
    }
  }

  String _getTypeName(TagTargetType type) {
    switch (type) {
      case TagTargetType.stroke:
        return '손글씨';
      case TagTargetType.image:
        return '사진';
      case TagTargetType.video:
        return '영상';
      case TagTargetType.text:
        return '텍스트';
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
