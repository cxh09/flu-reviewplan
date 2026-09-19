import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plaza_data.dart';
import '../models/plan.dart';
import '../utils/date_utils.dart';
import 'schedule_layout.dart';

/// 日历上的一个计划块。
///
/// - 宽度 = 时间跨度，横向按时间百分比定位；
/// - 左右两端各有 18px 的拉伸手柄（触屏下单边太窄按不准）；
/// - 订阅 [draggingId]：被拖起来时压暗并轻微放大，做出"提起"的手感。
class PlanBlockView extends StatelessWidget {
  const PlanBlockView({
    super.key,
    required this.block,
    required this.draggingId,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final PlanBlockLayout block;

  /// 当前正在拖拽的条目 id
  final ValueListenable<String?> draggingId;

  final ValueChanged<Plan> onTap;

  /// 起拖：把类型和起始全局坐标交给页面
  final void Function(Plan plan, DragKind kind, Offset globalPosition) onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final plan = block.plan;
    final color = categoryColor(plan.category);

    return Positioned(
      left: block.left,
      top: block.lane * ScheduleMetrics.laneHeight + 4,
      width: block.width,
      height: ScheduleMetrics.laneHeight - 8,
      child: ValueListenableBuilder<String?>(
        valueListenable: draggingId,
        builder: (context, dragging, _) {
          final isDragging = dragging == plan.id;

          return AnimatedScale(
            scale: isDragging ? 1.04 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: isDragging ? 0.35 : 1,
              duration: const Duration(milliseconds: 160),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(plan),
                onLongPressStart: (details) =>
                    onDragStart(plan, DragKind.planMove, details.globalPosition),
                onLongPressMoveUpdate: (details) =>
                    onDragUpdate(details.globalPosition),
                onLongPressEnd: (_) => onDragEnd(),
                onLongPressCancel: onDragEnd,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.bgColorContainer,
                    borderRadius: BorderRadius.circular(6),
                    border: Border(left: BorderSide(color: color, width: 3)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDragging ? 0.2 : 0.08),
                        blurRadius: isDragging ? 12 : 4,
                        offset: Offset(0, isDragging ? 4 : 1),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              plan.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: plan.done
                                    ? theme.textColorPlaceholder
                                    : theme.textColorPrimary,
                                decoration:
                                    plan.done ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${formatClock(block.start)} - ${formatClock(block.end)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.textColorPlaceholder,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildHandle(
                        context,
                        color: color,
                        alignLeft: true,
                        onStart: (position) =>
                            onDragStart(plan, DragKind.resizeStart, position),
                      ),
                      _buildHandle(
                        context,
                        color: color,
                        alignLeft: false,
                        onStart: (position) =>
                            onDragStart(plan, DragKind.resizeEnd, position),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 拉伸手柄：18px 宽的触摸区 + 中间一条 3px 的可见握把
  Widget _buildHandle(
    BuildContext context, {
    required Color color,
    required bool alignLeft,
    required ValueChanged<Offset> onStart,
  }) {
    return Positioned(
      left: alignLeft ? 0 : null,
      right: alignLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: 18,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) => onStart(details.globalPosition),
        onLongPressMoveUpdate: (details) => onDragUpdate(details.globalPosition),
        onLongPressEnd: (_) => onDragEnd(),
        onLongPressCancel: onDragEnd,
        child: Center(
          child: Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// 拖拽浮层里跟着手指走的小卡片。
///
/// 弹入的缩放由页面控制（每帧都要重建，放在这里的隐式动画会被反复重启）。
class DragPreviewCard extends StatelessWidget {
  const DragPreviewCard({super.key, required this.title, required this.category});

  final String title;
  final String category;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;

    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.bgColorContainer,
        borderRadius: BorderRadius.circular(theme.radiusDefault),
        border: Border.all(color: theme.brandNormalColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: categoryColor(category),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.textColorPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
