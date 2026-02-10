import 'package:flutter/material.dart';
import '../../core/utils/responsive.dart';
import '../../core/constants/app_colors.dart';

/// 적응형 스캐폴드 (폰: 탭 기반, 패드: 3패널)
class AdaptiveScaffold extends StatelessWidget {
  /// 현재 선택된 탭 인덱스
  final int currentIndex;
  
  /// 탭 변경 콜백
  final ValueChanged<int> onTabChanged;
  
  /// 탭별 화면 목록
  final List<Widget> screens;
  
  /// 탭 아이템 목록
  final List<BottomNavigationBarItem> tabItems;
  
  /// 선택된 화면의 상세 뷰 (패드 우측 패널)
  final Widget? detailView;
  
  /// 좌측 네비게이션 패널 (패드 전용)
  final Widget? navigationPanel;

  const AdaptiveScaffold({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
    required this.screens,
    required this.tabItems,
    this.detailView,
    this.navigationPanel,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      // 폰: 기존 탭 기반 레이아웃
      phone: _PhoneLayout(
        currentIndex: currentIndex,
        onTabChanged: onTabChanged,
        screens: screens,
        tabItems: tabItems,
      ),
      // 패드/데스크톱: 3패널 레이아웃
      tablet: _TabletLayout(
        currentIndex: currentIndex,
        onTabChanged: onTabChanged,
        screens: screens,
        tabItems: tabItems,
        detailView: detailView,
        navigationPanel: navigationPanel,
      ),
    );
  }
}

/// 폰 레이아웃 (하단 탭)
class _PhoneLayout extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  final List<Widget> screens;
  final List<BottomNavigationBarItem> tabItems;

  const _PhoneLayout({
    required this.currentIndex,
    required this.onTabChanged,
    required this.screens,
    required this.tabItems,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colorScheme.outline, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTabChanged,
          items: tabItems,
        ),
      ),
    );
  }
}

/// 패드/데스크톱 레이아웃 (3패널: 좌 네비/중 목록/우 상세)
class _TabletLayout extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  final List<Widget> screens;
  final List<BottomNavigationBarItem> tabItems;
  final Widget? detailView;
  final Widget? navigationPanel;

  const _TabletLayout({
    required this.currentIndex,
    required this.onTabChanged,
    required this.screens,
    required this.tabItems,
    this.detailView,
    this.navigationPanel,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape = Responsive.isLandscape(context);
    final dividerColor = Theme.of(context).colorScheme.outline;
    return Scaffold(
      body: Row(
        children: [
          // 좌측 네비게이션 레일
          _NavigationRail(
            currentIndex: currentIndex,
            onTabChanged: onTabChanged,
            tabItems: tabItems,
          ),
          
          // 구분선 (테마 색)
          VerticalDivider(width: 1, thickness: 1, color: dividerColor),
          
          // 중앙: 목록 또는 메인 콘텐츠
          Expanded(
            flex: isLandscape ? 2 : 3,
            child: screens[currentIndex],
          ),
          
          // 우측: 상세 뷰 (있을 경우)
          if (detailView != null && isLandscape) ...[
            VerticalDivider(width: 1, thickness: 1, color: dividerColor),
            Expanded(
              flex: 3,
              child: detailView!,
            ),
          ],
        ],
      ),
    );
  }
}

/// 좌측 네비게이션 레일 (다크 모드 대응)
class _NavigationRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  final List<BottomNavigationBarItem> tabItems;

  const _NavigationRail({
    required this.currentIndex,
    required this.onTabChanged,
    required this.tabItems,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: currentIndex,
      onDestinationSelected: onTabChanged,
      backgroundColor: colorScheme.surface,
      indicatorColor: AppColors.gold.withValues(alpha: 0.2),
      selectedIconTheme: IconThemeData(color: colorScheme.onSurface),
      unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
      labelType: NavigationRailLabelType.all,
      destinations: tabItems.map((item) {
        return NavigationRailDestination(
          icon: item.icon,
          selectedIcon: item.activeIcon,
          label: Text(item.label ?? ''),
        );
      }).toList(),
    );
  }
}
