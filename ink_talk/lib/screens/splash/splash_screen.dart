import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// 스플래시 화면 (로딩 중)
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로고 아이콘
            Icon(
              Icons.edit,
              size: 80,
              color: AppColors.gold,
            ),
            SizedBox(height: 24),
            
            // 앱 이름
            Text(
              'INK',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 24),
            
            // 로딩 인디케이터
            CircularProgressIndicator(
              color: AppColors.gold,
            ),
          ],
        ),
      ),
    );
  }
}
