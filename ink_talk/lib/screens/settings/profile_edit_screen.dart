import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;

    final user = await UserService().getUserById(uid);
    if (mounted) {
      setState(() {
        _user = user;
        _loading = false;
        if (user != null) {
          _nameController.text = user.displayName ?? '';
          _statusController.text = user.statusMessage ?? '';
          _visibleIdController.text = user.visibleId;
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

  Future<void> _save() async {
    if (_user == null) return;
    _formKey.currentState?.save();
    final displayName = _nameController.text.trim();
    final statusMessage = _statusController.text.trim();
    final visibleId = _visibleIdController.text.trim();

    if (visibleId.isEmpty) {
      setState(() => _error = '표시 ID를 입력해 주세요.');
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
    if (_loading && _user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('프로필 편집')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('프로필 편집')),
        body: const Center(child: Text('사용자 정보를 불러올 수 없습니다.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
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
            const Center(
              child: Text(
                '프로필 사진은 Google 계정에서 변경됩니다.',
                style: TextStyle(fontSize: 12, color: AppColors.mutedGray),
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
            TextFormField(
              controller: _visibleIdController,
              decoration: const InputDecoration(
                labelText: '표시 ID',
                hintText: '친구가 검색할 때 사용하는 ID',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.none,
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
