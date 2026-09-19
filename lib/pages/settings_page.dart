import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plan_data.dart';
import '../stores/app_store.dart';
import '../stores/connection.dart';
import '../stores/plan_store.dart';
import '../stores/plaza_store.dart';
import '../stores/sync_store.dart';
import '../utils/app_globals.dart';
import '../utils/date_utils.dart';
import '../widgets/app_ui.dart';
import '../widgets/date_picker_sheet.dart';

/// 设置（对应网页版 `views/SettingsView.vue`）：
/// 高考日期、主题、服务端同步、数据导入导出清空。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _appVersion = '0.1.0';

  late final TextEditingController _serverController;
  late final TextEditingController _tokenController;

  /// 当前进行中的操作：test | reconnect | overwrite，用于按钮 loading
  String _action = '';

  @override
  void initState() {
    super.initState();
    final syncStore = context.read<SyncStore>();
    _serverController = TextEditingController(text: syncStore.serverUrl);
    _tokenController = TextEditingController(text: syncStore.accessToken);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// 把输入框里的地址 / 令牌落到 store（内容没变时 store 内部会跳过）
  void _applyInputs() {
    final syncStore = context.read<SyncStore>();
    syncStore.setServerUrl(_serverController.text);
    syncStore.setAccessToken(_tokenController.text);
  }

  void _saveServerConfig() {
    _applyInputs();
    final configured = context.read<SyncStore>().configured;
    showSuccessToast(configured ? '已保存配置，正在连接服务端…' : '已清除服务端地址，应用进入只读模式');
  }

  Future<void> _testConnection() async {
    _applyInputs();
    final syncStore = context.read<SyncStore>();
    if (!syncStore.configured) {
      showWarningToast('请先填写服务端地址');
      return;
    }

    setState(() => _action = 'test');
    final result = await syncStore.testConnection();
    if (!mounted) return;
    setState(() => _action = '');

    if (result.ok) {
      final auth = result.auth ? ' · 已开启令牌校验' : '';
      showSuccessToast('连接成功 · 服务端 v${result.version}$auth');
    } else {
      showErrorToast(result.unauthorized ? '访问令牌不正确' : '连接失败：${result.error}');
    }
  }

  /// 重新连接并按云端数据覆盖本地
  Future<void> _reconnect() async {
    _applyInputs();
    final syncStore = context.read<SyncStore>();
    if (!syncStore.configured) {
      showWarningToast('请先填写服务端地址');
      return;
    }

    setState(() => _action = 'reconnect');
    final result = await syncStore.connect();
    if (!mounted) return;
    setState(() => _action = '');

    if (result.ok) {
      showSuccessToast('已同步为云端最新数据');
    } else if (result.queued) {
      // 上一次连接还没结束，已经排队重连，不再报错
      showInfoToast('正在连接中，稍后会自动重试');
    } else if (!result.stale) {
      showErrorToast(result.unauthorized ? '访问令牌不正确' : '连接失败：${result.error}');
    }
  }

  Future<void> _refreshFromCloud() async {
    _applyInputs();
    if (!context.read<SyncStore>().configured) {
      showWarningToast('请先填写服务端地址');
      return;
    }

    final confirmed = await showAppConfirm(
      context,
      title: '从云端刷新',
      content: '会丢弃本地缓存，用云端的待办清单、排版计划、高考日期与广场合集重新覆盖。确认继续？',
      confirmText: '确认刷新',
    );
    if (!confirmed || !mounted) return;
    await _reconnect();
  }

  Future<void> _clearServerConfig() async {
    final confirmed = await showAppConfirm(
      context,
      title: '清除服务端配置',
      content: '只会清除本机保存的服务端地址与访问令牌，云端数据不会被删除。清除后应用进入只读模式。',
      confirmText: '清除',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    context.read<SyncStore>().resetConfig();
    _serverController.clear();
    _tokenController.clear();
    showSuccessToast('已清除服务端配置');
  }

  // ---------- 数据导出 / 导入 / 清空 ----------

  Future<void> _exportJson() async {
    final planStore = context.read<PlanStore>();
    final plazaStore = context.read<PlazaStore>();

    // version 直接沿用 planStore 的 DATA_VERSION，避免两处各写一个版本号导致对不上
    final payload = <String, dynamic>{
      ...(jsonDecode(planStore.exportData()) as Map).cast<String, dynamic>(),
      'collections': plazaStore.exportData(),
    };

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/reviewplan-${todayKey()}.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          fileNameOverrides: <String>['reviewplan-${todayKey()}.json'],
          subject: '复习清单数据备份',
        ),
      );
      if (mounted) showSuccessToast('数据已导出为 JSON 文件');
    } catch (error) {
      if (mounted) showErrorToast('导出失败：$error');
    }
  }

  Future<void> _importJson() async {
    final planStore = context.read<PlanStore>();
    final plazaStore = context.read<PlazaStore>();
    final syncStore = context.read<SyncStore>();

    if (!isOnline) {
      showWarningToast('未连接服务端，导入需要在线才能写回云端');
      return;
    }

    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择备份文件',
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
      if (picked == null || picked.path == null) return;

      final text = await File(picked.path!).readAsString();
      final data = jsonDecode(text);
      if (data is! Map) throw const FormatException('数据格式不正确');

      final map = data.cast<String, dynamic>();
      // 先落到本地视图，再整体覆盖云端
      planStore.importData(map);
      plazaStore.importData(map['collections']);

      if (!mounted) return;
      setState(() => _action = 'overwrite');
      final result = await syncStore.overwriteCloud();
      if (!mounted) return;
      setState(() => _action = '');

      if (result.ok) {
        showSuccessToast('数据导入成功，并已写入云端');
      } else {
        showErrorToast('导入的数据没能写入云端：${result.error ?? '请稍后重试'}');
      }
    } catch (error) {
      if (mounted) showErrorToast('导入失败：$error');
    }
  }

  Future<void> _confirmReset() async {
    final planStore = context.read<PlanStore>();
    final plazaStore = context.read<PlazaStore>();
    final syncStore = context.read<SyncStore>();

    final confirmed = await showAppConfirm(
      context,
      title: '确认清空所有数据',
      content: '会同时清空云端与本地的待办清单、排版计划、日程广场合集，并把高考日期恢复为默认值。该操作不可撤销，建议先导出备份。',
      confirmText: '确认清空',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    if (!isOnline) {
      showWarningToast('未连接服务端，暂时无法清空');
      return;
    }

    planStore.resetAll();
    plazaStore.resetAll();
    setState(() => _action = 'overwrite');
    final result = await syncStore.overwriteCloud();
    if (!mounted) return;
    setState(() => _action = '');

    if (result.ok) {
      showSuccessToast('本地与云端数据已清空');
    } else {
      showErrorToast('清空失败：${result.error ?? '请稍后重试'}');
    }
  }

  Future<void> _pickGaokaoDate() async {
    final planStore = context.read<PlanStore>();
    final picked = await showDatePickerSheet(
      context,
      currentKey: planStore.gaokaoDate,
      title: '高考首日',
    );
    if (picked == null || !mounted) return;
    planStore.setGaokaoDate(picked);
  }

  void _restoreDefaultDate() {
    context.read<PlanStore>().setGaokaoDate(kDefaultGaokaoDate);
    if (isOnline) showSuccessToast('已恢复默认高考日期');
  }

  String _formatDateTime(int timestamp) {
    if (timestamp <= 0) return '尚未同步';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)} '
        '${pad(date.hour)}:${pad(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final appStore = context.watch<AppStore>();
    final planStore = context.watch<PlanStore>();
    final plazaStore = context.watch<PlazaStore>();
    final syncStore = context.watch<SyncStore>();

    final days = planStore.daysToGaokao;
    final daysText = days > 0
        ? '距离高考还有 $days 天'
        : days == 0
            ? '今天就是高考'
            : '高考已经过去 ${-days} 天';

    Color connectionColor;
    String connectionLabel;
    switch (syncStore.connectionState) {
      case ConnectionStatus.online:
        connectionColor = theme.successNormalColor;
        connectionLabel = '已连接';
      case ConnectionStatus.connecting:
        connectionColor = theme.brandNormalColor;
        connectionLabel = '连接中';
      case ConnectionStatus.unconfigured:
        connectionColor = theme.warningNormalColor;
        connectionLabel = '未配置';
      case ConnectionStatus.offline:
        connectionColor = theme.errorNormalColor;
        connectionLabel = '连接失败';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        // ---------- 高考设置 ----------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHeader(title: '高考设置'),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '高考首日',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '倒计时会以这一天为终点计算',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textColorPlaceholder,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _restoreDefaultDate,
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickGaokaoDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(theme.radiusDefault),
                    border: Border.all(color: theme.componentBorderColor),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(TIcons.calendar, size: 18, color: theme.textColorSecondary),
                      const SizedBox(width: 8),
                      Text(
                        planStore.gaokaoDate,
                        style: const TextStyle(fontSize: 15),
                      ),
                      const Spacer(),
                      Icon(
                        TIcons.chevron_right,
                        size: 18,
                        color: theme.textColorPlaceholder,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(theme.radiusLarge),
                  gradient: LinearGradient(
                    colors: <Color>[
                      theme.brandNormalColor.withValues(alpha: 0.10),
                      theme.successNormalColor.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        colors: <Color>[Color(0xFF0052D9), Color(0xFF00A870)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(rect),
                      blendMode: BlendMode.srcIn,
                      child: Text(
                        '${days < 0 ? 0 : days}',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(daysText, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(
                            '${formatCN(planStore.gaokaoDate)} · ${weekdayCN(planStore.gaokaoDate)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textColorPlaceholder,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 复习偏好 ----------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHeader(title: '复习偏好'),
              const SizedBox(height: 6),
              Text(
                '深色模式适合夜间复习',
                style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _ThemeButton(
                      label: '浅色',
                      icon: TIcons.sunny,
                      selected: !appStore.isDark,
                      onPressed: () => appStore.setTheme('light'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ThemeButton(
                      label: '深色',
                      icon: TIcons.moon,
                      selected: appStore.isDark,
                      onPressed: () => appStore.setTheme('dark'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 服务端同步 ----------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHeader(title: '服务端同步'),
              const SizedBox(height: 12),
              if (!syncStore.configured)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.warningLightColor,
                    borderRadius: BorderRadius.circular(theme.radiusDefault),
                  ),
                  child: Text(
                    '还没有配置服务端地址。应用采用全在线模式：数据以云端为准，必须连上服务端才能编辑，未配置时只能查看本地缓存。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.7,
                      color: theme.warningNormalColor,
                    ),
                  ),
                ),
              AppFormField(
                label: '服务端地址',
                tip: '例如 http://localhost:3000 或 http://192.168.1.10:3000',
                child: TInput(
                  controller: _serverController,
                  hintText: 'http://localhost:3000',
                  inputType: TextInputType.url,
                  onEditingComplete: _applyInputs,
                ),
              ),
              AppFormField(
                label: '访问令牌',
                tip: '需要手动填写，与服务端 ACCESS_TOKEN 保持一致',
                child: TInput(
                  controller: _tokenController,
                  hintText: '可选',
                  obscureText: true,
                  onEditingComplete: _applyInputs,
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.bgColorSecondaryContainer,
                  borderRadius: BorderRadius.circular(theme.radiusDefault),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: connectionColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(theme.radiusSmall),
                          ),
                          child: Text(
                            connectionLabel,
                            style: TextStyle(fontSize: 11, color: connectionColor),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            syncStore.message.isEmpty ? '等待操作' : syncStore.message,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textColorSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '最后同步：${_formatDateTime(syncStore.lastSyncAt)}',
                      style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '数据版本：${syncStore.rev}',
                      style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.fill,
                    colorScheme: TButtonColorScheme.primary,
                    child: const Text('保存配置'),
                    onPressed: syncStore.configured ? _saveServerConfig : null,
                  ),
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.outline,
                    colorScheme: TButtonColorScheme.primary,
                    icon: const Icon(TIcons.link, size: 15),
                    child: Text(_action == 'test' ? '测试中…' : '测试连接'),
                    onPressed: (!syncStore.configured || _action.isNotEmpty)
                        ? null
                        : _testConnection,
                  ),
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.outline,
                    colorScheme: TButtonColorScheme.defaultTheme,
                    icon: const Icon(TIcons.cloud_download, size: 15),
                    child: Text(_action == 'reconnect' ? '刷新中…' : '从云端刷新'),
                    onPressed: (!syncStore.configured || _action.isNotEmpty)
                        ? null
                        : _refreshFromCloud,
                  ),
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.text,
                    colorScheme: TButtonColorScheme.danger,
                    child: const Text('清除配置'),
                    onPressed: _action.isEmpty ? _clearServerConfig : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '全在线模式：待办清单、排版计划、高考日期与日程广场合集都以服务端为准，任何改动都会立即上传；连不上服务端时进入只读并每 3 秒自动重试；多端同时改动会按条目自动合并（同一条谁的时间戳新谁生效），只有在合不上时才退回以云端为准。本机只保留一份用于首屏快速渲染的缓存。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.75,
                  color: theme.textColorPlaceholder,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 数据管理 ----------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHeader(title: '数据管理'),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: <Widget>[
                  _StatTile(label: '待办清单', value: '${planStore.todoCount}'),
                  _StatTile(label: '排版计划', value: '${planStore.planCount}'),
                  _StatTile(label: '广场日程', value: '${plazaStore.itemCount}'),
                  _StatTile(label: '完成率', value: '${planStore.completionRate}%'),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.outline,
                    colorScheme: TButtonColorScheme.primary,
                    icon: const Icon(TIcons.download, size: 15),
                    child: const Text('导出数据'),
                    onPressed: _action.isEmpty ? _exportJson : null,
                  ),
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.outline,
                    colorScheme: TButtonColorScheme.defaultTheme,
                    icon: const Icon(TIcons.upload, size: 15),
                    child: Text(_action == 'overwrite' ? '写入中…' : '导入数据'),
                    onPressed: _action.isEmpty ? _importJson : null,
                  ),
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.outline,
                    colorScheme: TButtonColorScheme.danger,
                    icon: const Icon(TIcons.refresh, size: 15),
                    child: const Text('清空数据'),
                    onPressed: _action.isEmpty ? _confirmReset : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '导出的就是当前云端数据，可作为额外备份；导入会把文件内容直接覆盖写入云端；清空会同时清掉云端数据。日常使用时数据始终由服务端保存，本机副本仅用于首屏渲染。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.75,
                  color: theme.textColorPlaceholder,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 关于 ----------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHeader(title: '关于'),
              const SizedBox(height: 12),
              _AboutRow(label: '应用名称', value: '复习清单'),
              _AboutRow(label: '版本', value: _appVersion),
              _AboutRow(label: '技术栈', value: 'Flutter · Provider · TDesign'),
              _AboutRow(label: 'UI 组件库', value: 'TDesign Flutter'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 主题切换按钮
class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.brandLightColor : theme.bgColorSecondaryContainer,
          borderRadius: BorderRadius.circular(theme.radiusDefault),
          border: Border.all(
            color: selected ? theme.brandNormalColor : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: selected ? theme.brandNormalColor : theme.textColorSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? theme.brandNormalColor : theme.textColorSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统计小卡
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.bgColorSecondaryContainer,
        borderRadius: BorderRadius.circular(theme.radiusDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder),
          ),
        ],
      ),
    );
  }
}

/// 关于页的一行
class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: theme.textColorSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
