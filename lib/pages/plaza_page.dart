import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/plaza_data.dart';
import '../models/collection.dart';
import '../models/plaza_item.dart';
import '../stores/connection.dart';
import '../stores/plaza_store.dart';
import '../utils/app_globals.dart';
import '../utils/app_tabs.dart';
import '../utils/responsive.dart';
import '../widgets/app_ui.dart';
import '../widgets/collection_dialog.dart';
import '../widgets/plaza_item_dialog.dart';

/// 日程广场（对应网页版 `views/PlazaView.vue`）：
/// 自己维护的系列合集 → 往里添加日程 → 单条或整组一键加入待办清单。
class PlazaPage extends StatefulWidget {
  const PlazaPage({super.key});

  @override
  State<PlazaPage> createState() => _PlazaPageState();
}

class _PlazaPageState extends State<PlazaPage> {
  /// 默认先展示前几条，剩下的点「展开」再看
  static const int previewCount = 5;

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedIds = <String>{};

  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _trimmedKeyword => _keyword.trim().toLowerCase();

  bool _includes(String? text, String keyword) =>
      (text ?? '').toLowerCase().contains(keyword);

  bool _matchCollection(Collection collection, String keyword) =>
      _includes(collection.name, keyword) ||
      _includes(collection.desc, keyword) ||
      _includes(collection.category, keyword);

  bool _matchItem(PlazaItem item, String keyword) =>
      _includes(item.title, keyword) ||
      _includes(item.desc, keyword) ||
      _includes(item.category, keyword);

  /// 页面上直接展示的合集：有关键词时只留下命中的合集与命中的日程
  List<Collection> _visibleCollections(PlazaStore plazaStore) {
    final keyword = _trimmedKeyword;
    if (keyword.isEmpty) return plazaStore.collections;

    return plazaStore.collections
        .map((collection) {
          final items = _matchCollection(collection, keyword)
              ? collection.items
              : collection.items.where((item) => _matchItem(item, keyword)).toList();
          return collection.copyWith(items: items);
        })
        // 名称命中的空合集也要留下来，否则搜不到它
        .where((collection) =>
            collection.items.isNotEmpty || _matchCollection(collection, keyword))
        .toList();
  }

  List<PlazaItem> _visibleItems(Collection collection) {
    if (_expandedIds.contains(collection.id) || _trimmedKeyword.isNotEmpty) {
      return collection.items;
    }
    return collection.items.take(previewCount).toList();
  }

  Future<void> _openCollectionSheet(
    PlazaStore plazaStore, {
    Collection? collection,
  }) async {
    final result = await showCollectionSheet(context, collection: collection);
    if (result == null || !mounted) return;

    if (collection == null) {
      final created = plazaStore.addCollection(
        name: result.name,
        category: result.category,
        desc: result.desc,
        color: result.color,
      );
      if (created == null) return;
      showSuccessToast('合集已创建');
    } else {
      // 只读模式下 store 会拒绝写入并给出提示，这里不再报「已更新」
      if (plazaStore.updateCollection(
            collection.id,
            name: result.name,
            category: result.category,
            desc: result.desc,
            color: result.color,
          ) ==
          null) {
        return;
      }
      showSuccessToast('合集已更新');
    }
  }

