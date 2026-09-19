import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/plan_data.dart';
import '../models/plan.dart';
import '../models/todo.dart';
import '../services/tombstone_service.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';
import '../utils/url_utils.dart';
import 'connection.dart';

/// 未来若干天里已经排过班的一天
class PlanGroup {
  const PlanGroup({required this.date, required this.items});

  final String date;
  final List<Plan> items;
}

/// 本周（未来 7 天）的完成情况
class WeekStats {
  const WeekStats({required this.total, required this.done, required this.rate});

  final int total;
  final int done;
  final int rate;
}

/// 复习清单的核心数据（对齐网页版 `src/stores/plan.js`）：
/// - [todos] 待办清单（还没安排具体时间的复习任务）
/// - [plans] 排版计划（已安排到某天某个时段的复习任务）
///
/// 全在线模式：数据以云端为唯一来源，本地不落盘；
/// 初始为空，启动后由 [SyncStore] 拉取云端快照填充，改动经其推回云端。
///
/// 所有写操作都先过 [ensureWritable]，离线 / 未配置时拒绝写入并给出节流提示。
///
/// 两个性能上的关键约定：
/// 1. 计划列表**原地修改**，不再每次改动都整体拷贝——拖拽时每帧都会改一次，
///    全量拷贝在计划上百条时是纯浪费；
/// 2. 维护一份 `日期 → 当天计划` 的索引，[plansOfDate] 是 O(当天条数)，
///    而不是每次全表过滤。
class PlanStore extends ChangeNotifier {
  PlanStore() {
    _rebuildDateIndex();
  }

  String _gaokaoDate = kDefaultGaokaoDate;
  int _gaokaoDateUpdatedAt = 0;
  final List<Todo> _todos = <Todo>[];
  final List<Plan> _plans = <Plan>[];

  /// 每次数据变化 +1。
  /// 因为列表是原地修改的（引用不会变），外部想按"数据有没有变"做缓存，
  /// 只能靠这个版本号来判断。
  int _revision = 0;

  int get revision => _revision;

  /// 日期 → 当天计划（始终按开始时间升序）
  final Map<String, List<Plan>> _plansByDate = <String, List<Plan>>{};

  // ---------- 只读访问 ----------

  String get gaokaoDate => _gaokaoDate;
  int get gaokaoDateUpdatedAt => _gaokaoDateUpdatedAt;

  /// 待办清单（只读视图，不做拷贝）
  List<Todo> get todos => UnmodifiableListView<Todo>(_todos);

  /// 全部计划（只读视图，不做拷贝）
  List<Plan> get plans => UnmodifiableListView<Plan>(_plans);

  // ---------- 派生数据 ----------

  int get daysToGaokao => diffDays(todayKey(), _gaokaoDate);
  int get todoCount => _todos.length;
  int get planCount => _plans.length;
  int get donePlanCount => _plans.where((plan) => plan.done).length;

  int get completionRate =>
      planCount == 0 ? 0 : (donePlanCount / planCount * 100).round();

  /// 某一天的计划，按开始时间升序。
  ///
  /// 返回的是内部列表，**调用方不要修改**；这样拖拽时每帧查询不会产生额外分配。
  List<Plan> plansOfDate(String date) =>
      _plansByDate[date] ?? const <Plan>[];

  /// 未来 7 天里已经排过班的日子
  List<PlanGroup> get upcomingGroups {
    final base = todayKey();
    final groups = <PlanGroup>[];
    for (var offset = 0; offset < 7; offset += 1) {
      final date = addDays(base, offset);
      final items = plansOfDate(date);
      if (items.isNotEmpty) {
        groups.add(PlanGroup(date: date, items: List<Plan>.of(items)));
      }
    }
    return groups;
  }

  WeekStats get weekStats {
    var total = 0;
    var done = 0;
    for (final group in upcomingGroups) {
      total += group.items.length;
      done += group.items.where((item) => item.done).length;
    }
    return WeekStats(
      total: total,
      done: done,
      rate: total == 0 ? 0 : (done / total * 100).round(),
    );
  }

