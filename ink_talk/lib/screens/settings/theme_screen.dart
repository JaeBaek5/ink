import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/theme_provider.dart';

/// 테마 선택 화면
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('테마')),
      body: ListView(
        children: [
          RadioListTile<ThemeMode>(
            title: const Text('라이트'),
            subtitle: const Text('밝은 배경'),
            value: ThemeMode.light,
            groupValue: themeProvider.themeMode,
            activeColor: AppColors.gold,
            onChanged: (v) {
              if (v != null) themeProvider.setThemeMode(v);
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('다크'),
            subtitle: const Text('어두운 배경'),
            value: ThemeMode.dark,
            groupValue: themeProvider.themeMode,
            activeColor: AppColors.gold,
            onChanged: (v) {
              if (v != null) themeProvider.setThemeMode(v);
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('시스템 설정'),
            subtitle: const Text('기기 설정을 따름'),
            value: ThemeMode.system,
            groupValue: themeProvider.themeMode,
            activeColor: AppColors.gold,
            onChanged: (v) {
              if (v != null) themeProvider.setThemeMode(v);
            },
          ),
        ],
      ),
    );
  }
}
