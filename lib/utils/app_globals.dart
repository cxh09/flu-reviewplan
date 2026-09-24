import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

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
