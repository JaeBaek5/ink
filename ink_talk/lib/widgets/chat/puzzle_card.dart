import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/room_model.dart';

/// 퍼즐 카드 (채팅방 목록 아이템)
class PuzzleCard extends StatelessWidget {
  final RoomModel room;
  final String displayName;
  final String? displayImage;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const PuzzleCard({
    super.key,
    required this.room,
    required this.displayName,
    this.displayImage,
    required this.currentUserId,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unreadCount = room.members[currentUserId]?.unreadCount ?? 0;
    final lastEventIcon = _getEventIcon(room.lastEventType);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 프로필 이미지 + 퍼즐 타일 미리보기
              _buildProfileWithPreview(context),

              const SizedBox(width: 12),

              // 채팅방 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 방 이름 + 멤버 수
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (room.type == RoomType.group)
                          Text(
                            ' ${room.memberIds.length}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // 마지막 이벤트 미리보기
                    Row(
                      children: [
                        if (lastEventIcon != null) ...[
                          Icon(
                            lastEventIcon,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            room.lastEventPreview ?? '새 채팅방',
                            style: TextStyle(
                              color: unreadCount > 0
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                              fontSize: 14,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 시간 + 미확인 배지
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(room.lastActivityAt),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (unreadCount > 0) _buildUnreadBadge(unreadCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 프로필 이미지 + 퍼즐 타일 미리보기
  Widget _buildProfileWithPreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        // 메인 프로필
        CircleAvatar(
          radius: 28,
          backgroundImage: displayImage != null ? NetworkImage(displayImage!) : null,
          backgroundColor: room.type == RoomType.group
              ? AppColors.gold
              : colorScheme.surfaceContainerHighest,
          child: displayImage == null
              ? Icon(
                  room.type == RoomType.group ? Icons.group : Icons.person,
                  color: room.type == RoomType.group
                      ? Colors.white
                      : colorScheme.onSurfaceVariant,
                  size: 24,
                )
              : null,
        ),

        // 퍼즐 타일 (손글씨 미리보기 - 우하단)
        if (room.lastEventType == 'stroke')
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colorScheme.outline),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.gesture,
                size: 12,
                color: AppColors.gold,
              ),
            ),
          ),
      ],
    );
  }

  /// 미확인 배지
  Widget _buildUnreadBadge(int count) {
    final displayCount = count > 99 ? '99+' : count.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        displayCount,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 이벤트 타입별 아이콘
  IconData? _getEventIcon(String? eventType) {
    switch (eventType) {
      case 'stroke':
        return Icons.gesture;
      case 'text':
        return Icons.text_fields;
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'system':
        return Icons.info_outline;
      default:
        return null;
    }
  }

  /// 시간 포맷
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays == 0) {
      // 오늘
      final hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = hour < 12 ? '오전' : '오후';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$period $displayHour:$minute';
    } else if (diff.inDays == 1) {
      return '어제';
    } else if (diff.inDays < 7) {
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      return weekdays[dateTime.weekday - 1];
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}
