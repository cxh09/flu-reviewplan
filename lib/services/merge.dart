import '../data/plan_data.dart';

// 快照合并：按「条目」做 last-write-wins（对齐网页版 `src/utils/merge.js`）。
//
// 服务端保存的是一整份快照，两端先后上传时先到的一侧会拿到 409。
// 如果直接把后到的一侧丢掉，那 300ms 窗口里的改动就没了；
// 这里改成把本地和云端两份快照按 id 逐条合并，谁的时间戳新谁生效，
// 这样两端各改各的都不会互相覆盖。
//
// 删除必须靠删除标记（tombstone）：只按 id 合并的话，
// 一端删掉的条目会被另一端残留的副本「复活」，所以每个删除动作都要记一笔 { id, at }。

/// 条目最后一次修改的时间；历史数据没有这个字段时按 0 处理（视为最旧）
int entityTime(Object? entity) {
  if (entity is! Map) return 0;
  final value = toNumber(entity['updatedAt'], 0);
  return value > 0 ? value.round() : 0;
}

Map<String, Map<String, dynamic>> _indexById(Object? list) {
  final map = <String, Map<String, dynamic>>{};
  if (list is List) {
    for (final item in list) {
      if (item is Map) {
        final entry = item.cast<String, dynamic>();
        final id = '${entry['id'] ?? ''}';
        if (id.isNotEmpty) map[id] = entry;
      }
    }
  }
  return map;
}

/// 同 id 的两条记录取新的那条。
/// 时间戳相同（含历史数据都是 0）时以云端为准，保证两端结果一致。
Map<String, dynamic>? _pickNewer(
  Map<String, dynamic>? local,
  Map<String, dynamic>? remote,
) {
  if (local == null) return remote;
  if (remote == null) return local;
  return entityTime(local) > entityTime(remote) ? local : remote;
}

/// 合并两端的删除标记，同一 id 取更晚的删除时间，并回收过期的
List<Map<String, dynamic>> mergeTombstones(
  Object? localList,
  Object? remoteList, [
  int? nowMs,
]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final map = <String, int>{};

  void collect(Object? list) {
    if (list is! List) return;
    for (final item in list) {
      if (item is! Map) continue;
      final id = '${item['id'] ?? ''}';
      if (id.isEmpty) continue;
      final at = toNumber(item['at'], 0).round();
      if (at <= 0) continue;
      if (now - at > kTombstoneTtl) continue;
      final prev = map[id];
      if (prev == null || at > prev) map[id] = at;
    }
  }

  collect(localList);
  collect(remoteList);

  return map.entries
      .map((entry) => <String, dynamic>{'id': entry.key, 'at': entry.value})
      .toList();
}

/// 合并一组按 id 唯一的条目（待办 / 计划 / 合集 / 合集里的日程通用）。
/// 删除时间晚于最后一次修改的条目会被真正丢弃。
List<Map<String, dynamic>> mergeEntities(
  Object? localList,
  Object? remoteList,
  Map<String, int> tombstoneAt,
) {
  final localMap = _indexById(localList);
  final remoteMap = _indexById(remoteList);
  final merged = <Map<String, dynamic>>[];

  final ids = <String>{...localMap.keys, ...remoteMap.keys};
  for (final id in ids) {
    final winner = _pickNewer(localMap[id], remoteMap[id]);
    if (winner == null) continue;

    final deletedAt = tombstoneAt[id];
    if (deletedAt != null && deletedAt > entityTime(winner)) continue;

    merged.add(winner);
  }

  return merged;
}

List<Map<String, dynamic>> _mergeCollections(
  Object? localList,
  Object? remoteList,
  Map<String, int> tombstoneAt,
) {
  final localMap = _indexById(localList);
  final remoteMap = _indexById(remoteList);

  return mergeEntities(localList, remoteList, tombstoneAt).map((collection) {
    // 合集本身按 LWW 决定归属，里面的日程再单独合一次：
    // 两端各往同一个合集里加日程时，两边的条目都要留下
    final local = localMap['${collection['id']}'];
    final remote = remoteMap['${collection['id']}'];
    return <String, dynamic>{
      ...collection,
      'items': mergeEntities(local?['items'], remote?['items'], tombstoneAt),
    };
  }).toList();
}

/// 高考日期是个标量，单独用它的修改时间比
Map<String, dynamic> _mergeGaokaoDate(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  final localAt = toNumber(local['gaokaoDateUpdatedAt'], 0).round();
  final remoteAt = toNumber(remote['gaokaoDateUpdatedAt'], 0).round();
  final localDate = local['gaokaoDate'] is String ? local['gaokaoDate'] as String : '';
  final remoteDate = remote['gaokaoDate'] is String ? remote['gaokaoDate'] as String : '';

  if (remoteDate.isEmpty) {
    return <String, dynamic>{'gaokaoDate': localDate, 'gaokaoDateUpdatedAt': localAt};
  }
  if (localDate.isEmpty) {
    return <String, dynamic>{'gaokaoDate': remoteDate, 'gaokaoDateUpdatedAt': remoteAt};
  }

  return localAt > remoteAt
      ? <String, dynamic>{'gaokaoDate': localDate, 'gaokaoDateUpdatedAt': localAt}
      : <String, dynamic>{'gaokaoDate': remoteDate, 'gaokaoDateUpdatedAt': remoteAt};
}

/// 合并本地与云端两份快照。
///
/// [local] / [remote] 都是快照 JSON；[nowMs] 用于回收过期删除标记。
Map<String, dynamic> mergeSnapshots(
  Map<String, dynamic> local,
  Map<String, dynamic> remote, [
  int? nowMs,
]) {
  final deleted = mergeTombstones(local['deleted'], remote['deleted'], nowMs);
  final tombstoneAt = <String, int>{
    for (final entry in deleted) '${entry['id']}': toNumber(entry['at'], 0).round(),
  };

  return <String, dynamic>{
    ..._mergeGaokaoDate(local, remote),
    'todos': mergeEntities(local['todos'], remote['todos'], tombstoneAt),
    'plans': mergeEntities(local['plans'], remote['plans'], tombstoneAt),
    'collections': _mergeCollections(local['collections'], remote['collections'], tombstoneAt),
    'deleted': deleted,
  };
}