  /// 待办里是否已有这条日程（传科目时按「标题 + 科目」判断，与 [addTodo] 去重口径一致）
  bool hasTodo(String title, [String? category]) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return false;
    return _todos.any((todo) =>
        todo.title == trimmed && (category == null || todo.category == category));
  }

  // ---------- 按日索引的维护 ----------

  int _indexOfPlan(String planId) => _plans.indexWhere((plan) => plan.id == planId);

  void _sortBucket(String date) {
    _plansByDate[date]?.sort((a, b) => a.startHour.compareTo(b.startHour));
  }

  void _indexInsert(Plan plan) {
    (_plansByDate[plan.date] ??= <Plan>[]).add(plan);
    _sortBucket(plan.date);
  }

  void _indexRemove(Plan plan) {
    final bucket = _plansByDate[plan.date];
    if (bucket == null) return;
    bucket.removeWhere((item) => item.id == plan.id);
    if (bucket.isEmpty) _plansByDate.remove(plan.date);
  }

  /// 用 [next] 顶掉 [before]：日期没变就地替换，变了就换桶
  void _indexReplace(Plan before, Plan next) {
    if (before.date == next.date) {
      final bucket = _plansByDate[next.date];
      if (bucket != null) {
        final at = bucket.indexWhere((item) => item.id == next.id);
        if (at != -1) bucket[at] = next;
      }
      _sortBucket(next.date);
      return;
    }
    _indexRemove(before);
    _indexInsert(next);
  }

  /// 原地替换第 [index] 条计划
  void _replacePlanAt(int index, Plan next) {
    final before = _plans[index];
    _plans[index] = next;
    _indexReplace(before, next);
  }

  void _rebuildDateIndex() {
    _plansByDate.clear();
    for (final plan in _plans) {
      (_plansByDate[plan.date] ??= <Plan>[]).add(plan);
    }
    for (final date in _plansByDate.keys.toList()) {
      _sortBucket(date);
    }
  }

  // ---------- 待办清单 ----------

  /// 加入待办清单，同标题同科目视为同一条
  Todo? addTodo({
    required String title,
    String category = '通用',
    int duration = 30,
    String level = '基础',
    String desc = '',
    String link = '',
    String source = 'manual',
  }) {
    if (!ensureWritable()) return null;

    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;

    for (final todo in _todos) {
      if (todo.title == trimmed && todo.category == category) return todo;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final todo = Todo(
      id: createId('todo'),
      title: trimmed,
      category: category,
      duration: duration,
      level: level,
      desc: desc,
      link: sanitizeLink(link),
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    _todos.add(todo);
    _touch();
    return todo;
  }

  void removeTodo(String id) {
    if (!ensureWritable()) return;
    TombstoneService.markDeleted(id);
    _todos.removeWhere((todo) => todo.id == id);
    _touch();
  }

  // ---------- 排版计划 ----------

  Plan? _addPlan({
    required String title,
    String category = '通用',
    int duration = kDefaultSlotMinutes,
    String level = '基础',
    String desc = '',
    String link = '',
    String source = 'manual',
    required String date,
    required double startHour,
    String note = '',
    String? todoId,
    int? originDuration,
  }) {
    if (!ensureWritable()) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final plan = Plan(
      id: createId('plan'),
      title: title,
      category: category,
      duration: duration,
      level: level,
      desc: desc,
      link: sanitizeLink(link),
      source: source,
      createdAt: now,
      updatedAt: now,
      todoId: todoId,
      date: date,
      startHour: startHour,
      originDuration: originDuration,
      note: note,
    );
    _plans.add(plan);
    _indexInsert(plan);
    _touch();
    return plan;
  }

  /// 把待办清单里的条目拖到时间线上：从待办移到计划
  Plan? scheduleFromTodo(
    String todoId,
    String date,
    double startHour, {
    int? duration,
    String note = '',
  }) {
    if (!ensureWritable()) return null;

    final index = _todos.indexWhere((todo) => todo.id == todoId);
    if (index == -1) return null;

    final todo = _todos[index];
    // 待办被「消耗」成计划：记一笔删除，否则合并时会被另一端的副本复活
    TombstoneService.markDeleted(todo.id);
    _todos.removeAt(index);

    return _addPlan(
      title: todo.title,
      category: todo.category,
      level: todo.level,
      desc: todo.desc,
      link: todo.link,
      source: todo.source,
      date: date,
      startHour: startHour,
      // 没指定时长时默认用待办的预估耗时，之后再拖边缘调整跨度
      duration: duration ?? (todo.duration > 0 ? todo.duration : kDefaultSlotMinutes),
      todoId: todo.id,
      originDuration: todo.duration,
      note: note,
    );
  }

  /// 把计划退回到待办清单
  void unschedulePlan(String planId) {
    if (!ensureWritable()) return;

    final index = _indexOfPlan(planId);
    if (index == -1) return;

    final plan = _plans[index];
    TombstoneService.markDeleted(plan.id);
    _plans.removeAt(index);
    _indexRemove(plan);

    final now = DateTime.now().millisecondsSinceEpoch;
    _todos.add(
      Todo(
        id: createId('todo'),
        title: plan.title,
        category: plan.category,
        // 排班时可能被改成了一小时，退回待办还原成条目原本的时长
        duration: plan.originDuration ?? plan.duration,
        level: plan.level,
        desc: plan.desc,
        link: plan.link,
        source: plan.source,
        createdAt: now,
        updatedAt: now,
      ),
    );
    _touch();
  }

  void movePlan(String planId, String date, double startHour) {
    if (!ensureWritable()) return;

    final index = _indexOfPlan(planId);
    if (index == -1) return;

    _replacePlanAt(
      index,
      _plans[index].copyWith(
        date: date,
        startHour: startHour,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _touch();
  }

  /// 横向拉伸计划块：调整开始时间 / 时长（时间跨度）
  void resizePlan(String planId, {double? startHour, int? duration}) {
    if (!ensureWritable()) return;

    final index = _indexOfPlan(planId);
    if (index == -1) return;

    final plan = _plans[index];
    _replacePlanAt(
      index,
      plan.copyWith(
        startHour: startHour ?? plan.startHour,
        duration: duration == null ? plan.duration : (duration < 15 ? 15 : duration),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _touch();
  }

  /// 详情面板的批量更新。所有字段都会先归一化，
  /// 空标题、非法日期这类值不会覆盖原值，避免计划被改成空后从日历上消失。
  Plan? updatePlan(
    String planId, {
    String? title,
    String? category,
    String? level,
    String? desc,
    String? link,
    String? note,
    String? date,
    double? startHour,
    int? duration,
  }) {
    if (!ensureWritable()) return null;

    final index = _indexOfPlan(planId);
    if (index == -1) return null;

    var next = _plans[index];

    if (title != null) {
      final trimmed = title.trim();
      if (trimmed.isNotEmpty) next = next.copyWith(title: trimmed);
    }
    if (category != null && category.isNotEmpty) next = next.copyWith(category: category);
    if (level != null && level.isNotEmpty) next = next.copyWith(level: level);
    if (desc != null) next = next.copyWith(desc: desc);
    if (link != null) next = next.copyWith(link: sanitizeLink(link));
    if (note != null) next = next.copyWith(note: note);
    if (date != null && isValidDateKey(date)) next = next.copyWith(date: date);
    if (startHour != null) {
      next = next.copyWith(
        startHour: clampDouble(startHour, kFirstHour.toDouble(), kEndHour - 0.25),
      );
    }
    if (duration != null) {
      next = next.copyWith(duration: clampInt(duration, kMinDuration, kMaxDuration));
    }

    _replacePlanAt(
      index,
      next.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
    );
    _touch();
    return _plans[index];
  }

  void togglePlanDone(String planId) {
    if (!ensureWritable()) return;

    final index = _indexOfPlan(planId);
    if (index == -1) return;

    _plans[index] = _plans[index].copyWith(
      done: !_plans[index].done,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _touch();
  }

  void removePlan(String planId) {
    if (!ensureWritable()) return;

    final index = _indexOfPlan(planId);
    if (index == -1) return;

    final plan = _plans[index];
    TombstoneService.markDeleted(plan.id);
    _plans.removeAt(index);
    _indexRemove(plan);
    _touch();
  }

  // ---------- 设置与数据管理 ----------

  void setGaokaoDate(String date) {
    if (!ensureWritable()) return;
    if (!isValidDateKey(date)) return;
    _gaokaoDate = date;
    _gaokaoDateUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    _touch();
  }

  /// 当前数据打包成同步用的快照片段（对齐 sync store 的 `buildPayload`）
  Map<String, dynamic> buildPayload() => <String, dynamic>{
        'gaokaoDate': _gaokaoDate,
        'gaokaoDateUpdatedAt': _gaokaoDateUpdatedAt,
        'todos': _todos.map((todo) => todo.toJson()).toList(),
        'plans': _plans.map((plan) => plan.toJson()).toList(),
      };

  /// 导出（含版本号与删除标记）
  String exportData() => const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'version': kDataVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        ...buildPayload(),
        'deleted': TombstoneService.active(),
      });

  /// 应用一份远端 / 导入快照（不经过只读校验，调用方保证来源可信）
  void applySnapshot(Map<String, dynamic> data) {
    final rawTodos = data['todos'];
    final rawPlans = data['plans'];

    if (rawTodos is List) {
      _todos
        ..clear()
        ..addAll(
          rawTodos
              .whereType<Map>()
              .map((item) => Todo.fromJson(item.cast<String, dynamic>())),
        );
    }
    if (rawPlans is List) {
      _plans
        ..clear()
        ..addAll(
          rawPlans
              .whereType<Map>()
              .map((item) => Plan.fromJson(item.cast<String, dynamic>())),
        );
    }
    if (isValidDateKey(data['gaokaoDate'])) {
      _gaokaoDate = '${data['gaokaoDate']}';
      // 快照没带时间戳（历史数据）就记 0，避免本地旧时间戳让后续合并判断失真
      _gaokaoDateUpdatedAt = toInt(data['gaokaoDateUpdatedAt'], 0);
    }
    if (data['deleted'] is List) TombstoneService.setTombstones(data['deleted']);

    _rebuildDateIndex();
    _touch();
  }

  /// 导入备份文件（会校验版本号）
  void importData(Object payload) {
    final data = payload is String ? jsonDecode(payload) : payload;
    if (data is! Map) throw const FormatException('数据格式不正确');

    final map = data.cast<String, dynamic>();
    // 备份来自更新版本时，按旧结构解析可能丢字段，直接拒绝并给出明确提示
    final version = toNumber(map['version'], 0);
    if (version > kDataVersion) {
      throw const FormatException('备份文件来自更新的版本，请升级应用后再导入');
    }

    applySnapshot(map);
  }

  void resetAll() {
    if (!ensureWritable()) return;
    // 清空也是一次删除：不记标记的话，另一端残留的副本会把数据带回来
    TombstoneService.markDeletedMany(<String>[
      ..._todos.map((todo) => todo.id),
      ..._plans.map((plan) => plan.id),
    ]);
    _todos.clear();
    _plans.clear();
    _plansByDate.clear();
    _gaokaoDate = kDefaultGaokaoDate;
    _gaokaoDateUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    _touch();
  }

  /// 数据变了：通知界面刷新（改动由 SyncStore 监听并推送到云端）
  void _touch() {
    _revision += 1;
    notifyListeners();
  }
}
