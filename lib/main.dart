import 'package:flutter/material.dart';

import 'app.dart';
import 'stores/app_store.dart';
import 'stores/plan_store.dart';
import 'stores/plaza_store.dart';
import 'stores/sync_store.dart';
import 'utils/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先读本地缓存，首屏就能直接渲染，不用等云端
  await AppStorage.init();

  final planStore = PlanStore();
  final plazaStore = PlazaStore();
  final syncStore = SyncStore(planStore, plazaStore);
  final appStore = AppStore();

  runApp(
    ReviewPlanApp(
      appStore: appStore,
      planStore: planStore,
      plazaStore: plazaStore,
      syncStore: syncStore,
    ),
  );
}
