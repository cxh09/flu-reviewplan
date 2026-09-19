import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import 'layouts/home_shell.dart';
import 'stores/app_store.dart';
import 'stores/connection.dart';
import 'stores/plan_store.dart';
import 'stores/plaza_store.dart';
import 'stores/sync_store.dart';
import 'utils/app_globals.dart';

/// 应用根组件。
///
/// 网页版是给 `<html>` 挂 `theme-mode` 让 TDesign 的 CSS 变量整体切换；
/// 移动端对应的是 `TThemeBuilder.light / dark` 两套 ThemeData + themeMode。
class ReviewPlanApp extends StatefulWidget {
  const ReviewPlanApp({
    super.key,
    required this.appStore,
    required this.planStore,
    required this.plazaStore,
    required this.syncStore,
  });

  final AppStore appStore;
  final PlanStore planStore;
  final PlazaStore plazaStore;
  final SyncStore syncStore;

  @override
  State<ReviewPlanApp> createState() => _ReviewPlanAppState();
}

class _ReviewPlanAppState extends State<ReviewPlanApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // 切到后台 / 关闭前：把还没发出的改动补发一次（数据不落盘，全在线以云端为准）
    _lifecycleListener = AppLifecycleListener(
      onPause: _flushAll,
      onHide: _flushAll,
      onDetach: _flushAll,
    );
  }

  void _flushAll() {
    widget.syncStore.flushPending();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = TThemeData.defaultData();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStore>.value(value: widget.appStore),
        ChangeNotifierProvider<PlanStore>.value(value: widget.planStore),
        ChangeNotifierProvider<PlazaStore>.value(value: widget.plazaStore),
        ChangeNotifierProvider<SyncStore>.value(value: widget.syncStore),
        ChangeNotifierProvider<ConnectionManager>.value(value: connectionManager),
      ],
      child: Consumer<AppStore>(
        builder: (context, appStore, _) {
          return MaterialApp(
            title: '复习清单',
            debugShowCheckedModeBanner: false,
            navigatorKey: appNavigatorKey,
            theme: TThemeBuilder.light(token),
            darkTheme: TThemeBuilder.dark(token),
            themeMode: appStore.themeMode,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
