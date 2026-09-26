import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plan_data.dart';
import '../stores/connection.dart';
import '../stores/plan_store.dart';
import '../stores/sync_store.dart';
import '../utils/app_globals.dart';
import '../utils/date_utils.dart';
import '../utils/responsive.dart';
import '../widgets/app_ui.dart';
import '../widgets/date_picker_sheet.dart';

/// 设置页：高考日期 + 服务端同步。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _serverController;
  late final TextEditingController _tokenController;

  /// 个人资料（分享署名）：用户名输入 + 待保存的头像 dataURL 及其解码字节
  late final TextEditingController _nameController;
  final FocusNode _nameFocusNode = FocusNode();
  String? _avatarDataUrl;
  Uint8List? _avatarBytes;

  /// 上一次从 store（含联网拉取）同步到输入框的资料值：
  /// 只有当 store 里的资料变化（多为联网拉到）时才回填，避免打断正在输入的用户。
  String _syncedProfileName = '';
  String _syncedProfileAvatar = '';

  /// 当前进行中的操作：test | reconnect，用于按钮 loading
  String _action = '';

  @override
  void initState() {
    super.initState();
    final syncStore = context.read<SyncStore>();
    _serverController = TextEditingController(text: syncStore.serverUrl);
    _tokenController = TextEditingController(text: syncStore.accessToken);
    final planStore = context.read<PlanStore>();
    _nameController = TextEditingController(text: planStore.profileName);
    _syncedProfileName = planStore.profileName;
    _syncedProfileAvatar = planStore.profileAvatar;
    _applyAvatar(planStore.profileAvatar.isEmpty ? null : planStore.profileAvatar);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  /// 把输入框里的地址 / 令牌落到 store
  void _applyInputs() {
    final syncStore = context.read<SyncStore>();
    syncStore.setServerUrl(_serverController.text);
    syncStore.setAccessToken(_tokenController.text);
  }

  void _saveServerConfig() {
    _applyInputs();
    final configured = context.read<SyncStore>().configured;
    showSuccessToast(configured ? '已保存，正在连接…' : '已清除地址，进入只读模式');
  }

  Future<void> _testConnection() async {
    _applyInputs();
    final syncStore = context.read<SyncStore>();
    if (!syncStore.configured) {
      showWarningToast('请先填写地址');
      return;
    }

    setState(() => _action = 'test');
    final result = await runWithLoading(
      () => syncStore.testConnection(),
      message: '测试中…',
    );
    if (!mounted) return;
    setState(() => _action = '');

    if (result.ok) {
      final auth = result.auth ? ' · 已校验' : '';
      showSuccessToast('连接成功 v${result.version}$auth');
    } else {
      showErrorToast(result.unauthorized ? '令牌不正确' : '连接失败：${result.error}');
    }
  }

  Future<void> _reconnect() async {
    _applyInputs();
    final syncStore = context.read<SyncStore>();
    if (!syncStore.configured) {
      showWarningToast('请先填写地址');
      return;
    }

    setState(() => _action = 'reconnect');
    final result = await runWithLoading(
      () => syncStore.connect(),
      message: '连接中…',
    );
    if (!mounted) return;
    setState(() => _action = '');

    if (result.ok) {
      showSuccessToast('已同步云端数据');
    } else if (result.queued) {
      showInfoToast('连接中，稍后自动重试');
    } else if (!result.stale) {
      showErrorToast(result.unauthorized ? '令牌不正确' : '连接失败：${result.error}');
    }
  }

  Future<void> _refreshFromCloud() async {
    _applyInputs();
    if (!context.read<SyncStore>().configured) {
      showWarningToast('请先填写地址');
      return;
    }

    final confirmed = await showAppConfirm(
      context,
      title: '从云端刷新',
      content: '会丢弃本地缓存，用云端的排版计划、高考日期与广场合集重新覆盖。确认继续？',
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
    showSuccessToast('已清除配置');
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
    if (isOnline) showSuccessToast('已恢复默认日期');
  }

  // ---------- 个人资料（分享署名） ----------

  /// 把头像 dataURL 存入待保存字段，并解码出预览用的字节
  void _applyAvatar(String? dataUrl) {
    _avatarDataUrl = (dataUrl == null || dataUrl.isEmpty) ? null : dataUrl;
    if (_avatarDataUrl == null || !_avatarDataUrl!.contains(',')) {
      _avatarBytes = null;
      return;
    }
    try {
      _avatarBytes = base64Decode(_avatarDataUrl!.substring(_avatarDataUrl!.indexOf(',') + 1));
    } catch (_) {
      _avatarBytes = null;
    }
  }

  Future<void> _pickAvatar() async {
    final XFile? file;
    try {
      // 用 pickImage 的 maxWidth/maxHeight/imageQuality 原生压缩，避免引入 image 包
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 320,
        maxHeight: 320,
        imageQuality: 80,
      );
    } catch (_) {
      showErrorToast('无法打开相册');
      return;
    }
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    // 压缩后仍异常大就拒绝，避免快照膨胀
    if (dataUrl.length > 200 * 1024) {
      showErrorToast('头像过大，请换一张较小的图片');
      return;
    }
    setState(() => _applyAvatar(dataUrl));
  }

  void _saveProfile() {
    context.read<PlanStore>().setProfile(
          name: _nameController.text,
          avatar: _avatarDataUrl,
        );
    if (isOnline) showSuccessToast('资料已保存');
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
    final planStore = context.watch<PlanStore>();
    final syncStore = context.watch<SyncStore>();

    // 个人资料随快照同步：联网拉到新资料时回填输入框；
    // 用户名框正在编辑（有焦点）时不打断，头像直接跟随远端。
    if (planStore.profileName != _syncedProfileName) {
      _syncedProfileName = planStore.profileName;
      if (!_nameFocusNode.hasFocus) _nameController.text = planStore.profileName;
    }
    if (planStore.profileAvatar != _syncedProfileAvatar) {
      _syncedProfileAvatar = planStore.profileAvatar;
      _applyAvatar(planStore.profileAvatar.isEmpty ? null : planStore.profileAvatar);
    }

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

    return AdaptivePage(
      child: ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: <Widget>[
        // ---------- 个人资料 ----------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHeader(title: '个人资料'),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.bgColorSecondaryContainer,
                        border: Border.all(color: theme.componentBorderColor),
                        image: _avatarBytes == null
                            ? null
                            : DecorationImage(
                                image: MemoryImage(_avatarBytes!),
                                fit: BoxFit.cover,
                              ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _avatarBytes == null
                          ? Center(
                              child: Icon(
                                TIcons.user,
                                size: 28,
                                color: theme.textColorPlaceholder,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AppTextInput(
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                          hintText: '用户名（用于分享页署名）',
                          onEditingComplete: _saveProfile,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '分享页顶部会显示“由 用户名 分享”。用户名与头像会随数据同步到各端，离线时无法保存。',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.6,
                            color: theme.textColorPlaceholder,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                    child: const Text('保存资料'),
                    onPressed: _saveProfile,
                  ),
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.outline,
                    colorScheme: TButtonColorScheme.defaultTheme,
                    icon: const Icon(TIcons.image, size: 15),
                    child: const Text('选择头像'),
                    onPressed: _pickAvatar,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

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
                child: AppTextInput(
                  controller: _serverController,
                  hintText: 'http://localhost:3000',
                  inputType: TextInputType.url,
                  onEditingComplete: _applyInputs,
                ),
              ),
              AppFormField(
                label: '访问令牌',
                tip: '需要手动填写，与服务端 ACCESS_TOKEN 保持一致',
                child: AppTextInput(
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
                '全在线模式：排版计划、高考日期与日程广场合集都以服务端为准，任何改动都会立即上传；连不上服务端时进入只读并每 3 秒自动重试；多端同时改动会按条目自动合并。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.75,
                  color: theme.textColorPlaceholder,
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }
}