  Future<void> _removeCollection(PlazaStore plazaStore, Collection collection) async {
    final confirmed = await showAppConfirm(
      context,
      title: '删除系列合集',
      content:
          '确认删除「${collection.name}」？里面的 ${collection.items.length} 条日程会一并删除，已经排到日程表的日程不受影响。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    plazaStore.removeCollection(collection.id);
    if (isOnline) showSuccessToast('合集已删除');
  }

  Future<void> _openItemSheet(
    PlazaStore plazaStore, {
    required String collectionId,
    PlazaItem? item,
  }) async {
    final result = await showPlazaItemSheet(context, item: item);
    if (result == null || !mounted) return;

    if (item == null) {
      if (plazaStore.addItem(
            collectionId,
            title: result.title,
            duration: result.duration,
            link: result.link,
          ) ==
          null) {
        return;
      }
      // 新加的日程在末尾，展开合集免得看起来「没加上」
      setState(() => _expandedIds.add(collectionId));
      showSuccessToast('已加入合集');
    } else {
      if (plazaStore.updateItem(
            collectionId,
            item.id,
            title: result.title,
            duration: result.duration,
            link: result.link,
          ) ==
          null) {
        return;
      }
      showSuccessToast('日程已更新');
    }
  }

  Future<void> _removeItem(
    PlazaStore plazaStore,
    Collection collection,
    PlazaItem item,
  ) async {
    final confirmed = await showAppConfirm(
      context,
      title: '删除日程',
      content: '确认从「${collection.name}」中删除「${item.title}」？',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    plazaStore.removeItem(collection.id, item.id);
    if (isOnline) showSuccessToast('日程已删除');
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final plazaStore = context.watch<PlazaStore>();
    final collections = _visibleCollections(plazaStore);
    final searching = _trimmedKeyword.isNotEmpty;

    return AdaptivePage(
      child: ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '日程广场',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '每个系列合集下面直接列出它的日程：在这里新建合集、往里加日程，再回到日程表点“＋”把它们拖到时间线上排班。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.75,
                  color: theme.textColorSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TButton(
                      size: TButtonSize.small,
                      variant: TButtonVariant.fill,
                      colorScheme: TButtonColorScheme.primary,
                      icon: const Icon(TIcons.add, size: 16),
                      child: const Text('新建合集'),
                      onPressed: () => _openCollectionSheet(plazaStore),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TButton(
                      size: TButtonSize.small,
                      variant: TButtonVariant.outline,
                      colorScheme: TButtonColorScheme.defaultTheme,
                      icon: const Icon(TIcons.chevron_right, size: 16),
                      iconPosition: TButtonIconPosition.right,
                      child: const Text('去日程表排班'),
                      onPressed: () => goToTab(AppTab.schedule),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 搜索框：图标与输入文字放在居中的 Row 里，保证两者垂直居中对齐。
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.bgColorSecondaryContainer,
                  borderRadius: BorderRadius.circular(theme.radiusDefault),
                  border: Border.all(
                    color: theme.componentStrokeColor,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      TIcons.search,
                      size: 18,
                      color: theme.textColorPlaceholder,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textColorPrimary,
                        ),
                        onChanged: (value) => setState(() => _keyword = value),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: '搜索合集名称或日程内容',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: theme.textColorPlaceholder,
                          ),
                        ),
                      ),
                    ),
                    if (_keyword.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _keyword = '');
                        },
                        child: Icon(
                          TIcons.close_circle,
                          size: 18,
                          color: theme.textColorPlaceholder,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: <Widget>[
                  Text(
                    '${plazaStore.collectionCount} 个系列合集',
                    style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
                  ),
                  Text(
                    '${plazaStore.itemCount} 条日程',
                    style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (collections.isEmpty)
          AppCard(
            child: EmptyHint(
              text: searching ? '没有找到匹配的日程，换个关键词试试' : '还没有任何系列合集\n新建一个合集，把同一类复习日程收在一起',
              actionText: searching ? null : '新建合集',
              onAction: searching ? null : () => _openCollectionSheet(plazaStore),
            ),
          )
        else
          ...collections.map(
            (collection) => _CollectionCard(
              collection: collection,
              items: _visibleItems(collection),
              expanded: _expandedIds.contains(collection.id),
              forceExpanded: searching,
              onToggleExpand: () {
                setState(() {
                  if (!_expandedIds.remove(collection.id)) {
                    _expandedIds.add(collection.id);
                  }
                });
              },
              onCreateItem: () =>
                  _openItemSheet(plazaStore, collectionId: collection.id),
              onEditCollection: () =>
                  _openCollectionSheet(plazaStore, collection: collection),
              onRemoveCollection: () => _removeCollection(plazaStore, collection),
              onEditItem: (item) => _openItemSheet(
                plazaStore,
                collectionId: collection.id,
                item: item,
              ),
              onRemoveItem: (item) => _removeItem(plazaStore, collection, item),
            ),
          ),
      ],
      ),
    );
  }
}

