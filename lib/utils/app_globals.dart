import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../widgets/app_ui.dart';

/// 全局 Navigator 句柄（路由跳转用）
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 挂在应用外壳根节点上的 key。
///
/// store、service 这类非 UI 层弹提示时拿不到 Widget 的 context；
/// 而 TMessage 内部是 `Overlay.of(context)`，需要一个能找到 Overlay 的
/// context，这里指向外壳根节点，它在路由内容里、位于 Overlay 之下。
final GlobalKey appRootKey = GlobalKey();

BuildContext? get _appContext =>
    appRootKey.currentContext ?? appNavigatorKey.currentContext;

/// 普通文本提示
void showInfoToast(String message) {
  final context = _appContext;
  if (context == null) return;
  TMessage.show(context: context, content: message, variant: TMessageVariant.info);
}

/// 成功提示
void showSuccessToast(String message) {
  final context = _appContext;
  if (context == null) return;
  TMessage.show(context: context, content: message, variant: TMessageVariant.success);
}

/// 警告提示
void showWarningToast(String message) {
  final context = _appContext;
  if (context == null) return;
  TMessage.show(context: context, content: message, variant: TMessageVariant.warning);
}

/// 错误提示
void showErrorToast(String message) {
  final context = _appContext;
  if (context == null) return;
  TMessage.show(context: context, content: message, variant: TMessageVariant.error);
}

// ---------- 全局 loading 遮罩 ----------

OverlayEntry? _loadingEntry;
_LoadingOverlayState? _activeLoading;

/// 显示全局 loading 遮罩：TDesign 转圈 + 半透明蒙层，淡入 / 淡出各 250ms。
///
/// 所有「点了要等响应」的操作（同步到云端、上传附件、生成分享、测试连接等）
/// 都用它做过渡，避免等待期间界面看起来像卡死；蒙层同时兜住重复点击。
void showLoading({String message = '处理中…'}) {
  if (_loadingEntry != null) return; // 已在显示，避免重复叠加
  final context = _appContext;
  if (context == null) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _LoadingOverlay(
      message: message,
      onDismissed: () {
        entry.remove();
        if (_loadingEntry == entry) _loadingEntry = null;
      },
    ),
  );
  overlay.insert(entry);
  _loadingEntry = entry;
}

/// 收起全局 loading 遮罩（先淡出，动画结束后再移除）。
void hideLoading() {
  _activeLoading?.dismiss();
}

/// 包一段异步操作：期间显示全局 loading 遮罩，无论成功失败结束后都自动收起。
Future<T> runWithLoading<T>(
  Future<T> Function() task, {
  String message = '处理中…',
}) async {
  showLoading(message: message);
  try {
    return await task();
  } finally {
    hideLoading();
  }
}

/// 全局 loading 遮罩内容：自带淡入 / 淡出动画。
///
/// [onDismissed] 在淡出动画结束后回调，由外层移除 OverlayEntry。
class _LoadingOverlay extends StatefulWidget {
  const _LoadingOverlay({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<_LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.fade,
      reverseDuration: AppMotion.fade,
    )..forward();
    _activeLoading = this;
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_activeLoading == this) _activeLoading = null;
    super.dispose();
  }

  /// 淡出，动画结束后通知外层移除遮罩。
  Future<void> dismiss() async {
    if (_activeLoading == this) _activeLoading = null;
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    return FadeTransition(
      opacity: _controller,
      // 插到根 Overlay 上时，子树没有 Material 祖先，Text 会被画调试用的
      // 黄色双下划线；套一层透明 Material 消掉它，不影响观感。
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: <Widget>[
            // 蒙层：吸收手势，等待期间不让用户再点别处
            const ModalBarrier(dismissible: false, color: Colors.black38),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
                decoration: BoxDecoration(
                  color: theme.bgColorContainer,
                  borderRadius: BorderRadius.circular(theme.radiusLarge),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const TLoading(size: TLoadingSize.large),
                    if (widget.message.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        widget.message,
                        style: TextStyle(fontSize: 13, color: theme.textColorSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
