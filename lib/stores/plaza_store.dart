import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/plaza_data.dart';
import '../models/collection.dart';
import '../models/plaza_item.dart';
import '../services/tombstone_service.dart';
import '../utils/id_utils.dart';
import '../utils/url_utils.dart';
import 'connection.dart';

/// 日程广场（对齐网页版 `src/stores/plaza.js`）：
/// 用户自己维护的「系列合集」以及合集里的日程。
///
/// 全在线模式：数据以云端为唯一来源，本地不落盘；初始为空，
/// 启动后由 SyncStore 拉取云端快照填充，改动经其推回云端。
class PlazaStore extends ChangeNotifier {
  /// 广场从空开始，等云端快照填充
  List<Collection> _collections = <Collection>[];

  /// 合集列表（只读视图，不做拷贝）——`List.unmodifiable` 会把整份列表复制一遍，
  /// 而页面每帧都可能读它
  List<Collection> get collections =>
      UnmodifiableListView<Collection>(_collections);

  int get collectionCount => _collections.length;

  int get itemCount =>
      _collections.fold<int>(0, (sum, collection) => sum + collection.items.length);

  Collection? findCollection(String id) {
    for (final collection in _collections) {
      if (collection.id == id) return collection;
    }
    return null;
  }

  PlazaItem? findItem(String collectionId, String itemId) {
    final collection = findCollection(collectionId);
    if (collection == null) return null;
    for (final item in collection.items) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  // ---------- 合集 ----------

  Collection? addCollection({
    required String name,
    String category = '通用',
    String desc = '',
    String color = '',
  }) {
    if (!ensureWritable()) return null;

    final collection = Collection.fromJson(<String, dynamic>{
      'id': createId('col'),
      'name': name,
      'category': category,
      'desc': desc,
      'color': color.isEmpty ? (kCategoryColors[category] ?? kCollectionColors.first) : color,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    _collections = <Collection>[..._collections, collection];
    _touch();
    return collection;
  }

  Collection? updateCollection(
    String id, {
    String? name,
    String? desc,
    String? category,
    String? color,
  }) {
    if (!ensureWritable()) return null;

    final index = _collections.indexWhere((collection) => collection.id == id);
    if (index == -1) return null;

    final collection = _collections[index];
    final trimmedName = (name ?? '').trim();
    _collections = <Collection>[..._collections];
    _collections[index] = collection.copyWith(
      name: trimmedName.isEmpty ? collection.name : trimmedName,
      desc: desc ?? '',
      category: (category == null || category.isEmpty) ? collection.category : category,
      color: (color == null || color.isEmpty) ? collection.color : color,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _touch();
    return _collections[index];
  }

  void removeCollection(String id) {
    if (!ensureWritable()) return;
    TombstoneService.markDeleted(id);
    _collections = _collections.where((collection) => collection.id != id).toList();
    _touch();
  }

  // ---------- 合集里的日程 ----------

  PlazaItem? addItem(
    String collectionId, {
    required String title,
    String? category,
    String? level,
    int? duration,
    String? desc,
    String? link,
  }) {
    if (!ensureWritable()) return null;

    final index = _collections.indexWhere((collection) => collection.id == collectionId);
    if (index == -1) return null;

    final collection = _collections[index];
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = PlazaItem.fromJson(<String, dynamic>{
      'id': createId('item'),
      'title': title,
      'category': (category == null || category.isEmpty) ? collection.category : category,
      'level': (level == null || level.isEmpty) ? '基础' : level,
      'duration': (duration == null || duration == 0) ? kDefaultItemDuration : duration,
      'desc': desc ?? '',
      'link': sanitizeLink(link),
      'updatedAt': now,
    });

    _collections = <Collection>[..._collections];
    _collections[index] = collection.copyWith(
      items: <PlazaItem>[...collection.items, item],
      updatedAt: now,
    );
    _touch();
    return item;
  }

  PlazaItem? updateItem(
    String collectionId,
    String itemId, {
    String? title,
    String? category,
    String? level,
    int? duration,
    String? desc,
    String? link,
  }) {
    if (!ensureWritable()) return null;

    final collectionIndex =
        _collections.indexWhere((collection) => collection.id == collectionId);
    if (collectionIndex == -1) return null;

    final collection = _collections[collectionIndex];
    final itemIndex = collection.items.indexWhere((item) => item.id == itemId);
    if (itemIndex == -1) return null;

    final item = collection.items[itemIndex];
    final trimmedTitle = (title ?? '').trim();
    final next = item.copyWith(
      title: trimmedTitle.isEmpty ? item.title : trimmedTitle,
      category: (category == null || category.isEmpty) ? item.category : category,
      level: (level == null || level.isEmpty) ? item.level : level,
      duration: (duration == null || duration == 0) ? item.duration : duration,
      desc: desc ?? item.desc,
      link: link == null ? item.link : sanitizeLink(link),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final items = <PlazaItem>[...collection.items];
    items[itemIndex] = next;
    _collections = <Collection>[..._collections];
    _collections[collectionIndex] = collection.copyWith(
      items: items,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _touch();
    return next;
  }

  void removeItem(String collectionId, String itemId) {
    if (!ensureWritable()) return;

    final index = _collections.indexWhere((collection) => collection.id == collectionId);
    if (index == -1) return;

    final collection = _collections[index];
    TombstoneService.markDeleted(itemId);
    _collections = <Collection>[..._collections];
    _collections[index] = collection.copyWith(
      items: collection.items.where((item) => item.id != itemId).toList(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _touch();
  }

  // ---------- 数据管理 ----------

  List<Map<String, dynamic>> exportData() =>
      _collections.map((collection) => collection.toJson()).toList();

  /// 同步用的快照片段
  Map<String, dynamic> buildPayload() => <String, dynamic>{
        'collections': exportData(),
      };

  /// 导入：老备份里没有 collections 时保持现有数据不变
  void importData(Object? list) {
    if (list is! List) return;
    _collections = list
        .whereType<Map>()
        .map((item) => Collection.fromJson(item.cast<String, dynamic>()))
        .toList();
    _touch();
  }

  void resetAll() {
    if (!ensureWritable()) return;
    // 清空也是一次删除：不记标记的话，另一端残留的副本会把合集带回来
    TombstoneService.markDeletedMany(
      _collections.expand<String>(
        (collection) => <String>[
          collection.id,
          ...collection.items.map((item) => item.id),
        ],
      ),
    );
    _collections = <Collection>[];
    _touch();
  }

  /// 数据变了：通知界面刷新（改动由 SyncStore 监听并推送到云端）
  void _touch() {
    notifyListeners();
  }
}
