import 'package:flutter/material.dart';

import '../utils/storage.dart';

/// 主题偏好（对齐网页版 `src/stores/app.js`）。
///
/// 网页版是把 `theme-mode` 写到 `<html>` 上让 TDesign 的 CSS 变量整体切换，
/// 移动端对应的是给 MaterialApp 换一套 [ThemeData]。
class AppStore extends ChangeNotifier {
  AppStore() {
    _theme = AppStorage.readText(AppStorage.themeKey) == 'dark' ? 'dark' : 'light';
  }

  late String _theme;

  String get theme => _theme;
  bool get isDark => _theme == 'dark';
  ThemeMode get themeMode => isDark ? ThemeMode.dark : ThemeMode.light;

  void setTheme(String mode) {
    final next = mode == 'dark' ? 'dark' : 'light';
    if (next == _theme) return;
    _theme = next;
    AppStorage.writeText(AppStorage.themeKey, _theme);
    notifyListeners();
  }

  void toggleTheme() => setTheme(isDark ? 'light' : 'dark');
}
