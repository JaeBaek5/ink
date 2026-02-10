import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../services/contact_service.dart';

/// 연락처 동기화 화면
class ContactSyncScreen extends StatefulWidget {
  const ContactSyncScreen({super.key});

  @override
  State<ContactSyncScreen> createState() => _ContactSyncScreenState();
}

class _ContactSyncScreenState extends State<ContactSyncScreen> {
  final ContactService _contactService = ContactService();

  bool _isLoading = false;
  bool _hasPermission = false;
  List<ContactRecommendation> _recommendations = [];
  Set<String> _selectedUserIds = {};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await _contactService.checkPermission();
    setState(() {
      _hasPermission = status == PermissionStatus.granted;
    });

    if (_hasPermission) {
      _loadRecommendations();
    }
  }

  Future<void> _requestPermission() async {
    final granted = await _contactService.requestPermission();
    setState(() {
      _hasPermission = granted;
    });

    if (granted) {
      _loadRecommendations();
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.user?.uid;

      if (userId == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 연락처 가져오기
      final contacts = await _contactService.getContacts();
      
      if (contacts.isEmpty) {
        setState(() {
          _isLoading = false;
          _recommendations = [];
        });
        return;
      }

      // 전화번호 추출
      final phoneNumbers = _contactService.extractPhoneNumbers(contacts);

      // INK 가입자 찾기
      final recommendations = await _contactService.findRegisteredUsers(
        userId,
        phoneNumbers,
      );

      setState(() {
        _recommendations = recommendations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedUserIds = _recommendations.map((r) => r.user.uid).toSet();
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedUserIds.clear();
    });
  }

  Future<void> _addSelectedFriends() async {
    if (_selectedUserIds.isEmpty) return;

    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final friendProvider = context.read<FriendProvider>();
    final userId = authProvider.user?.uid;

    if (userId == null) return;

    int successCount = 0;
    int failCount = 0;

    for (final friendId in _selectedUserIds) {
      final recommendation = _recommendations.firstWhere(
        (r) => r.user.uid == friendId,
      );

      final success = await friendProvider.addFriendById(
        userId,
        recommendation.user.visibleId,
      );

      if (success) {
        successCount++;
      } else {
        failCount++;
      }
    }

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$successCount명에게 친구 요청을 보냈습니다.${failCount > 0 ? ' ($failCount명 실패)' : ''}',
          ),
        ),
      );

      if (successCount > 0) {
        // 추가된 친구 제거
        setState(() {
          _recommendations.removeWhere(
            (r) => _selectedUserIds.contains(r.user.uid),
          );
          _selectedUserIds.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('연락처 친구 찾기'),
        actions: [
          if (_recommendations.isNotEmpty)
            TextButton(
              onPressed: _selectedUserIds.length == _recommendations.length
                  ? _deselectAll
                  : _selectAll,
              child: Text(
                _selectedUserIds.length == _recommendations.length
                    ? '전체 해제'
                    : '전체 선택',
              ),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _selectedUserIds.isNotEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.border),
                  ),
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _addSelectedFriends,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: AppColors.paper,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.paper,
                          ),
                        )
                      : Text('${_selectedUserIds.length}명 친구 추가'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (!_hasPermission) {
      return _buildPermissionRequest();
    }

    if (_isLoading && _recommendations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('연락처를 확인하고 있습니다...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRecommendations,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_recommendations.isEmpty) {
      return _buildEmptyState();
    }

    return _buildRecommendationList();
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.contacts_outlined,
              size: 80,
              color: AppColors.gold,
            ),
            const SizedBox(height: 24),
            const Text(
              '연락처 접근 권한이 필요합니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '연락처에서 INK를 사용하는 친구를 찾아\n쉽게 추가할 수 있습니다.\n\n연락처 정보는 친구 찾기에만 사용되며\n서버에 저장되지 않습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.mutedGray,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _requestPermission,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: AppColors.paper,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: const Text('연락처 접근 허용'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_search_outlined,
              size: 80,
              color: AppColors.mutedGray,
            ),
            const SizedBox(height: 24),
            const Text(
              '추천할 친구가 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '연락처에 INK를 사용하는 친구가\n아직 없거나, 이미 모두 친구로 추가되어 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.mutedGray,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: _loadRecommendations,
              child: const Text('새로고침'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationList() {
    return ListView.builder(
      itemCount: _recommendations.length,
      itemBuilder: (context, index) {
        final recommendation = _recommendations[index];
        final isSelected = _selectedUserIds.contains(recommendation.user.uid);

        return _buildRecommendationTile(recommendation, isSelected);
      },
    );
  }

  Widget _buildRecommendationTile(
    ContactRecommendation recommendation,
    bool isSelected,
  ) {
    final user = recommendation.user;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
        backgroundColor: AppColors.gold,
        child: user.photoUrl == null
            ? const Icon(Icons.person, color: Colors.white)
            : null,
      ),
      title: Text(
        user.displayName ?? user.visibleId,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
      ),
      subtitle: user.statusMessage != null
          ? Text(
              user.statusMessage!,
              style: const TextStyle(color: AppColors.mutedGray),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Checkbox(
        value: isSelected,
        onChanged: (value) => _toggleSelection(user.uid),
        activeColor: AppColors.gold,
      ),
      onTap: () => _toggleSelection(user.uid),
    );
  }
}
