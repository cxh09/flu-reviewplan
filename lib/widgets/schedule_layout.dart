import '../data/plan_data.dart';
import '../models/plan.dart';

/// 日程表网格的固定尺寸与拖拽常量
class ScheduleMetrics {
  ScheduleMetrics._();

  /// 左侧日期列宽
  static const double dateWidth = 66;

  /// 每个整点列的宽度
  static const double hourWidth = 92;

  /// 同一时间段重叠时每层的高度
  static const double laneHeight = 60;

  /// 拉伸 / 落点吸附的粒度（分钟）
  static const int snapMinutes = 15;
  static const double snapHours = snapMinutes / 60;

  /// 时间轴总宽（18 个整点列）
  static const double contentWidth = hourWidth * kHoursCount;

  /// 拖到边缘多少像素内开始自动滚动，以及最大速度（像素 / 帧）
  static const double edgeSize = 72;
  static const double edgeSpeed = 16;
}

/// 拖拽类型
enum DragKind {
  /// 从待办清单拖到时间线上排班
  todo,

  /// 拖动日历上的计划块换时间
  planMove,

  /// 拖左边缘：改开始时间（结束时间不变）
  resizeStart,

  /// 拖右边缘：改时长
  resizeEnd,
}

extension DragKindExtension on DragKind {
  bool get isResize => this == DragKind.resizeStart || this == DragKind.resizeEnd;
}

/// 高亮用的落点单元格（日期 + 整点）。
///
/// 单独抽出来是因为它挂在 [ValueNotifier] 上：只有值真正变化时才通知，
/// 手指在一个格子里移动不会触发任何重建。
class DropCell {
  const DropCell(this.date, this.hour);

  final String date;
  final int hour;

  bool containsHour(double startHour) => startHour >= hour && startHour < hour + 1;

  @override
  bool operator ==(Object other) =>
      other is DropCell && other.date == date && other.hour == hour;

  @override
  int get hashCode => Object.hash(date, hour);
}

/// 落点：某个日期的某个时间（已按 15 分钟吸附）
class DropTarget {
  const DropTarget({required this.date, required this.startHour});

  final String date;
  final double startHour;

  DropCell get cell => DropCell(date, startHour.floor());
}

/// 一条计划在某一天的排版结果
class PlanBlockLayout {
  const PlanBlockLayout({
    required this.plan,
    required this.lane,
    required this.start,
    required this.end,
  });

  final Plan plan;

  /// 第几层（同一时间段重叠时上下错开）
  final int lane;
  final double start;
  final double end;

  /// 横向位置：按时间轴百分比铺开，宽度就是时长
  double get left =>
      (start - kFirstHour) / kHoursCount * ScheduleMetrics.contentWidth;

  double get width =>
      (end - start) / kHoursCount * ScheduleMetrics.contentWidth;
}

/// 一天的分层排版结果
class DayLayout {
  const DayLayout({
    required this.signature,
    required this.lanes,
    required this.blocks,
  });

  static const DayLayout empty =
      DayLayout(signature: '', lanes: 1, blocks: <PlanBlockLayout>[]);

  /// 布局签名，用来判断能不能复用上一次算出来的结果
  final String signature;

  /// 这一天占用的层数
  final int lanes;
  final List<PlanBlockLayout> blocks;

  double get height => lanes * ScheduleMetrics.laneHeight;
}

/// 布局签名。
///
/// 包含 `updatedAt`：计划是替换而不是原地改的，
/// 只比 id / 时间的话标题、科目这些改动不会触发重新排版。
String dayLayoutSignature(List<Plan> items) {
  if (items.isEmpty) return '';
  return items
      .map((plan) => '${plan.id}:${plan.startHour}:${plan.duration}:${plan.updatedAt}')
      .join('|');
}

/// 按天分层：同一时间段重叠的计划上下错开，互不遮挡。
///
/// [items] 需要按开始时间升序（`PlanStore.plansOfDate` 已保证）。
DayLayout computeDayLayout(List<Plan> items, String signature) {
  if (items.isEmpty) return DayLayout.empty;

  final entries = <PlanBlockLayout>[];
  for (final plan in items) {
    final start = clampDouble(
      plan.startHour,
      kFirstHour.toDouble(),
      kEndHour - ScheduleMetrics.snapHours,
    );
    final minutes =
        plan.duration < ScheduleMetrics.snapMinutes ? ScheduleMetrics.snapMinutes : plan.duration;
    final end = clampDouble(start + minutes / 60, start, kEndHour.toDouble());
    entries.add(PlanBlockLayout(plan: plan, lane: 0, start: start, end: end));
  }
  entries.sort((a, b) => a.start == b.start ? a.end.compareTo(b.end) : a.start.compareTo(b.start));

  // 经典的"最少车道"分配：每一层记录当前结束时间，
  // 新条目优先塞进最早腾出来的那一层
  final laneEnds = <double>[];
  final blocks = <PlanBlockLayout>[];
  for (final entry in entries) {
    var lane = laneEnds.indexWhere((end) => end <= entry.start);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(0);
    }
    laneEnds[lane] = entry.end;
    blocks.add(
      PlanBlockLayout(
        plan: entry.plan,
        lane: lane,
        start: entry.start,
        end: entry.end,
      ),
    );
  }

  return DayLayout(
    signature: signature,
    lanes: laneEnds.isEmpty ? 1 : laneEnds.length,
    blocks: blocks,
  );
}
