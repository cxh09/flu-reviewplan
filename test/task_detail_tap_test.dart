import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reviewplan_mobile/app.dart';
import 'package:reviewplan_mobile/data/plan_data.dart';
import 'package:reviewplan_mobile/stores/app_store.dart';
import 'package:reviewplan_mobile/stores/plan_store.dart';
import 'package:reviewplan_mobile/stores/plaza_store.dart';
import 'package:reviewplan_mobile/stores/sync_store.dart';
import 'package:reviewplan_mobile/utils/date_utils.dart';
import 'package:reviewplan_mobile/utils/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首页「我的排版计划」里的任务行必须能点开半屏详情（标记完成 + 上传完成情况）。
///
/// 这条链路是后补的：日程表上的任务块早就接了 `showScheduleDetailSheet`，
/// 首页的行当时只是纯展示，点下去没有任何反馈。
/// 竖屏 / 横屏都要覆盖——两种尺寸下外壳走的是不同布局分支
/// （竖屏 `_TopBar` + 底部标签栏，横屏侧边导航）。
Future<SyncStore> pumpAppWithPlan(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await AppStorage.init();

  final planStore = PlanStore();
  planStore.applySnapshot(<String, dynamic>{
    'plans': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'probe-1',
        'title': '探针任务',
        'category': '语文',
        'date': todayKey(),
        'startHour': DateTime.now().hour.clamp(kFirstHour, kEndHour - 2).toDouble(),
        'duration': 45,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    ],
  });

  // SyncStore 构造时会起轮询定时器，用例结束必须 dispose，否则测试报 pending timers
  final syncStore = SyncStore(planStore, PlazaStore());

  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    ReviewPlanApp(
      appStore: AppStore(),
      planStore: planStore,
      plazaStore: PlazaStore(),
      syncStore: syncStore,
    ),
  );
  await tester.pumpAndSettle();
  return syncStore;
}

void main() {
  for (final entry in <String, Size>{
    '竖屏': const Size(393, 852),
    '横屏': const Size(852, 393),
  }.entries) {
    testWidgets('${entry.key}：首页点击任务行弹出半屏详情', (tester) async {
      final syncStore = await pumpAppWithPlan(tester, entry.value);
      try {
        final row = find.text('探针任务');
        expect(row, findsOneWidget, reason: '首页应列出该任务');

        // 矮屏下行可能在首屏之外，先滚进可视区
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();

        // 横屏下面板不渲染标题行（见 _SheetFrame），所以只能拿方向无关的表单标签断言
        expect(find.text('日程名称'), findsOneWidget,
            reason: '${entry.key}下点击任务行未弹出详情面板');
        // 详情里必须给得出完成入口
        expect(find.textContaining('标记为'), findsOneWidget);
      } finally {
        syncStore.dispose();
      }
    });
  }
}
