import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plaza_data.dart';
import '../models/collection.dart';
import '../models/plaza_item.dart';
import 'app_ui.dart';

/// 从底部滑出的日程广场面板。
///
/// 只做浏览与排班：长按某条日程拖到日历上任意位置即可排班；
/// 点右侧日历图标直接把它排到今天。取消中间的「待办清单」缓冲，看到即可排。
class PlazaPanelView extends StatelessWidget {
  const PlazaPanelView({
    super.key,
    required this.collections,
    required this.draggingId,
    required this.onClose,
    required this.onGoPlaza,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final List<Collection> collections;

  /// 当前正在拖拽的条目 id（被拖起来的卡片压暗）
  final ValueListenable<String?> draggingId;

  final VoidCallback onClose;

  final VoidCallback onGoPlaza;

  final void Function(PlazaItem item, Offset globalPosition) onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  bool get _isEmpty => collections.every((collection) => collection.items.isEmpty);

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.bgColorContainer,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(theme.radiusExtraLarge),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.componentBorderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(
              children: <Widget>[
                const Text(
                  '日程广场',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                MetaChip(text: '${collections.length} 个合集'),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onGoPlaza,
                  child: Row(
                    children: <Widget>[
                      Text(
                        '管理合集',
                        style: TextStyle(fontSize: 12, color: theme.brandNormalColor),
                      ),
                      Icon(
                        TIcons.chevron_right,
                        size: 16,
                        color: theme.brandNormalColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Icon(TIcons.close, size: 20, color: theme.textColorPlaceholder),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                Icon(TIcons.drag_move, size: 14, color: theme.textColorPlaceholder),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '长按日程拖到日历上任意位置即可排班；拖完可以在日程表上继续调时间。',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: theme.textColorSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isEmpty
                ? SingleChildScrollView(
                    child: EmptyHint(
                      text: '日程广场还没有可排的日程\n去广场新建合集、往里加日程',
                      actionText: '去日程广场',
                      onAction: onGoPlaza,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: collections.length,
                    itemBuilder: (context, index) {
                      final collection = collections[index];
                      if (collection.items.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _CollectionSection(
                        collection: collection,
                        draggingId: draggingId,
                        onDragStart: onDragStart,
                        onDragUpdate: onDragUpdate,
                        onDragEnd: onDragEnd,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CollectionSection extends StatelessWidget {
  const _CollectionSection({
    required this.collection,
    required this.draggingId,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Collection collection;
  final ValueListenable<String?> draggingId;
  final void Function(PlazaItem item, Offset globalPosition) onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
            child: Row(
              children: <Widget>[
                Container(
                  width: 4,
                  height: 14,
                  decoration: BoxDecoration(
                    color: collection.displayColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.textColorPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${collection.items.length} 条',
                  style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder),
                ),
              ],
            ),
          ),
          ...collection.items.map(
            (item) => _PlazaChip(
              key: ValueKey<String>(item.id),
              item: item,
              draggingId: draggingId,
              onDragStart: (position) => onDragStart(item, position),
              onDragUpdate: onDragUpdate,
              onDragEnd: onDragEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlazaChip extends StatelessWidget {
  const _PlazaChip({
    super.key,
    required this.item,
    required this.draggingId,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final PlazaItem item;
  final ValueListenable<String?> draggingId;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final color = categoryColor(item.category);

    return ValueListenableBuilder<String?>(
      valueListenable: draggingId,
      builder: (context, dragging, _) {
        final isDragging = dragging == item.id;

        return AnimatedScale(
          scale: isDragging ? 1.02 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: isDragging ? 0.35 : 1,
            duration: const Duration(milliseconds: 160),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (details) => onDragStart(details.globalPosition),
              onLongPressMoveUpdate: (details) => onDragUpdate(details.globalPosition),
              onLongPressEnd: (_) => onDragEnd(),
              onLongPressCancel: onDragEnd,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                decoration: BoxDecoration(
                  color: theme.bgColorContainer,
                  borderRadius: BorderRadius.circular(theme.radiusDefault),
                  border: Border.all(color: theme.componentStrokeColor, width: 0.5),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 3,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: <Widget>[
                              MetaChip(text: item.level),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${item.category} · ${item.duration} 分钟',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textColorPlaceholder,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
