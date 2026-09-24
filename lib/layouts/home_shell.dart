import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../pages/home_page.dart';
import '../pages/plaza_page.dart';
import '../pages/schedule_page.dart';
import '../pages/settings_page.dart';
import '../stores/app_store.dart';
import '../stores/connection.dart';
import '../stores/plan_store.dart';
import '../stores/sync_store.dart';
import '../utils/app_globals.dart';
import '../utils/app_tabs.dart';
import '../utils/responsive.dart';
import '../widgets/app_tab_bar.dart';

/// 应用外壳（对应网页版 `layouts/BasicLayout.vue`）：
/// 顶部品牌 + 倒计时 + 主题切换，中间连接状态条与页面内容，底部四标签导航。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const List<String> _titles = <String>['首页', '日程表', '日程广场', '设置'];

  static const List<AppTabBarItem> _tabs = <AppTabBarItem>[
    AppTabBarItem(label: '首页', icon: TIcons.home),
    AppTabBarItem(label: '日程表', icon: TIcons.calendar),
    AppTabBarItem(label: '日程广场', icon: TIcons.queue),
    AppTabBarItem(label: '设置', icon: TIcons.setting),
  ];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    appTabIndex.addListener(_syncTabIndex);
    // 启动即连接云端：拿到权威数据后才允许编辑，连不上会进入只读并自动重试
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<SyncStore>().connect());
    });
  }

  void _syncTabIndex() {
    if (!mounted || appTabIndex.value == _index) return;
    setState(() => _index = appTabIndex.value);
  }

  @override
  void dispose() {
    appTabIndex.removeListener(_syncTabIndex);
    super.dispose();
  }

  void _goToSettings() => goToTab(AppTab.settings);

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final connection = context.watch<ConnectionManager>();
    // 平板 / 横屏大屏（宽度达到阈值）改用左侧导航栏，把纵向空间留给内容。
    final useSideNav = context.useSideNav;

    // 横屏（侧边导航）下去掉顶部标题栏，把纵向空间留给内容；
    // 主题切换挪到侧边栏底部，状态栏高度用 SizedBox 补回。
    final topInset = MediaQuery.of(context).padding.top;
    final contentColumn = Column(
      children: <Widget>[
        if (useSideNav)
          SizedBox(height: topInset)
        else
          _TopBar(title: _titles[_index]),
        if (connection.status != ConnectionStatus.online)
          _ConnectionNotice(
            status: connection.status,
            message: context.watch<SyncStore>().connectionMessage,
            onGoSettings: _goToSettings,
          ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: const <Widget>[
              HomePage(),
              SchedulePage(),
              PlazaPage(),
              SettingsPage(),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      key: appRootKey,
      backgroundColor: theme.bgColorContainer,
      body: useSideNav
          ? SafeArea(
              top: false,
              child: Row(
                children: <Widget>[
                  _SideNav(index: _index, tabs: _tabs),
                  Container(width: 0.5, color: theme.componentStrokeColor),
                  Expanded(child: contentColumn),
                ],
              ),
            )
          : SafeArea(
              bottom: false,
              top: false,
              child: contentColumn,
            ),
      bottomNavigationBar: useSideNav
          ? null
          : AppTabBar(
              currentIndex: _index,
              onChanged: goToTab,
              items: _tabs,
            ),
    );
  }
}

/// 平板 / 横屏下的左侧导航栏（对应手机端的底部标签栏）。
class _SideNav extends StatelessWidget {
  const _SideNav({required this.index, required this.tabs});

  final int index;
  final List<AppTabBarItem> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final appStore = context.watch<AppStore>();
    final topInset = MediaQuery.of(context).padding.top;

    return Material(
      color: theme.bgColorContainer,
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: NavigationRail(
          backgroundColor: Colors.transparent,
          selectedIndex: index,
          onDestinationSelected: goToTab,
          labelType: NavigationRailLabelType.all,
          indicatorColor: theme.brandLightColor,
          selectedIconTheme: IconThemeData(color: theme.brandNormalColor),
          unselectedIconTheme: IconThemeData(color: theme.textColorPlaceholder),
          selectedLabelTextStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.brandNormalColor,
          ),
          unselectedLabelTextStyle: TextStyle(
            fontSize: 12,
            color: theme.textColorPlaceholder,
          ),
          leading: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Container(
              width: 30,
              height: 30,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: theme.componentStrokeColor,
                  width: 0.5,
                ),
              ),
              child: Image.asset('assets/app_icon_plain.png', fit: BoxFit.cover),
            ),
          ),
          destinations: tabs
              .map(
                (item) => NavigationRailDestination(
                  icon: Icon(item.icon, size: 22),
                  label: Text(item.label),
                ),
              )
              .toList(),
          // 顶部标题栏在横屏下被去掉，主题切换按钮挪到这里
          trailing: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IconButton(
              onPressed: appStore.toggleTheme,
              tooltip: appStore.isDark ? '切换到浅色模式' : '切换到深色模式',
              icon: Icon(appStore.isDark ? TIcons.sunny : TIcons.moon, size: 18),
              color: theme.textColorSecondary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部条：品牌 + 当前页标题 + 倒计时徽标 + 主题切换
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final appStore = context.watch<AppStore>();
    final days = context.watch<PlanStore>().daysToGaokao;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    final countdownText = days > 0
        ? '距高考 $days 天'
        : days == 0
            ? '高考就在今天'
            : '高考已过 ${-days} 天';

    return Container(
      padding: EdgeInsets.only(top: statusBarHeight),
      decoration: BoxDecoration(
        color: theme.bgColorContainer,
        border: Border(bottom: BorderSide(color: theme.componentStrokeColor, width: 0.5)),
      ),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.componentStrokeColor, width: 0.5),
                ),
                child: Image.asset('assets/app_icon_plain.png', fit: BoxFit.cover),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.brandLightColor,
                  borderRadius: BorderRadius.circular(theme.radiusRound),
                ),
                child: Text(
                  countdownText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.brandNormalColor,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                onPressed: appStore.toggleTheme,
                tooltip: appStore.isDark ? '切换到浅色模式' : '切换到深色模式',
                icon: Icon(appStore.isDark ? TIcons.sunny : TIcons.moon, size: 18),
                color: theme.textColorSecondary,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 连接状态提示条（连接中 / 连接失败 / 未配置）
class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice({
    required this.status,
    required this.message,
    required this.onGoSettings,
  });

  final ConnectionStatus status;
  final String message;
  final VoidCallback onGoSettings;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;

    late final Color foreground;
    late final Color background;
    late final IconData icon;
    String? actionText;

    switch (status) {
      case ConnectionStatus.connecting:
        foreground = theme.brandNormalColor;
        background = theme.brandLightColor;
        icon = TIcons.loading;
      case ConnectionStatus.unconfigured:
        foreground = theme.warningNormalColor;
        background = theme.warningLightColor;
        icon = TIcons.info_circle;
        actionText = '去设置';
      case ConnectionStatus.offline:
        foreground = theme.errorNormalColor;
        background = theme.errorLightColor;
        icon = TIcons.error_circle;
        actionText = '立即重试';
      case ConnectionStatus.online:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: <Widget>[
          if (status == ConnectionStatus.connecting)
            _SpinningIcon(color: foreground)
          else
            Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, height: 1.5, color: foreground),
            ),
          ),
          if (actionText != null)
            TextButton(
              onPressed: status == ConnectionStatus.unconfigured
                  ? onGoSettings
                  : () => context.read<SyncStore>().connect(),
              style: TextButton.styleFrom(
                foregroundColor: foreground,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionText, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// 连接中的旋转图标。
///
/// 静态的 `TIcons.loading` 看起来像"卡住了"，加一个匀速旋转，
/// 和网页版连接状态条上的 spin 一致。
class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.color});

  final Color color;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(TIcons.loading, size: 16, color: widget.color),
    );
  }
}