/// 一个合集一块：标题头 + 操作 + 下面的日程列表
class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.collection,
    required this.items,
    required this.expanded,
    required this.forceExpanded,
    required this.onToggleExpand,
    required this.onCreateItem,
    required this.onEditCollection,
    required this.onRemoveCollection,
    required this.onEditItem,
    required this.onRemoveItem,
  });

  final Collection collection;
  final List<PlazaItem> items;
  final bool expanded;
  final bool forceExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCreateItem;
  final VoidCallback onEditCollection;
  final VoidCallback onRemoveCollection;
  final void Function(PlazaItem item) onEditItem;
  final void Function(PlazaItem item) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final color = collection.displayColor;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              MetaChip(text: collection.category, color: color),
              const SizedBox(width: 8),
              Text(
                '${collection.items.length} 条日程',
                style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            collection.desc.isEmpty ? '这个合集还没有写简介' : collection.desc,
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: theme.textColorSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              TButton(
                size: TButtonSize.extraSmall,
                variant: TButtonVariant.outline,
                colorScheme: TButtonColorScheme.defaultTheme,
                icon: const Icon(TIcons.add, size: 14),
                child: const Text('添加日程'),
                onPressed: onCreateItem,
              ),
              TButton(
                size: TButtonSize.extraSmall,
                variant: TButtonVariant.text,
                colorScheme: TButtonColorScheme.defaultTheme,
                icon: const Icon(TIcons.edit, size: 16),
                onPressed: onEditCollection,
              ),
              TButton(
                size: TButtonSize.extraSmall,
                variant: TButtonVariant.text,
                colorScheme: TButtonColorScheme.danger,
                icon: const Icon(TIcons.delete, size: 16),
                onPressed: onRemoveCollection,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (collection.items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.bgColorSecondaryContainer,
                borderRadius: BorderRadius.circular(theme.radiusDefault),
              ),
              child: Text(
                '这个合集还没有日程，点上面的「添加日程」加一条',
                style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
              ),
            )
          else ...<Widget>[
            ...items.map(
              (item) => _ItemRow(
                item: item,
                onEdit: () => onEditItem(item),
                onRemove: () => onRemoveItem(item),
              ),
            ),
            if (!forceExpanded && collection.items.length > _PlazaPageState.previewCount)
              Align(
                alignment: Alignment.centerLeft,
                child: TButton(
                  size: TButtonSize.extraSmall,
                  variant: TButtonVariant.text,
                  colorScheme: TButtonColorScheme.primary,
                  child: Text(
                    expanded
                        ? '收起'
                        : '展开剩余 ${collection.items.length - items.length} 条',
                  ),
                  icon: Icon(expanded ? TIcons.chevron_up : TIcons.chevron_down, size: 16),
                  iconPosition: TButtonIconPosition.right,
                  onPressed: onToggleExpand,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 把分钟数格式化成「X 小时 Y 分」，不足 1 小时只显示分钟
String formatDuration(int minutes) {
  if (minutes <= 0) return '';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '预估 $m 分钟';
  return m == 0 ? '预估 $h 小时' : '预估 $h 小时 $m 分';
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onEdit,
    required this.onRemove,
  });

  final PlazaItem item;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  Future<void> _openLink() async {
    final uri = Uri.tryParse(item.link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final color = categoryColor(item.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.bgColorSecondaryContainer,
        borderRadius: BorderRadius.circular(theme.radiusDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(top: 2),
                decoration:
                    BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (item.desc.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        item.desc,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: theme.textColorSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        MetaChip(text: item.category, color: color),
                        MetaChip(
                          text: item.level,
                          color: theme.textColorSecondary,
                        ),
                        MetaChip(text: formatDuration(item.duration)),
                        if (item.link.isNotEmpty)
                          GestureDetector(
                            onTap: _openLink,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  TIcons.link,
                                  size: 12,
                                  color: theme.brandNormalColor,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '打开链接',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.brandNormalColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Spacer(),
              TButton(
                size: TButtonSize.extraSmall,
                variant: TButtonVariant.text,
                colorScheme: TButtonColorScheme.defaultTheme,
                icon: const Icon(TIcons.edit, size: 15),
                onPressed: onEdit,
              ),
              TButton(
                size: TButtonSize.extraSmall,
                variant: TButtonVariant.text,
                colorScheme: TButtonColorScheme.danger,
                icon: const Icon(TIcons.delete, size: 15),
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
