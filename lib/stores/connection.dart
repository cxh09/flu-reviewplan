import 'package:flutter/foundation.dart';

import '../utils/app_globals.dart';

/// 全局连接状态（全在线模式，对齐网页版 `src/utils/connection.js`）。
///
/// 应用以云端数据为唯一数据源，只有「已连上服务端」时才允许编辑，其余状态一律只读：
/// - [ConnectionStatus.connecting]   正在连接（启动 / 重试中）
/// - [ConnectionStatus.online]       已连上，可编辑，改动会自动同步
/// - [ConnectionStatus.offline]      连不上（网络问题或令牌错误），只读并自动重试
/// - [ConnectionStatus.unconfigured] 还没填服务端地址，只读
enum ConnectionStatus { connecting, online, offline, unconfigured }

/// 放在独立单例里（而不是 SyncStore 内部），是为了让 plan / plaza store
/// 能直接读取状态又不会和 sync store 形成循环依赖。
class ConnectionManager extends ChangeNotifier {
  ConnectionManager._();

  static final ConnectionManager instance = ConnectionManager._();

  /// 提示节流间隔：拖拽会以帧频触发写操作，不能每次都弹提示
  static const int warnIntervalMs = 2500;

  ConnectionStatus _status = ConnectionStatus.connecting;
  int _lastWarnAt = 0;

  ConnectionStatus get status => _status;
  bool get isOnline => _status == ConnectionStatus.online;
  bool get isReadOnly => !isOnline;

  void setStatus(ConnectionStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  /// 只读状态下尝试编辑时给出提示
  void warnReadOnly() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastWarnAt < warnIntervalMs) return;
    _lastWarnAt = now;

    showWarningToast(
      _status == ConnectionStatus.unconfigured
          ? '尚未配置服务端地址，请先到「设置 → 服务端同步」完成配置'
          : '未连接服务端，当前为只读模式，正在自动重试…',
    );
  }

  /// 所有写操作的统一入口：在线才放行
  bool ensureWritable() {
    if (isOnline) return true;
    warnReadOnly();
    return false;
  }
}

ConnectionManager get connectionManager => ConnectionManager.instance;

bool get isOnline => connectionManager.isOnline;

bool get isReadOnly => connectionManager.isReadOnly;

/// @returns 是否允许写入
bool ensureWritable() => connectionManager.ensureWritable();
