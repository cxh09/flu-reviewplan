import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 全局 Navigator 句柄（路由跳转用）
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 挂在应用外壳根节点上的 key。
///
/// store、service 这类非 UI 层弹提示时拿不到 Widget 的 context；
/// 而 TToast 内部是 `Overlay.maybeOf(context)`，必须拿到 Overlay 子树里
/// 的 context（Navigator 自身的 context 在 Overlay 之上，取不到），
/// 所以这里指向外壳根节点，它在路由内容里、位于 Overlay 之下。
final GlobalKey appRootKey = GlobalKey();

BuildContext? get _appContext =>
    appRootKey.currentContext ?? appNavigatorKey.currentContext;

/// 普通文本提示
void showInfoToast(String message) {
  final context = _appContext;
  if (context == null) return;
  TToast.showText(message, context: context);
}

/// 成功提示
void showSuccessToast(String message) {
  final context = _appContext;
  if (context == null) return;
  TToast.showSuccess(message, context: context);
}

/// 警告提示
void showWarningToast(String message) {
  final context = _appContext;
  if (context == null) return;
  TToast.showWarning(message, context: context);
}

/// 错误提示
void showErrorToast(String message) {
  final context = _appContext;
  if (context == null) return;
  TToast.showFail(message, context: context);
}
