import '../data/plan_data.dart';
import '../utils/debouncer.dart';
import '../utils/storage.dart';

/// 删除标记：条目被删掉时记一笔 { id, at }（对齐网页版 `src/utils/tombstone.js`）。
///
/// 合并两端快照时，如果没有删除标记，一端删掉的条目会被另一端残留的副本复活。
/// 标记要跟着本地缓存一起持久化：否则「删除后推送失败 → 重启应用」会丢掉删除记录。
class TombstoneService {
  TombstoneService._();

  static final Debouncer _writer = Debouncer(const Duration(milliseconds: 250));

  static List<Map<String, dynamic>> _tombstones = _load();

  static List<Map<String, dynamic>> _load() {
    final raw = AppStorage.readJson(AppStorage.tombstonesKey);
    return _normalize(raw);
  }

  static List<Map<String, dynamic>> _normalize(Object? list) {
    if (list is! List) return <Map<String, dynamic>>[];
    return list
        .whereType<Map>()
        .map((entry) => <String, dynamic>{
              'id': '${entry['id'] ?? ''}',
              'at': toNumber(entry['at'], 0).round(),
            })
        .where((entry) => '${entry['id']}'.isNotEmpty && (entry['at'] as int) > 0)
        .toList();
  }

  /// 记录一次删除；同一 id 只保留最新的删除时间
  static void markDeleted(String id, [int? atMs]) {
    if (id.isEmpty) return;
    final at = atMs ?? DateTime.now().millisecondsSinceEpoch;

    final index = _tombstones.indexWhere((entry) => entry['id'] == id);
    if (index == -1) {
      _tombstones.add(<String, dynamic>{'id': id, 'at': at});
    } else if (at > (_tombstones[index]['at'] as int)) {
      _tombstones[index] = <String, dynamic>{'id': id, 'at': at};
    }

    _writer.run(_persist);
  }

  /// 批量记录删除（清空数据时用）
  static void markDeletedMany(Iterable<String> ids) {
    for (final id in ids) {
      markDeleted(id);
    }
  }

  /// 用云端快照里的删除标记替换本地（同步层应用远端数据时调用）
  static void setTombstones(Object? list) {
    if (list is! List) return;
    _tombstones = _normalize(list);
    _writer.run(_persist);
  }

  /// 取还在有效期内的删除标记（随快照上传的那份）
  static List<Map<String, dynamic>> active([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return _tombstones
        .where((entry) => now - (entry['at'] as int) <= kTombstoneTtl)
        .map((entry) => <String, dynamic>{'id': entry['id'], 'at': entry['at']})
        .toList();
  }

  static void _persist() {
    AppStorage.writeJson(AppStorage.tombstonesKey, _tombstones);
  }
}
