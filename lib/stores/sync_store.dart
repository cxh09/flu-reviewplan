import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/plan_data.dart';
import '../services/api_client.dart';
import '../services/merge.dart';
import '../services/tombstone_service.dart';
import '../utils/app_globals.dart';
import '../utils/debouncer.dart';
import '../utils/storage.dart';
import 'connection.dart';
import 'plan_store.dart';
import 'plaza_store.dart';

/// 一次同步操作的结果，供界面决定提示文案
class SyncResult {
  const SyncResult({
    required this.ok,
    this.rev,
    this.error,
    this.version,
    this.auth = false,
    this.unauthorized = false,
    this.stale = false,
    this.queued = false,
    this.busy = false,
    this.skipped = false,
    this.merged = false,
    this.conflict = false,
  });

  final bool ok;
  final int? rev;
  final String? error;

  /// 测试连接成功时服务端的版本号
  final String? version;

  /// 测试连接成功时服务端是否开启了令牌校验
  final bool auth;
  final bool unauthorized;
  final bool stale;
  final bool queued;
  final bool busy;
  final bool skipped;
  final bool merged;
  final bool conflict;
}

/// 云端数据源（对齐网页版 `src/stores/sync.js`）。
///
/// 全在线模式：计划 / 高考日期 / 日程广场合集都以服务端为唯一来源，本地不落盘。
/// - 启动后 [connect] 拉取云端快照填充；在线期间每 3 秒轮询版本号，
///   云端被其它设备改动时自动拉取合并（[pollOnce] / [pullRemote]）；
/// - 连不上时进入只读，并每隔几秒自动重试；
/// - 在线期间任何改动都会自动上传（合并 300ms 内的连续改动）；
/// - 版本冲突（409）不丢改动：拉云端快照与本地按条目（last-write-wins）合并后重推。
class SyncStore extends ChangeNotifier {
  SyncStore(this._planStore, this._plazaStore) {
    final persisted = _loadPersisted();
    _serverUrl = '${persisted['serverUrl'] ?? ''}';
    _accessToken = '${persisted['accessToken'] ?? ''}';
    _lastSyncAt = toInt(persisted['lastSyncAt'], 0);
    _rev = toInt(persisted['rev'], 0);
    _syncedUrl = '${persisted['lastSyncedUrl'] ?? ''}';

    // 拖拽 / 拉伸会以帧频改数据，攒一下再发，避免打满请求
    _pushDebouncer = Debouncer(const Duration(milliseconds: 300));

    _planStore.addListener(_handleDataChanged);
    _plazaStore.addListener(_handleDataChanged);

    // 在线期间定时轮询云端版本号，让其它设备的改动几秒内同步过来
    _pollTimer = Timer.periodic(const Duration(milliseconds: pollIntervalMs), (_) {
      unawaited(pollOnce());
    });
  }

  /// 改动合并窗口（毫秒）
  static const int pushDelayMs = 300;

  /// 断线重试间隔（毫秒）
  static const int retryDelayMs = 3000;

  /// 在线轮询间隔（毫秒）：查一次云端版本号，变了才拉整份，让多端秒级对齐
  static const int pollIntervalMs = 3000;

  final PlanStore _planStore;
  final PlazaStore _plazaStore;

  late final Debouncer _pushDebouncer;

  String _serverUrl = '';
  String _accessToken = '';
  int _lastSyncAt = 0;
  int _rev = 0;
  String _message = '';
  String _error = '';
  bool _testing = false;

  /// 最近一次与云端一致的数据指纹：内容没变就跳过推送
  String _syncedJson = '';

  /// 应用云端数据期间挂起推送，避免把自己的回写当成用户改动
  bool _suppressPush = false;

  bool _pushInFlight = false;
  bool _pushAgain = false;
  Timer? _retryTimer;
  Timer? _pollTimer;
  bool _connecting = false;

  /// 连接过程中又被要求连接（改了地址 / 点了刷新）：本次结束后补做一次
  bool _reconnectQueued = false;

