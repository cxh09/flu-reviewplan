import 'package:flutter/material.dart';

/// 屏幕尺寸分级（基于逻辑宽度，参考 Material 3 窗口尺寸类别）。
enum ScreenSize { compact, medium, expanded }

/// 响应式断点。
class Breakpoints {
  Breakpoints._();

  /// 平板竖屏 / 大屏手机的起始宽度。
  static const double medium = 600;

  /// 平板横屏 / 桌面的起始宽度。
  static const double expanded = 840;

  /// 达到该宽度时，用左侧导航栏替代底部标签栏（横屏手机、平板都受益）。
  static const double sideNav = 720;
}

/// 在 [BuildContext] 上直接读取屏幕尺寸信息，供各页面做自适应布局。
extension ResponsiveContext on BuildContext {
  Size get _screenSize => MediaQuery.of(this).size;

  double get screenWidth => _screenSize.width;
  double get screenHeight => _screenSize.height;
  bool get isLandscape => _screenSize.width > _screenSize.height;

  ScreenSize get screenSize {
    final w = screenWidth;
    if (w >= Breakpoints.expanded) return ScreenSize.expanded;
    if (w >= Breakpoints.medium) return ScreenSize.medium;
    return ScreenSize.compact;
  }

  bool get isCompact => screenSize == ScreenSize.compact;

  /// 是否为平板级别的宽屏。
  bool get isTablet => screenWidth >= Breakpoints.medium;

  /// 是否采用侧边导航（横屏大屏 / 平板）。
  bool get useSideNav => screenWidth >= Breakpoints.sideNav;

  /// 文档类页面（首页 / 广场 / 设置）正文的最大宽度，
  /// 宽屏下把内容约束到舒适阅读宽度并居中，避免被拉伸到整屏。
  double get contentMaxWidth {
    switch (screenSize) {
      case ScreenSize.compact:
        return double.infinity;
      case ScreenSize.medium:
        return 680;
      case ScreenSize.expanded:
        return 760;
    }
  }

  /// 底部弹层（抽屉 / 表单 / 确认框）在宽屏下左右各留的间距；窄屏为 0（铺满）。
  double get sheetSideMargin => isCompact ? 0 : 24;

  /// 底部弹层在宽屏下的最大宽度；窄屏不限。
  double get sheetMaxWidth => isCompact ? double.infinity : 640;

  /// 网格列数：窄屏 2 列，宽屏更多列。
  int gridColumns(int compactCount, {int expandedCount = 4}) {
    switch (screenSize) {
      case ScreenSize.compact:
        return compactCount;
      case ScreenSize.medium:
        return compactCount * 2 > expandedCount ? compactCount * 2 : expandedCount;
      case ScreenSize.expanded:
        return expandedCount;
    }
  }
}

/// 文档类页面的自适应外壳：窄屏铺满，宽屏约束到 [ResponsiveContext.contentMaxWidth]
/// 并水平居中。日程表这类需要横向铺满的时间轴页面不使用它。
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({super.key, required this.child, this.maxWidth});

  final Widget child;

  /// 覆盖默认的正文最大宽度。
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final cap = maxWidth ?? context.contentMaxWidth;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cap),
        child: child,
      ),
    );
  }
}
