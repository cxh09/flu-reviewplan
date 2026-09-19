import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 移动端通用视觉组件。
///
/// 全部颜色 / 圆角 / 间距都取自 TDesign token（`context.tTheme`），
/// 与 TDesign Flutter 组件保持同一套设计语言；浅色 / 深色主题自动跟随。

/// 卡片容器：圆角 + 描边 + 容器底色
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final radius = BorderRadius.circular(theme.radiusLarge);
    final content = Padding(padding: padding, child: child);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? theme.bgColorContainer,
        borderRadius: radius,
        border: Border.all(color: theme.componentStrokeColor, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}

/// 区块标题：左侧色条 + 标题 + 可选尾部
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (accent != null) ...<Widget>[
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 小的信息标签（科目 / 难度 / 状态）
class MetaChip extends StatelessWidget {
  const MetaChip({
    super.key,
    required this.text,
    this.color,
    this.background,
    this.icon,
  });

  final String text;
  final Color? color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final foreground = color ?? theme.textColorSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? theme.bgColorSecondaryContainer,
        borderRadius: BorderRadius.circular(theme.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(text, style: TextStyle(fontSize: 11, color: foreground)),
        ],
      ),
    );
  }
}

/// 半屏面板的统一动效参数。
///
/// 待办面板（页面内的 `AnimatedPositioned`）和所有弹层
/// （走 [showAppSheetBuilder] 的自定义路由）都取这里的值，
/// 保证从底部滑入的手感完全一致，也不会各改各的慢慢跑偏。
class AppMotion {
  AppMotion._();

  /// 滑入 / 滑出时长
  static const Duration sheet = Duration(milliseconds: 260);

  /// 滑入曲线；滑出沿用同一条，和待办面板的隐式动画保持一致
  static const Curve sheetCurve = Curves.easeOutCubic;

  /// 下拉松手后的回弹时长
  static const Duration sheetSettle = Duration(milliseconds: 220);

  /// 下拉超过这个距离就判定为「要关掉」
  static const double swipeDismissThreshold = 96;

  /// 下拉速度超过这个值也判定为「要关掉」
  static const double swipeDismissVelocity = 700;
}

/// 底部弹层骨架：拖拽条 + 标题 + 关闭按钮 + 内容区 + 可选底部操作区。
///
/// 所有弹层（合集 / 日程 / 添加日程 / 详情 / 日期选择）都复用它，
/// 免得每个文件各抄一遍这套外框；下拉交互与动效在 [_SheetFrame] 里。
class AppSheetShell extends StatelessWidget {
  const AppSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.maxHeightRatio = 0.9,
  });

  final String title;
  final Widget child;

  /// 底部操作区；不传则只留安全区留白
  final Widget? footer;
  final double maxHeightRatio;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: title,
      footer: footer,
      maxHeightRatio: maxHeightRatio,
      child: child,
    );
  }
}

class _SheetFrame extends StatefulWidget {
  const _SheetFrame({
    required this.title,
    required this.child,
    required this.footer,
    required this.maxHeightRatio,
  });

  final String title;
  final Widget child;
  final Widget? footer;
  final double maxHeightRatio;

  @override
  State<_SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<_SheetFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;

  /// 下拉位移（像素，>= 0）
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: AppMotion.sheetSettle,
    )..addListener(_onSettleTick);
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  void _onSettleTick() {
    final animation = _settleAnimation;
    if (animation == null) return;
    setState(() => _dragOffset = animation.value);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _settleController.stop();
    setState(() => _dragOffset = (_dragOffset + details.delta.dy).clamp(0, 800));
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_dragOffset > AppMotion.swipeDismissThreshold ||
        velocity > AppMotion.swipeDismissVelocity) {
      _close();
      return;
    }
    // 没到阈值就滑回原位
    _settleAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _settleController, curve: AppMotion.sheetCurve),
    );
    _settleController.forward(from: 0);
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final media = MediaQuery.of(context);
    final insets = media.viewInsets.bottom;
    final bottomInset = media.padding.bottom;

    // 键盘弹起时整体上移，同时把可用高度减掉键盘，避免顶到状态栏
    final available = media.size.height * widget.maxHeightRatio - insets;
    final maxHeight = available < 240 ? 240.0 : available;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            // 弹层必须有 Material 祖先：Flutter 在没有 Material 的子树里会把文字
            // 套成「红字 + 双黄下划线」的错误样式；按钮的水波纹也要靠它做墨水层。
            // （showModalBottomSheet 自带一层 Material，换成自定义路由后要自己补。）
            color: theme.bgColorContainer,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(theme.radiusExtraLarge),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 拖拽条：点一下收起（与待办面板一致），按住下拉可以甩掉
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                onVerticalDragUpdate: _handleDragUpdate,
                onVerticalDragEnd: _handleDragEnd,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.componentBorderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _handleDragUpdate,
                onVerticalDragEnd: _handleDragEnd,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 8, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _close,
                        icon: const Icon(TIcons.close, size: 20),
                        tooltip: '关闭',
                        color: theme.textColorPlaceholder,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: widget.child,
                ),
              ),
              if (widget.footer != null) ...<Widget>[
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
                  child: widget.footer!,
                ),
              ] else
                SizedBox(height: bottomInset),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹层底部的「取消 / 确定」两个按钮
