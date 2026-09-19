import 'dart:async';
import 'dart:ui' show VoidCallback;

/// 带防抖的持久化写入器（对齐网页版 `src/utils/persist.js` 的 `createDebouncedWriter`）。
///
/// 拖拽 / 拉伸这类操作会以帧频修改数据，如果每次变更都全量序列化并写本地存储，
/// 主线程会被拖垮。这里统一按 [delay] 合并写入；应用切后台时再 [flush] 一次，
/// 避免「改完立刻退出丢数据」。
class PersistWriter {
  PersistWriter(this.delay, this.writeNow);

  final Duration delay;
  final VoidCallback writeNow;

  Timer? _timer;

  /// 调度一次写入，[delay] 内的重复调用会被合并
  void schedule() {
    if (_timer?.isActive ?? false) return;
    _timer = Timer(delay, () {
      _timer = null;
      writeNow();
    });
  }

  /// 立即落盘（有挂起的写入才执行）
  void flush() {
    if (!(_timer?.isActive ?? false)) return;
    _timer!.cancel();
    _timer = null;
    writeNow();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