  /// 上次同步成功时用的服务端地址。
  /// 本地缓存只有在地址没变时才和这个服务端对得上，这时才敢做合并，
  /// 否则会把上一个服务端的数据混进来。
  String _syncedUrl = '';

  // ---------- 对外状态 ----------

  String get serverUrl => _serverUrl;
  String get accessToken => _accessToken;
  int get lastSyncAt => _lastSyncAt;
  int get rev => _rev;
  String get message => _message;
  String get error => _error;
  bool get testing => _testing;

  String get normalizedUrl => normalizeServerUrl(_serverUrl);
  bool get configured => normalizedUrl.isNotEmpty;

  ConnectionStatus get connectionState => connectionManager.status;
  bool get isOnline => connectionManager.isOnline;

  String get connectionMessage {
    switch (connectionManager.status) {
      case ConnectionStatus.online:
        return '';
      case ConnectionStatus.connecting:
        return '正在连接服务端…';
      case ConnectionStatus.unconfigured:
        return '尚未配置服务端地址，当前为只读模式';
      case ConnectionStatus.offline:
        return _error.isNotEmpty
            ? '无法连接服务端（$_error），正在自动重试…当前为只读模式'
            : '无法连接服务端，正在自动重试…当前为只读模式';
    }
  }

  static Map<String, dynamic> _loadPersisted() {
    final data = AppStorage.readJson(AppStorage.serverKey);
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  void _persist() {
    AppStorage.writeJson(AppStorage.serverKey, <String, dynamic>{
      'serverUrl': _serverUrl,
      'accessToken': _accessToken,
      'lastSyncAt': _lastSyncAt,
      'rev': _rev,
      'lastSyncedUrl': _syncedUrl,
    });
  }

  void _setMessage(String message, {String error = ''}) {
    _message = message;
    _error = error;
    notifyListeners();
  }

  // ---------- 重试 ----------

  void _clearRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleRetry() {
    if (_retryTimer != null) return;
    _retryTimer = Timer(const Duration(milliseconds: retryDelayMs), () {
      _retryTimer = null;
      unawaited(connect());
    });
  }

  // ---------- 数据快照 ----------

  /// 当前完整快照（服务端存的就是它）
  Map<String, dynamic> buildPayload() => <String, dynamic>{
        ..._planStore.buildPayload(),
        'collections': _plazaStore.exportData(),
        'deleted': TombstoneService.active(),
      };

  /// 把云端数据写进各 store（不经过只读校验，这是权威数据）
  void _applyRemote(Map<String, dynamic> data) {
    _suppressPush = true;
    try {
      _planStore.applySnapshot(data);
      _plazaStore.importData(data['collections']);
    } finally {
      _suppressPush = false;
    }
  }

  void _handleDataChanged() {
    if (_suppressPush) return;
    schedulePush();
  }

  // ---------- 连接 ----------

  /// 连接并全量拉取云端数据。启动、断线重试、手动刷新都走这里。
  Future<SyncResult> connect() async {
    if (!configured) {
      connectionManager.setStatus(ConnectionStatus.unconfigured);
      notifyListeners();
      return const SyncResult(ok: false, error: '未配置服务端地址');
    }

    // 已有连接在进行：排队补做一次，避免「手动刷新」变成无声的空操作
    if (_connecting) {
      _reconnectQueued = true;
      return const SyncResult(ok: false, queued: true);
    }

    // 记下本次请求用的地址 / 令牌，回来时用它判断结果是否已经过期
    final url = normalizedUrl;
    final token = _accessToken;

    _pushDebouncer.cancel();
    _connecting = true;
    connectionManager.setStatus(ConnectionStatus.connecting);
    notifyListeners();

    try {
      final snapshot = await ApiClient.fetchSnapshot(url, token);

      // 请求期间地址或令牌被改过，这次结果作废（排队的那次会用新配置重连）
      if (url != normalizedUrl || token != _accessToken) {
        return const SyncResult(ok: false, stale: true);
      }

      final rawRemote = snapshot?['data'];
      Map<String, dynamic>? remote;
      if (rawRemote is Map) remote = rawRemote.cast<String, dynamic>();

      // 服务端还没有数据时保留本地缓存，等用户第一次改动再整体上传
      Map<String, dynamic>? merged;
      if (remote != null) {
        // 本地缓存还属于这个服务端时做一次合并，把上一次没推上去的改动救回来；
        // 换了服务端就直接以云端为准，免得把上一个服务端的数据混进来
        final canMerge = _syncedUrl == url && toNumber(snapshot?['rev'], 0) > 0;
        merged = canMerge ? mergeSnapshots(buildPayload(), remote) : remote;
        _applyRemote(merged);
      }

      _rev = toInt(snapshot?['rev'], 0);
      final updatedAt = snapshot?['updatedAt'];
      if (updatedAt != null) {
        _lastSyncAt =
            DateTime.tryParse('$updatedAt')?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
      }
      _syncedUrl = url;

      // 合并结果比云端新（本地有没推上去的改动）时，把指纹记成云端那份，
      // 让随后的 schedulePush 把合并结果补推上去
      final localJson = jsonEncode(buildPayload());
      final mergedJson = merged == null ? '' : jsonEncode(merged);
      _syncedJson = (mergedJson.isNotEmpty && mergedJson != localJson)
          ? jsonEncode(remote)
          : localJson;
      _persist();

      connectionManager.setStatus(ConnectionStatus.online);
      _setMessage('已连接云端 · 版本 $_rev');
      _clearRetry();
      schedulePush();
      return SyncResult(ok: true, rev: _rev);
    } on ApiException catch (err) {
      if (err.isUnauthorized) {
        // 令牌不对时重试没有意义，停掉自动重试，等用户去设置里改
        const message = '访问令牌不正确，请在「设置 → 服务端同步」里检查';
        connectionManager.setStatus(ConnectionStatus.offline);
        _setMessage(message, error: message);
        _clearRetry();
        return const SyncResult(ok: false, error: message, unauthorized: true);
      }

      connectionManager.setStatus(ConnectionStatus.offline);
      _setMessage(err.message, error: err.message);
      _scheduleRetry();
      return SyncResult(ok: false, error: err.message);
    } catch (err) {
      connectionManager.setStatus(ConnectionStatus.offline);
      _setMessage('$err', error: '$err');
      _scheduleRetry();
      return SyncResult(ok: false, error: '$err');
    } finally {
      _connecting = false;
      if (_reconnectQueued) {
        _reconnectQueued = false;
        // 放到下一个事件循环，避免和本次收尾逻辑交错
        scheduleMicrotask(() => unawaited(connect()));
      }
    }
  }

  /// 拉云端最新快照，与本地合并后应用（保留还没推上去的本地改动）。
  Future<void> pullRemote() async {
    if (_connecting || _pushInFlight) return;
    final url = normalizedUrl;
    final token = _accessToken;

    Map<String, dynamic>? snapshot;
    try {
      snapshot = await ApiClient.fetchSnapshot(url, token);
    } catch (_) {
      // 轮询期间的一次拉取失败不打紧，下一轮或 push 时会再触发重连
      return;
    }
    // 拉取期间改了地址 / 令牌，结果作废
    if (url != normalizedUrl || token != _accessToken) return;

    final rawRemote = snapshot?['data'];
    if (rawRemote is! Map) return;
    final remote = rawRemote.cast<String, dynamic>();

    // 按条目 last-write-wins 合并：云端更新的覆盖本地，本地没推上去的改动也保住
    final merged = mergeSnapshots(buildPayload(), remote);
    _applyRemote(merged);

    _rev = toInt(snapshot?['rev'], 0);
    final updatedAt = snapshot?['updatedAt'];
    if (updatedAt != null) {
      _lastSyncAt = DateTime.tryParse('$updatedAt')?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
    }
    _syncedUrl = url;
    // 指纹记成云端那份：本地若确有未推改动，下面的 schedulePush 会把合并结果补推
    _syncedJson = jsonEncode(remote);
    _persist();
    _setMessage('已同步云端 · 版本 $_rev');
    schedulePush();
  }

  /// 轮询一次：先查版本号，和云端对不上才拉整份快照
  Future<void> pollOnce() async {
    if (!isOnline || _connecting || _pushInFlight) return;
    try {
      final remote = await ApiClient.fetchRev(normalizedUrl, _accessToken);
      if (toInt(remote?['rev'], -1) != _rev) await pullRemote();
    } catch (_) {
      // 网络抖动 / 令牌问题：留给 push、retry 或下一轮处理
    }
  }

  /// 只探活 + 校验令牌，不改动本地数据
  Future<SyncResult> testConnection() async {
    if (!configured) return const SyncResult(ok: false, error: '未配置服务端地址');

    _testing = true;
    notifyListeners();
    try {
      final health = await ApiClient.fetchHealth(normalizedUrl, _accessToken);
      await ApiClient.fetchSnapshot(normalizedUrl, _accessToken);
      return SyncResult(
        ok: true,
        version: '${health?['version'] ?? ''}',
        auth: health?['auth'] == true,
      );
    } on ApiException catch (err) {
      return SyncResult(ok: false, error: err.message, unauthorized: err.isUnauthorized);
    } catch (err) {
      return SyncResult(ok: false, error: '$err');
    } finally {
      _testing = false;
      notifyListeners();
    }
  }

  // ---------- 推送 ----------

  void schedulePush() {
    if (_suppressPush || !isOnline) return;
    _pushDebouncer.run(() => unawaited(pushNow()));
  }

  /// 把当前数据上传到服务端。[force] 为 true 时不做冲突检测，直接覆盖云端。
  Future<SyncResult> pushNow({bool force = false}) async {
    if (!configured) return const SyncResult(ok: false, error: '未配置服务端地址');
    if (!force && !isOnline) return const SyncResult(ok: false, error: '当前离线');

    if (_pushInFlight) {
      _pushAgain = true;
      return const SyncResult(ok: false, busy: true);
    }

    final payload = buildPayload();
    final json = jsonEncode(payload);
    // 内容与云端一致就不发请求，避免因为拉取后的归一化产生无意义的写入
    if (!force && json == _syncedJson) return const SyncResult(ok: true, skipped: true);

    _pushInFlight = true;
    try {
      final result = await ApiClient.putSnapshot(
        normalizedUrl,
        _accessToken,
        payload,
        force ? null : _rev,
      );

      _rev = toInt(result?['rev'], _rev);
      final updatedAt = result?['updatedAt'];
      _lastSyncAt = updatedAt == null
          ? DateTime.now().millisecondsSinceEpoch
          : (DateTime.tryParse('$updatedAt')?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch);
      _syncedJson = json;
      connectionManager.setStatus(ConnectionStatus.online);
      _setMessage('已同步到云端 · 版本 $_rev');
      _persist();
      return SyncResult(ok: true, rev: _rev);
    } on ApiException catch (err) {
      if (err.isConflict) return resolveConflict();

      final message = err.isUnauthorized
          ? '访问令牌不正确，请在「设置 → 服务端同步」里检查'
          : err.message;
      connectionManager.setStatus(ConnectionStatus.offline);
      _setMessage(message, error: message);
      // 令牌错误重试也没用，等用户改配置；其它错误才自动重连
      if (err.isUnauthorized) {
        _clearRetry();
      } else {
        _scheduleRetry();
      }
      return SyncResult(ok: false, error: message, unauthorized: err.isUnauthorized);
    } catch (err) {
      final message = '$err';
      connectionManager.setStatus(ConnectionStatus.offline);
      _setMessage(message, error: message);
      _scheduleRetry();
      return SyncResult(ok: false, error: message);
    } finally {
      _pushInFlight = false;
      if (_pushAgain) {
        _pushAgain = false;
        schedulePush();
      }
    }
  }

  /// 版本冲突：拉云端最新快照，与本地按条目合并后重新上传。
  /// 这样两端各改各的都不会互相覆盖；一直合不上才退化为「以云端为准」。
  Future<SyncResult> resolveConflict([int attempt = 0]) async {
    final url = normalizedUrl;
    final token = _accessToken;

    try {
      final snapshot = await ApiClient.fetchSnapshot(url, token);
      final rawRemote = snapshot?['data'];

      // 云端空着：直接把本地整份推上去
      if (rawRemote is! Map) {
        final local = buildPayload();
        final result = await ApiClient.putSnapshot(url, token, local, null);
        _rev = toInt(result?['rev'], _rev);
        _lastSyncAt = DateTime.now().millisecondsSinceEpoch;
        _syncedJson = jsonEncode(local);
        _syncedUrl = url;
        _persist();
        notifyListeners();
        return SyncResult(ok: true, rev: _rev);
      }

      final remote = rawRemote.cast<String, dynamic>();
      final merged = mergeSnapshots(buildPayload(), remote);
      _applyRemote(merged);

      final result = await ApiClient.putSnapshot(url, token, merged, toInt(snapshot?['rev'], 0));
      _rev = toInt(result?['rev'], _rev);
      _lastSyncAt = DateTime.now().millisecondsSinceEpoch;
      _syncedJson = jsonEncode(merged);
      _syncedUrl = url;
      _persist();
      notifyListeners();

      showInfoToast('数据被其它设备改过，已自动合并双方改动');
      return SyncResult(ok: true, rev: _rev, merged: true);
    } catch (error) {
      // 合并期间又有别的设备提交，再合一次
      if (error is ApiException && error.isConflict && attempt < 2) {
        return resolveConflict(attempt + 1);
      }

      // 实在合不上：退回「以云端为准」，至少保证两端一致
      final pulled = await connect();
      if (pulled.ok) showWarningToast('数据冲突，已同步为云端最新');
      return SyncResult(ok: false, conflict: true, error: '$error');
    }
  }

  /// 用本地当前数据强制覆盖云端（不做冲突检测）
  Future<SyncResult> overwriteCloud() {
    _pushDebouncer.cancel();
    return pushNow(force: true);
  }

  /// 应用切到后台 / 关闭前，把还没发出去的改动补发出去
  void flushPending() {
    if (!_pushDebouncer.isPending) return;
    _pushDebouncer.flush(() => unawaited(pushNow()));
  }

  // ---------- 配置 ----------

  void setServerUrl(String value) {
    final next = value.trim();
    if (next == _serverUrl) return;

    _serverUrl = next;
    // 换了服务端，版本号、指纹都作废；本地缓存也不再属于新地址，不能参与合并
    _rev = 0;
    _syncedUrl = '';
    _syncedJson = '';
    _message = '';
    _error = '';
    _persist();
    _clearRetry();
    _pushDebouncer.cancel();
    notifyListeners();

    if (next.isNotEmpty) {
      unawaited(connect());
    } else {
      connectionManager.setStatus(ConnectionStatus.unconfigured);
    }
  }

  void setAccessToken(String value) {
    final next = value.trim();
    if (next == _accessToken) return;

    _accessToken = next;
    _persist();
    _clearRetry();
    notifyListeners();
    // 令牌可能填错了，换完立刻重连一次
    if (_serverUrl.isNotEmpty) unawaited(connect());
  }

  void resetConfig() {
    _serverUrl = '';
    _accessToken = '';
    _rev = 0;
    _lastSyncAt = 0;
    _syncedUrl = '';
    _syncedJson = '';
    _message = '';
    _error = '';
    _clearRetry();
    _pushDebouncer.cancel();
    connectionManager.setStatus(ConnectionStatus.unconfigured);
    _persist();
    notifyListeners();
  }

  /// 从云端刷新：丢弃本地缓存重新拉取
  Future<SyncResult> refreshFromCloud() async {
    _syncedUrl = '';
    return connect();
  }

  @override
  void dispose() {
    _planStore.removeListener(_handleDataChanged);
    _plazaStore.removeListener(_handleDataChanged);
    _pushDebouncer.dispose();
    _retryTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}
