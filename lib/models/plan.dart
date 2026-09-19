import '../data/plan_data.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';
import '../utils/url_utils.dart';
import 'todo.dart';

/// 排版计划：已安排到某天某个时段的复习任务。
///
/// 字段与网页版 `stores/plan.js` 的 `plan` 完全一致。
class Plan extends Todo {
  const Plan({
    required super.id,
    required super.title,
    super.category,
    super.level,
    super.duration,
    super.desc,
    super.link,
    super.source,
    super.createdAt,
    super.updatedAt,
    this.todoId,
    this.date = '',
    this.startHour = 6.0,
    this.originDuration,
    this.note = '',
    this.done = false,
  });

  /// 由哪条待办排班而来（手动添加的日程为 null）
  final String? todoId;
  final String date;

  /// 开始时刻，用小数小时表示，例如 9.75 表示 9:45
  final double startHour;

  /// 排班前待办原本的时长：退回待办时用它还原
  final int? originDuration;
  final String note;
  final bool done;

  /// 兼容旧数据与导入数据：在待办字段基础上补齐排班字段并夹回合法范围
  factory Plan.fromJson(Map<String, dynamic>? raw) {
    final base = Todo.fromJson(raw);
    final data = raw ?? const <String, dynamic>{};
    return Plan(
      id: '${data['id'] ?? ''}'.trim().isEmpty ? createId('plan') : '${data['id']}',
      title: base.title,
      category: base.category,
      level: base.level,
      duration: clampInt(
        toNumber(data['duration'], kDefaultSlotMinutes.toDouble()),
        kMinDuration,
        kMaxDuration,
      ),
      desc: base.desc,
      link: sanitizeLink(data['link']),
      source: base.source,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      todoId: data['todoId'] == null ? null : '${data['todoId']}',
      date: isValidDateKey(data['date']) ? '${data['date']}' : todayKey(),
      startHour: clampDouble(
        toNumber(data['startHour'], kFirstHour.toDouble()),
        kFirstHour.toDouble(),
        kEndHour - 0.25,
      ),
      originDuration:
          data['originDuration'] == null ? null : toInt(data['originDuration'], 0),
      note: '${data['note'] ?? ''}',
      done: data['done'] == true,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...super.toJson(),
        'todoId': todoId,
        'date': date,
        'startHour': startHour,
        'originDuration': originDuration,
        'note': note,
        'done': done,
      };

  @override
  Plan copyWith({
    String? id,
    String? title,
    String? category,
    String? level,
    int? duration,
    String? desc,
    String? link,
    String? source,
    int? createdAt,
    int? updatedAt,
    String? todoId,
    String? date,
    double? startHour,
    int? originDuration,
    String? note,
    bool? done,
  }) {
    return Plan(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      level: level ?? this.level,
      duration: duration ?? this.duration,
      desc: desc ?? this.desc,
      link: link ?? this.link,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      todoId: todoId ?? this.todoId,
      date: date ?? this.date,
      startHour: startHour ?? this.startHour,
      originDuration: originDuration ?? this.originDuration,
      note: note ?? this.note,
      done: done ?? this.done,
    );
  }
}
