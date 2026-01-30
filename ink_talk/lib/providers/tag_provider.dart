import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/tag_model.dart';
import '../services/tag_service.dart';

/// 태그 Provider
class TagProvider extends ChangeNotifier {
  final TagService _tagService = TagService();
  
  List<TagModel> _tags = [];
  List<TagModel> get tags => _tags;

  StreamSubscription<List<TagModel>>? _tagsSubscription;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // 필터
  TagTargetType? _filterType;
  String? _filterRoomId;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  TagTargetType? get filterType => _filterType;
  String? get filterRoomId => _filterRoomId;

  /// 내 태그 구독 시작
  void subscribeToMyTags(String userId) {
    _tagsSubscription?.cancel();
    _tagsSubscription = _tagService.getMyTagsStream(userId).listen(
      (tags) {
        _tags = _applyFilters(tags);
        notifyListeners();
      },
      onError: (e) {
        debugPrint('태그 스트림 오류: $e');
        _errorMessage = '태그를 불러오는데 실패했습니다.';
        notifyListeners();
      },
    );
  }

  /// 필터 적용
  List<TagModel> _applyFilters(List<TagModel> tags) {
    var filtered = tags;

    if (_filterType != null) {
      filtered = filtered.where((t) => t.targetType == _filterType).toList();
    }

    if (_filterRoomId != null) {
      filtered = filtered.where((t) => t.roomId == _filterRoomId).toList();
    }

    if (_filterStartDate != null) {
      filtered = filtered.where((t) => t.createdAt.isAfter(_filterStartDate!)).toList();
    }

    if (_filterEndDate != null) {
      filtered = filtered.where((t) => t.createdAt.isBefore(_filterEndDate!)).toList();
    }

    return filtered;
  }

  /// 필터 설정
  void setFilter({
    TagTargetType? type,
    String? roomId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    _filterType = type;
    _filterRoomId = roomId;
    _filterStartDate = startDate;
    _filterEndDate = endDate;
    // 기존 태그에 필터 다시 적용
    _tags = _applyFilters(_tags);
    notifyListeners();
  }

  /// 필터 초기화
  void clearFilters() {
    _filterType = null;
    _filterRoomId = null;
    _filterStartDate = null;
    _filterEndDate = null;
    notifyListeners();
  }

  /// 태그 생성
  Future<void> createTag(TagModel tag) async {
    try {
      await _tagService.createTag(tag);
    } catch (e) {
      _errorMessage = '태그 생성에 실패했습니다.';
      notifyListeners();
    }
  }

  /// 태그 읽음 처리
  Future<void> markAsRead(String tagId) async {
    await _tagService.markAsRead(tagId);
  }

  /// 태그 삭제
  Future<void> deleteTag(String tagId) async {
    await _tagService.deleteTag(tagId);
  }

  /// 읽지 않은 태그 수
  int get unreadCount => _tags.where((t) => !t.isRead).length;

  @override
  void dispose() {
    _tagsSubscription?.cancel();
    super.dispose();
  }
}
