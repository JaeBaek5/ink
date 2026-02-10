import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';

/// 사용자 ID 형식: 영문 소문자, 숫자, 언더스코어만 4~24자
bool _isValidVisibleId(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 4 || trimmed.length > 24) return false;
  return RegExp(r'^[a-z0-9_]+$').hasMatch(trimmed);
}

/// 프로필 편집 화면
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _statusController = TextEditingController();
  final _visibleIdController = TextEditingController();

  UserModel? _user;
  bool _loading = true;
  String? _error;
  bool _checkingId = false;
  bool? _idAvailable;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final authProvider = context.read<AuthProvider>();
    final firebaseUser = authProvider.user;
    final uid = firebaseUser?.uid;
    if (uid == null) {
      if (mounted) setState(() { _user = null; _loading = false; });
      return;
    }

    var user = await UserService().getUserById(uid);
    // Firestore에 사용자 문서가 없으면 로그인 정보로 생성 (최초 프로필 편집 시)
    if (user == null && firebaseUser != null) {
      try {
        user = await UserService().createOrUpdateUser(firebaseUser);
      } catch (e) {
        if (mounted) {
          setState(() {
            _user = null;
            _loading = false;
            _error = '프로필을 생성하는 중 오류가 발생했습니다.';
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _user = user;
        _loading = false;
        if (user != null) {
          _nameController.text = user.displayName ?? '';
          _statusController.text = user.statusMessage ?? '';
          _visibleIdController.text = user.visibleId.isNotEmpty ? user.visibleId : '';
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    _visibleIdController.dispose();
    super.dispose();
  }

  Future<void> _checkDuplicateId() async {
    final visibleId = _visibleIdController.text.trim();
    if (visibleId.isEmpty) {
      setState(() {
        _error = '사용자 ID를 입력한 뒤 중복 검사를 해 주세요.';
        _idAvailable = null;
      });
      return;
    }
    if (!_isValidVisibleId(visibleId)) {
      setState(() {
        _error = '사용자 ID는 영문 소문자, 숫자, 언더스코어만 4~24자로 입력해 주세요.';
        _idAvailable = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _checkingId = true;
      _idAvailable = null;
    });
    try {
      final uid = context.read<AuthProvider>().user?.uid;
      final available = await UserService().checkVisibleIdAvailable(
        visibleId,
        excludeUid: uid,
      );
      if (mounted) {
        setState(() {
          _checkingId = false;
          _idAvailable = available;
          _error = available ? null : _error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingId = false;
          _idAvailable = null;
          _error = '중복 검사 중 오류가 발생했습니다.';
        });
      }
    }
  }

  Future<void> _generateNewId() async {
    setState(() {
      _error = null;
      _idAvailable = null;
      _checkingId = true;
    });
    try {
      final newId = await UserService().generateAvailableVisibleId();
      if (mounted) {
        setState(() {
          _visibleIdController.text = newId;
          _visibleIdController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: newId.length,
          );
          _checkingId = false;
          _idAvailable = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingId = false;
          _error = 'ID 생성 중 오류가 발생했습니다.';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_user == null) return;
    _formKey.currentState?.save();
    final displayName = _nameController.text.trim();
    final statusMessage = _statusController.text.trim();
    final visibleId = _visibleIdController.text.trim();

    if (visibleId.isEmpty) {
      setState(() => _error = '사용자 ID를 입력해 주세요.');
      return;
    }
    if (!_isValidVisibleId(visibleId)) {
      setState(() => _error = '사용자 ID는 영문 소문자, 숫자, 언더스코어만 4~24자로 입력해 주세요.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      await UserService().updateProfile(
        displayName: displayName.isEmpty ? null : displayName,
        statusMessage: statusMessage.isEmpty ? null : statusMessage,
        visibleId: visibleId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필이 저장되었습니다.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedColor = isDark ? theme.colorScheme.onSurfaceVariant : AppColors.mutedGray;

    if (_loading && _user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('프로필 편집')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.gold),
              const SizedBox(height: 16),
              Text('프로필을 불러오는 중...', style: TextStyle(color: mutedColor)),
            ],
          ),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('프로필 편집')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error ?? '사용자 정보를 불러올 수 없습니다.\n다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _error != null ? Colors.red : mutedColor,
                fontSize: 15,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필 편집'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('저장'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundImage: _user!.photoUrl != null
                    ? NetworkImage(_user!.photoUrl!)
                    : null,
                backgroundColor: AppColors.gold,
                child: _user!.photoUrl == null
                    ? const Icon(Icons.person, color: Colors.white, size: 40)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '프로필 사진은 Google 계정에서 변경됩니다.',
                style: TextStyle(fontSize: 12, color: mutedColor),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '이름',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 16),
            Text(
              '사용자 ID',
              style: TextStyle(
                fontSize: 12,
                color: mutedColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _visibleIdController,
              decoration: InputDecoration(
                hintText: '친구가 검색할 때 사용 (예: ink_abc123)',
                border: const OutlineInputBorder(),
                suffixIcon: _idAvailable == true
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : _idAvailable == false
                        ? const Icon(Icons.cancel, color: Colors.red, size: 20)
                        : null,
              ),
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              onChanged: (_) => setState(() => _idAvailable = null),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _checkingId ? null : _checkDuplicateId,
                  icon: _checkingId
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search, size: 18),
                  label: const Text('중복 검사'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _checkingId ? null : _generateNewId,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('추천 아이디'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            if (_idAvailable == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text('사용 가능한 ID입니다.', style: TextStyle(fontSize: 13, color: Colors.green.shade700)),
                  ],
                ),
              )
            else if (_idAvailable == false)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.cancel_outlined, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Text('이미 사용 중인 ID입니다.', style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _statusController,
              decoration: const InputDecoration(
                labelText: '상태 메시지',
                hintText: '선택 입력',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
