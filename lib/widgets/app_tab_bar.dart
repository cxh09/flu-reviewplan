import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 底部标签项
class AppTabBarItem {
  const AppTabBarItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// 底部标签栏（TDesign 移动端形态 + 选中弹跳动画）。
///
/// 这里没有直接用 `TTabBar`：它在 `iconText` 形态下，`indicatorAnimation`
/// 生成的动画指示器高度为 null，实际渲染高度是 0（等于没有），
/// 因此既拿不到胶囊选中背景、也没有动画。改成自绘，
/// 视觉全部取自 TDesign token（`context.tTheme`），并补上选中时的弹跳。
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
  });

  final List<AppTabBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      color: theme.bgColorContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(height: 0.5, color: theme.componentStrokeColor),
          SizedBox(
            height: 58,
            child: Row(
              children: List<Widget>.generate(items.length, (index) {
                return Expanded(
                  child: _TabItem(
                    item: items[index],
                    selected: index == currentIndex,
                    onTap: () => onChanged(index),
                  ),
                );
              }),
            ),
          ),
          // 手势条留白
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppTabBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> with SingleTickerProviderStateMixin {
  /// 弹跳动画控制器
  late final AnimationController _bounce;

  /// 图标缩放：放大 → 回弹过头一点 → 归位
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 1.32)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.32, end: 0.9)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 26,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.9, end: 1)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 34,
      ),
    ]).animate(_bounce);

    // 初始就已选中的那一项不播放动画，避免一进页面就抖一下
    if (widget.selected) _bounce.value = 1;
  }

  @override
  void didUpdateWidget(covariant _TabItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected && widget.selected) {
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final selected = widget.selected;
    final activeColor = theme.brandNormalColor;
    final idleColor = theme.textColorPlaceholder;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // 胶囊选中底色：跟着选中状态淡入淡出，尺寸保持不变，避免整行跳动
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            decoration: BoxDecoration(
              color: selected ? theme.brandLightColor : Colors.transparent,
              borderRadius: BorderRadius.circular(theme.radiusRound),
            ),
            child: ScaleTransition(
              scale: _scale,
              child: TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 220),
                tween: ColorTween(
                  end: selected ? activeColor : idleColor,
                ),
                builder: (context, color, _) => Icon(
                  widget.item.icon,
                  size: 22,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? activeColor : idleColor,
            ),
            child: Text(widget.item.label),
          ),
        ],
      ),
    );
  }
}
