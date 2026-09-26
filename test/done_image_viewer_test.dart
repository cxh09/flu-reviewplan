import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:reviewplan_mobile/stores/plan_store.dart';
import 'package:reviewplan_mobile/stores/plaza_store.dart';
import 'package:reviewplan_mobile/stores/sync_store.dart';
import 'package:reviewplan_mobile/utils/date_utils.dart';
import 'package:reviewplan_mobile/utils/storage.dart';
import 'package:reviewplan_mobile/widgets/schedule_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 完成详情图片预览走 TDesign `TImageViewer`：分页 / 页码 / 关闭由它负责，
/// 本项目额外要守住的是「默认只看 ≤1MB 预览版，点按钮才拉原图」这条策略。
///
/// 用例只关心交互与入口的有无，不关心像素；测试环境里网络图必然加载失败，
/// 而缩略图用的是没有 errorBuilder 的 DecorationImage，所以把图片解码类
/// 错误滤掉，其余错误照常抛出。
void _ignoreImageCodecErrors() {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.context?.toDescription().contains('image codec') ?? false) {
      return;
    }
    previous?.call(details);
  };
}

Future<SyncStore> pumpSheetWithImage(
  WidgetTester tester, {
  required bool withPreview,
}) async {
  _ignoreImageCodecErrors();
  SharedPreferences.setMockInitialValues(<String, Object>{
    AppStorage.serverKey:
        '{"serverUrl":"http://127.0.0.1:9","accessToken":""}',
  });
  await AppStorage.init();

  final planStore = PlanStore();
  planStore.applySnapshot(<String, dynamic>{
    'plans': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'p1',
        'title': '带图任务',
        'date': todayKey(),
        'startHour': 9,
        'duration': 45,
        'done': true,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'doneImages': <Map<String, dynamic>>[
          if (withPreview)
            <String, dynamic>{
              'name': 'big.jpg',
              'url': '/uploads/big.jpg',
              'preview': '/uploads/preview.jpg',
            }
          else
            <String, dynamic>{'name': 'small.jpg', 'url': '/uploads/small.jpg'},
        ],
      },
    ],
  });

  final syncStore = SyncStore(planStore, PlazaStore());

  final token = TThemeData.defaultData();
  // Provider 必须在 MaterialApp 之上：详情面板走 showGeneralDialog，
  // 路由挂在 root Navigator 上，放在 home 里面板就找不到 store。
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlanStore>.value(value: planStore),
        ChangeNotifierProvider<SyncStore>.value(value: syncStore),
      ],
      child: MaterialApp(
        theme: TThemeBuilder.light(token),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showScheduleDetailSheet(context, 'p1'),
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('打开详情'));
  await tester.pumpAndSettle();
  return syncStore;
}

/// 缩略图在面板的滚动区里，默认视口下常常在屏外，先滚进来再点。
Future<void> tapThumb(WidgetTester tester) async {
  final thumb = find.byKey(const ValueKey<String>('done-image-0'));
  await tester.ensureVisible(thumb);
  await tester.pumpAndSettle();
  await tester.tap(thumb);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('有独立预览图时，预览默认不拉原图，点按钮才切换', (tester) async {
    final syncStore = await pumpSheetWithImage(tester, withPreview: true);
    try {
      await tapThumb(tester);

      // ImageViewer 自带的页码
      expect(find.text('1 / 1'), findsOneWidget);
      // 默认停在预览版，右上角给出切原图的入口
      expect(find.byTooltip('查看原图'), findsOneWidget);
      expect(find.byTooltip('返回预览'), findsNothing);

      await tester.tap(find.byTooltip('查看原图'));
      await tester.pumpAndSettle();

      // 换成原图后入口反向，页码仍在（说明是重开并停在同一张）
      expect(find.byTooltip('返回预览'), findsOneWidget);
      expect(find.byTooltip('查看原图'), findsNothing);
      expect(find.text('1 / 1'), findsOneWidget);
    } finally {
      syncStore.dispose();
    }
  });

  testWidgets('小图只有一份时不给切换入口', (tester) async {
    final syncStore = await pumpSheetWithImage(tester, withPreview: false);
    try {
      await tapThumb(tester);

      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.byTooltip('查看原图'), findsNothing);
      expect(find.byTooltip('返回预览'), findsNothing);
    } finally {
      syncStore.dispose();
    }
  });
}
