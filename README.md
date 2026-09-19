# 复习清单 · 移动端（Flutter）

网页版「复习清单」的 Android 移动端实现：**倒计时 + 待办清单 + 拖拽排班 + 日程广场 + 设置**，与 `../src`（Vue 3 + TDesign Vue Next）功能对齐，数据与 `../server` 共用同一份云端快照。

- 框架：Flutter 3.44（Dart 3.12），仅生成 Android 平台
- UI：`tdesign_flutter` 1.0.0-alpha.1（TDesign 官方 Flutter 组件库，alpha 版）
- 状态管理：`provider`（ChangeNotifier，对应网页版的 Pinia store）
- 本地缓存：`shared_preferences`（键名沿用网页版的 `reviewplan:*`）

## 快速开始

```bash
cd mobile
flutter pub get          # 安装依赖
flutter run              # 连接真机 / 模拟器后运行
flutter analyze          # 静态检查（当前为 0 issue）
flutter test             # 单元测试：日期、链接归一化、快照合并
flutter build apk --release   # 打包 Android APK
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`。

### 安装包体积

默认的通用 APK 会把 `arm64-v8a / armeabi-v7a / x86_64` 三个架构都打进去，其中 x86_64
只服务于模拟器。真机安装时按需要裁剪架构：

```bash
# 只打两种真机架构：51.8MB → 33.4MB
flutter build apk --release --target-platform android-arm64,android-arm

# 只打自己的手机（更小，约 22MB）
flutter build apk --release --target-platform android-arm64

# 装机（-r 覆盖安装，保留已保存的服务端配置）
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

> 注意：`defaultConfig.ndk.abiFilters` 对 Flutter 构建无效（会被 Flutter Gradle 插件覆盖），
> 只能用 `--target-platform`。另外 `flutter install` 在无法原地升级时会先卸载旧版本，
> 那会**清掉应用数据**（服务端地址与令牌要重填）；想保留就用上面的 `adb install -r`。

## 数据同步（全在线模式）

与网页版完全一致：**云端是唯一数据源**，未连上服务端时只读。

1. 先启动服务端（仓库根目录）：

   ```bash
   npm run server:install   # 首次
   npm run server           # 默认 http://localhost:3000
   ```

2. 打开 App → 底部「设置」→「服务端同步」：
   - **服务端地址**：真机请填电脑的局域网地址，例如 `http://192.168.1.10:3000`
     （手机上的 `localhost` 指向手机自己，连不上电脑）
   - **访问令牌**：与服务端 `server/src/config.js` 里的 `DEFAULT_ACCESS_TOKEN` 保持一致
   - 点「测试连接」，状态变成「已连接」后即可编辑

3. 连上后任何改动都会自动上传（300ms 内合并）；断线时进入只读并每 3 秒自动重试；
   多端同时改动会按条目合并（同一条谁的时间戳新谁生效），删除靠删除标记避免被另一端复活。

> 已在 `android/app/src/main/AndroidManifest.xml` 打开 `usesCleartextTraffic`，
> 否则 Android 9+ 会拦掉局域网 `http://` 请求。公网部署建议换 https。

## 目录结构

```
lib/
├── main.dart                     # 入口：初始化本地缓存 → 构建 store → runApp
├── app.dart                      # MaterialApp + TDesign 浅/深主题 + 中文本地化 + 生命周期 flush
├── data/
│   ├── plan_data.dart            # 时间轴 / 时长 / 版本等常量（对齐 stores/plan.js）
│   └── plaza_data.dart           # 科目、难度主题、科目色、合集色
├── models/                       # todo / plan / plaza_item / collection
├── utils/                        # 日期、随机 id、链接归一化、本地存储、防抖、全局 toast
├── services/
│   ├── api_client.dart           # 服务端请求（地址归一化、超时、401/409 判定）
│   ├── merge.dart                # 快照按条目 last-write-wins 合并 + 删除标记
│   └── tombstone_service.dart    # 删除标记的读写与持久化
├── stores/
│   ├── connection.dart           # 全局连接状态 + ensureWritable（只读闸门）
│   ├── app_store.dart            # 主题偏好
│   ├── plan_store.dart           # 待办 / 计划 / 高考日期 + 派生统计 + 按日索引
│   ├── plaza_store.dart          # 日程广场合集与日程
│   └── sync_store.dart           # 连接 / 拉取 / 改动即推送 / 冲突合并
├── layouts/home_shell.dart       # 顶部品牌条 + 连接状态条 + 底部四标签导航
├── pages/
│   ├── home_page.dart            # 倒计时 + 统计 + 未来 7 天计划
│   ├── schedule_page.dart        # 日程表：滚动 / 拖拽 / 落点解析 / 面板编排
│   ├── plaza_page.dart           # 日程广场
│   └── settings_page.dart        # 设置
└── widgets/
    ├── schedule_layout.dart      # 纯逻辑：网格常量、分层排版、落点单元格、拖拽类型
    ├── plan_block_view.dart      # 日历上的计划块 + 左右拉伸手柄 + 拖拽浮层卡片
    ├── todo_panel_view.dart      # 底部待办面板
    ├── schedule_detail_sheet.dart# 日程详情弹层
    ├── collection_dialog.dart    # 合集新建 / 编辑弹层
    ├── plaza_item_dialog.dart    # 合集内日程弹层
    ├── date_picker_sheet.dart    # 日期选择弹层
    ├── app_tab_bar.dart          # 底部标签栏（选中弹跳）
    └── app_ui.dart               # 通用组件：AppCard / AppSheetShell / AppSheetActions / ChoiceChips …
```

