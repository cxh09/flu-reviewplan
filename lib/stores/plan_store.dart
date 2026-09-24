import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/plan_data.dart';
import '../models/plan.dart';
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
///
/// 「日程广场」里的日程是排班的素材库：点一条或把它拖到时间线上，
/// 就直接生成一条排版计划（[scheduleFromPlaza]），不再有中间的待办缓冲。
class PlanStore extends ChangeNotifier {
  PlanStore() {
    _rebuildDateIndex();
  }

  String _gaokaoDate = kDefaultGaokaoDate;
  int _gaokaoDateUpdatedAt = 0;
  final List<Plan> _plans = <Plan>[];

  // 分享署名用的作者资料：头像为客户端压缩后的 dataURL；对齐网页版 plan.js 的 profile
  String _profileName = '';
  String _profileAvatar = '';
  int _profileUpdatedAt = 0;

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

  String get profileName => _profileName;
  String get profileAvatar => _profileAvatar;

  /// 全部计划（只读视图，不做拷贝）
  List<Plan> get plans => UnmodifiableListView<Plan>(_plans);

  // ---------- 派生数据 ----------

  int get daysToGaokao => diffDays(todayKey(), _gaokaoDate);
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
      date: date,
      startHour: startHour,
      note: note,
    );
    _plans.add(plan);
    _indexInsert(plan);
    _touch();
    return plan;
  }

  /// 把「日程广场」里的一条日程直接排到时间线上（生成一条排版计划）。
  /// 同一条可反复排到不同时段，不做去重。
  Plan? scheduleFromPlaza({
    required String title,
    required String date,
    required double startHour,
    String category = '通用',
    int duration = kDefaultSlotMinutes,
    String level = '基础',
    String desc = '',
    String link = '',
    String note = '',
  }) {
    if (!ensureWritable()) return null;

    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;

    return _addPlan(
      title: trimmed,
      category: category,
      level: level,
      desc: desc,
      link: link,
      source: 'plaza',
      date: date,
      startHour: startHour,
      duration: duration > 0 ? duration : kDefaultSlotMinutes,
      note: note,
    );
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

  /// 更新作者资料（用户名 / 头像）；[avatar] 传 null 表示不改动当前头像。
  void setProfile({String? name, String? avatar}) {
    if (!ensureWritable()) return;
    if (name != null) {
      final trimmed = name.trim();
      _profileName = trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;
    }
    if (avatar != null && avatar.isNotEmpty) _profileAvatar = avatar;
    _profileUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    _touch();
  }

  /// 当前数据打包成同步用的快照片段（对齐 sync store 的 `buildPayload`）
  Map<String, dynamic> buildPayload() => <String, dynamic>{
        'gaokaoDate': _gaokaoDate,
        'gaokaoDateUpdatedAt': _gaokaoDateUpdatedAt,
        'plans': _plans.map((plan) => plan.toJson()).toList(),
        'profile': <String, dynamic>{
          'name': _profileName,
          'avatar': _profileAvatar,
          'updatedAt': _profileUpdatedAt,
        },
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
    final rawPlans = data['plans'];

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

    // 资料是随快照同步的标量对象，缺字段时按空处理，不会写进脏数据
    final rawProfile = data['profile'];
    if (rawProfile is Map) {
      final p = rawProfile.cast<String, dynamic>();
      _profileName = '${p['name'] ?? ''}';
      _profileAvatar = '${p['avatar'] ?? ''}';
      _profileUpdatedAt = toInt(p['updatedAt'], 0);
    }

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
    TombstoneService.markDeletedMany(
      _plans.map((plan) => plan.id).toList(),
    );
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
