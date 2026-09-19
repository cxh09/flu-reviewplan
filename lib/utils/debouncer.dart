import 'dart:async';
import 'dart:ui' show VoidCallback;

/// 简单的防抖器：拖拽 / 拉伸会以帧频改数据，攒一下再落盘或上传，
/// 避免每一帧都做一次全量序列化 / 网络请求。
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  bool get isPending => _timer?.isActive ?? false;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// 取消已排队的任务并立刻执行
  void flush(VoidCallback action) {
    cancel();
    action();
  }

  void dispose() => cancel();
}
