import 'package:flutter/foundation.dart';

/// 底部标签的当前下标。
///
/// 页面内部（例如首页空态、日程广场的「去日程表排班」）需要直接切到别的标签，
/// 用一个全局 [ValueNotifier] 比层层传回调更省事，外壳负责监听并同步标签栏。
final ValueNotifier<int> appTabIndex = ValueNotifier<int>(0);

/// 标签下标常量
class AppTab {
  AppTab._();

  static const int home = 0;
  static const int schedule = 1;
  static const int plaza = 2;
  static const int settings = 3;
}

/// 切换到某个标签
void goToTab(int index) => appTabIndex.value = index;
