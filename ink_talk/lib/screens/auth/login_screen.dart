import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';

/// 로그인 화면
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 로고 아이콘
                const Icon(
                  Icons.edit,
                  size: 80,
                  color: AppColors.gold,
                ),
                const SizedBox(height: 24),
                
                // 앱 이름
                const Text(
                  'INK',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                
                // 슬로건
                const Text(
                  '손글씨 기반 실시간 메신저',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.mutedGray,
                  ),
                ),
                const SizedBox(height: 48),
                
                // Google 로그인 버튼
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    return SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: auth.isLoading
                            ? null
                            : () => _handleGoogleSignIn(context),
                        icon: auth.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.paper,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          auth.isLoading ? '로그인 중...' : 'Google로 로그인',
                        ),
                      ),
                    );
                  },
                ),
                
                // 에러 메시지
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    if (auth.errorMessage != null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          auth.errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleGoogleSignIn(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    authProvider.clearError();
    
    final success = await authProvider.signInWithGoogle();
    
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인에 실패했습니다.')),
      );
    }
  }
}
