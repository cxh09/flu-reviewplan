import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plaza_data.dart';
import '../models/todo.dart';
import 'app_ui.dart';

/// 从底部滑出的待办清单面板。
///
/// 长按卡片拖到日历上任意位置即可排班；把计划拖到面板上则退回待办。
class TodoPanelView extends StatelessWidget {
  const TodoPanelView({
    super.key,
    required this.todos,
    required this.draggingId,
    required this.onClose,
    required this.onScheduleTodo,
    required this.onRemoveTodo,
    required this.onGoPlaza,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final List<Todo> todos;

  /// 当前正在拖拽的条目 id（被拖起来的卡片压暗）
  final ValueListenable<String?> draggingId;

  final VoidCallback onClose;

  /// 「直接排班」：把这条待办直接排到今天的时间线上
  final ValueChanged<Todo> onScheduleTodo;
  final ValueChanged<Todo> onRemoveTodo;
  final VoidCallback onGoPlaza;

  final void Function(Todo todo, Offset globalPosition) onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

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
                  '待办清单',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                MetaChip(text: '${todos.length}'),
                const Spacer(),
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
                    '长按卡片拖到日历上任意位置即可排班；把计划拖到下方「取消排班」条可以退回待办。',
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
            child: todos.isEmpty
                ? EmptyHint(
                    text: '暂无待办，去日程广场添加',
                    actionText: '去日程广场',
                    onAction: onGoPlaza,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: todos.length,
                    itemBuilder: (context, index) {
                      final todo = todos[index];
                      return _TodoChip(
                        key: ValueKey<String>(todo.id),
                        todo: todo,
                        draggingId: draggingId,
                        onSchedule: () => onScheduleTodo(todo),
                        onRemove: () => onRemoveTodo(todo),
                        onDragStart: (position) => onDragStart(todo, position),
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

class _TodoChip extends StatelessWidget {
  const _TodoChip({
    super.key,
    required this.todo,
    required this.draggingId,
    required this.onSchedule,
    required this.onRemove,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Todo todo;
  final ValueListenable<String?> draggingId;
  final VoidCallback onSchedule;
  final VoidCallback onRemove;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final color = categoryColor(todo.category);

    return ValueListenableBuilder<String?>(
      valueListenable: draggingId,
      builder: (context, dragging, _) {
        final isDragging = dragging == todo.id;

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
                            todo.title,
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
                              MetaChip(text: todo.level),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${todo.category} · ${todo.duration} 分钟',
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
                    IconButton(
                      onPressed: onSchedule,
                      icon: const Icon(TIcons.calendar, size: 18),
                      color: theme.brandNormalColor,
                      tooltip: '直接排班',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(TIcons.delete, size: 18),
                      color: theme.textColorPlaceholder,
                      tooltip: '移出待办',
                      visualDensity: VisualDensity.compact,
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