## 动效约定

所有半屏面板（底部待办面板 + 5 个弹层）共用同一组动效参数，定义在 `widgets/app_ui.dart` 的 `AppMotion`：

| 参数 | 值 |
| --- | --- |
| 滑入 / 滑出时长 | `260ms` |
| 滑入曲线 | `Curves.easeOutCubic`（滑出沿用同一条） |
| 下拉回弹时长 | `220ms` |
| 下拉关闭阈值 | 位移 > 96px 或速度 > 700px/s |

- 待办面板用页面内的 `AnimatedPositioned` 从底部滑入；
- 各弹层走 `showGeneralDialog` + `SlideTransition`（`showAppSheetBuilder`），
  **没有用 `showModalBottomSheet`**——它固定是 250ms + `easeOutQuad`，和待办面板对不上，
  这也是之前几处弹层"看着不太一样"的原因；
- 弹层都支持下拉关闭：拖拽条与标题行可以按住下滑（超过阈值松手即关），只点拖拽条则直接收起（与待办面板一致）；
- **所有模态面板统一为底部半屏**，包括二次确认（删除合集 / 删除日程 / 从云端刷新 / 清除配置 / 清空数据），
  项目里已不存在居中 `TDialog` / `showDialog`；点遮罩或下拉关闭一律按「取消」处理。

## 性能上的两个关键约定

日程表是这个应用里唯一会以 60fps 改数据的地方（拖拽排班），所以有两处专门的处理：

1. **计划按日建索引**：`PlanStore` 内部维护 `日期 → 当天计划`，`plansOfDate()` 是 O(当天条数)
   而不是每次全表过滤。计划列表也改成**原地修改**（不再每次改动整体拷贝），
   并提供 `revision` 版本号给外部做缓存失效判断。
2. **拖拽状态走 `ValueNotifier`**：手指移动只刷新「拖拽浮层位置 / 高亮的落点格子 /
   源卡片变灰」这三小块，不会重建整页（`IndexedStack` 里另外三个页面也不会跟着重建）。
   落点解析用累计行高 + 二分反算日期，不依赖 `RenderObject` 查找。

## 应用图标

源图来自网页版的 `../public/favicon.png`（64×64）。因为启动图标需要 192×192 以上，先用高质量双三次插值放大，生成三份素材放在 `assets/`：

| 文件 | 用途 |
| --- | --- |
| `app_icon.png` | 512×512 白底，用于各密度 `ic_launcher.png`（Android 8 以下的传统图标） |
| `app_icon_foreground.png` | 1024×1024 透明，图形占 62.5%，作为自适应图标前景（留出系统裁切安全区） |
| `app_icon_plain.png` | 512×512 透明，App 内顶栏品牌位使用 |

改完图标素材后重新生成：

```bash
dart run flutter_launcher_icons
```

底部标签栏是自绘的（`lib/widgets/app_tab_bar.dart`），视觉取自 TDesign token，
选中时图标做一次 460ms 的弹跳（1 → 1.32 → 0.9 → 1），胶囊底色与文字颜色淡入过渡。
没有直接用 `TTabBar`：它在 `iconText` 形态下 `indicatorAnimation` 生成的指示器高度为 null、
实际渲染高度为 0，拿不到胶囊选中背景，也就没有动画。

## 与网页版的差异（移动端适配）

| 项目 | 网页版 | 移动端 |
| --- | --- | --- |
| 导航 | 顶部 Tab 菜单 | 底部图标标签栏 |
| 表单 | 居中弹窗 | 底部弹层（BottomSheet），键盘友好 |
| 待办清单 | 右下角滑出面板，挤压日历 | 底部上滑面板，长按卡片拖出到日历 |
| 排班 | 鼠标 pointer 拖拽、`elementFromPoint` 反查落点 | 长按拖拽 + 几何反算落点（行高累计 / 列宽换算） |
| 改时长 | 拖卡片左右边缘 | 块两端 18px 拉伸手柄；详情弹层里也可选开始时间与时长 |
| 取消排班 | 拖回待办面板 | 拖到计划卡片下方出现的「取消排班」条，或详情里「退回待办」 |
| 虚拟滚动 | 手写虚拟窗口 | `ListView.builder` 天然只渲染可视区 |
| 横向滚动 | 原生横向滚动条 | 自绘横向偏移 + 惯性减速（与纵向滚动同屏共存） |

数据协议、只读保护、300ms 推送合并、3s 断线重试、409 冲突按条目合并、删除标记 30 天 TTL 等行为与网页版完全一致，
两端可同时连同一个服务端互相同步。

## 说明

- `tdesign_flutter` 目前是 `1.0.0-alpha.1` 预发布版，个别组件 API 与官方文档可能不一致；
  本项目已按该版本实际源码对齐（`TThemeBuilder` 双主题、`TText` / `TButton` / `TStepper` 的 `ValueChanged<num>` 等）。
- 组件缺失时（如时间轴网格）按 TDesign token（`context.tTheme`）自绘，保证与组件同一套视觉。
- `sort_child_properties_last` 这条 lint 已关闭：TDesign 组件里 icon / child / onPressed 三段并列时按业务可读性排列。