class AppSheetActions extends StatelessWidget {
  const AppSheetActions({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.cancelText = '取消',
    this.confirmText = '保存',
    this.confirmFlex = 1,
    this.confirmDanger = false,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String cancelText;
  final String confirmText;
  final int confirmFlex;

  /// 确认按钮是否用危险色（删除 / 清空这类不可撤销的操作）
  final bool confirmDanger;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TButton(
            variant: TButtonVariant.outline,
            colorScheme: TButtonColorScheme.defaultTheme,
            child: Text(cancelText),
            onPressed: onCancel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: confirmFlex,
          child: TButton(
            variant: TButtonVariant.fill,
            colorScheme: confirmDanger
                ? TButtonColorScheme.danger
                : TButtonColorScheme.primary,
            child: Text(confirmText),
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}

/// 打开一个底部弹层（内容由骨架补齐）
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  Widget? footer,
  double maxHeightRatio = 0.9,
}) {
  return showAppSheetBuilder<T>(
    context,
    (_) => AppSheetShell(
      title: title,
      footer: footer,
      maxHeightRatio: maxHeightRatio,
      child: child,
    ),
  );
}

/// 打开一个底部弹层（内容自带 [AppSheetShell]）。
/// 需要跟随弹层内部状态刷新底部按钮时用这个。
///
/// 动效没有走 `showModalBottomSheet`：那套是 250ms + `easeOutQuad`，
/// 和待办面板的 [AppMotion.sheet]（260ms + `easeOutCubic`）对不上。
/// 这里用自定义路由直接复用 [AppMotion]，滑入手感与待办面板完全一致。
Future<T?> showAppSheetBuilder<T>(BuildContext context, WidgetBuilder builder) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black54,
    transitionDuration: AppMotion.sheet,
    pageBuilder: (context, animation, secondaryAnimation) => Align(
      alignment: Alignment.bottomCenter,
      child: builder(context),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.sheetCurve,
        reverseCurve: AppMotion.sheetCurve,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// 二次确认（删除 / 清空 / 覆盖这类不可撤销的操作）。
///
/// 和别的半屏面板一样从底部滑入、共用同一套 [AppMotion]，
/// 不再是居中的弹窗——手机上拇指够得着底部，确认与取消都在顺手的位置。
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String content,
  String confirmText = '确认',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final result = await showAppSheetBuilder<bool>(
    context,
    (sheetContext) {
      final theme = sheetContext.tTheme;
      final accent = danger ? theme.errorNormalColor : theme.brandNormalColor;

      return AppSheetShell(
        title: title,
        footer: AppSheetActions(
          cancelText: cancelText,
          confirmText: confirmText,
          confirmDanger: danger,
          onCancel: () => Navigator.of(sheetContext).pop(false),
          onConfirm: () => Navigator.of(sheetContext).pop(true),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              danger ? TIcons.error_circle : TIcons.info_circle,
              size: 18,
              color: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.7,
                  color: theme.textColorSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  // 点遮罩或下拉关闭都没带回值，一律按「取消」处理
  return result == true;
}

/// 表单里的一个字段（标签 + 控件）
class AppFormField extends StatelessWidget {
  const AppFormField({super.key, required this.label, required this.child, this.tip});

  final String label;
  final Widget child;
  final String? tip;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.textColorSecondary,
            ),
          ),
          if (tip != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(tip!, style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder)),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// 一排可点选的标签（科目 / 开始时间这类选项在手机上比下拉框更好点）
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.labelOf,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T value)? labelOf;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = option == selected;
        return GestureDetector(
          onTap: () => onChanged(option),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.brandLightColor
                  : theme.bgColorSecondaryContainer,
              borderRadius: BorderRadius.circular(theme.radiusRound),
              border: Border.all(
                color: isSelected ? theme.brandNormalColor : Colors.transparent,
              ),
            ),
            child: Text(
              labelOf?.call(option) ?? '$option',
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? theme.brandNormalColor : theme.textColorSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 空态占位（带可选操作按钮）
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.text,
    this.actionText,
    this.onAction,
    this.icon = TIcons.folder_open,
  });

  final String text;
  final String? actionText;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 40, color: theme.textColorPlaceholder),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.7, color: theme.textColorPlaceholder),
          ),
          if (actionText != null && onAction != null) ...<Widget>[
            const SizedBox(height: 16),
            TButton(
              size: TButtonSize.small,
              variant: TButtonVariant.outline,
              colorScheme: TButtonColorScheme.primary,
              child: Text(actionText!),
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
