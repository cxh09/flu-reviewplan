import '../data/plan_data.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';
import '../utils/url_utils.dart';

/// 完成详情的文件引用：只认服务端 /uploads/ 下的随机文件名，其余丢弃；最多 9 项。
/// preview 为 ≤1MB 的压缩预览图，展示默认用它，查看原图才加载 url。
List<Map<String, dynamic>> sanitizeFileRefs(Object? list) {
  if (list is! List) return <Map<String, dynamic>>[];
  final pattern = RegExp(r'^/uploads/[\w.-]+$');
  final refs = <Map<String, dynamic>>[];
  for (final item in list) {
    if (item is! Map) continue;
    final url = '${item['url'] ?? ''}';
    if (!pattern.hasMatch(url)) continue;
    var name = '${item['name'] ?? ''}';
    if (name.length > 120) name = name.substring(0, 120);
    final ref = <String, dynamic>{'name': name, 'url': url};
    final preview = '${item['preview'] ?? ''}';
    if (pattern.hasMatch(preview)) ref['preview'] = preview;
    refs.add(ref);
    if (refs.length >= 9) break;
  }
  return refs;
}

/// 排版计划：已安排到某天某个时段的复习任务。
///
/// 字段与网页版 `stores/plan.js` 的 `plan` 完全一致。
class Plan {
  const Plan({
    required this.id,
    required this.title,
    this.category = '通用',
    this.level = '基础',
    this.duration = kDefaultSlotMinutes,
    this.desc = '',
    this.link = '',
    this.source = 'manual',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.date = '',
    this.startHour = 6.0,
    this.note = '',
    this.done = false,
    this.doneNote = '',
    this.doneImages = const <Map<String, dynamic>>[],
    this.doneFiles = const <Map<String, dynamic>>[],
  });

  final String id;
  final String title;
  final String category;
  final String level;
  final int duration;
  final String desc;
  final String link;
  final String source;
  final int createdAt;

  /// 条目最后一次修改时间；0 表示历史数据（没有时间戳），合并时视为最旧
  final int updatedAt;

  final String date;

  /// 开始时刻，用小数小时表示，例如 9.75 表示 9:45
  final double startHour;
  final String note;
  final bool done;

  /// 完成详情：说明文字 + 图片 / 附件引用（文件存服务端，这里只存 URL）
  final String doneNote;
  final List<Map<String, dynamic>> doneImages;
  final List<Map<String, dynamic>> doneFiles;

  /// 兼容旧数据与导入数据：补齐缺失字段并夹回合法范围
  factory Plan.fromJson(Map<String, dynamic>? raw) {
    final data = raw ?? const <String, dynamic>{};
    return Plan(
      id: '${data['id'] ?? ''}'.trim().isEmpty ? createId('plan') : '${data['id']}',
      title: '${data['title'] ?? ''}'.trim().isEmpty
          ? '未命名日程'
          : '${data['title']}'.trim(),
      category: '${data['category'] ?? ''}'.isEmpty ? '通用' : '${data['category']}',
      level: '${data['level'] ?? ''}'.isEmpty ? '基础' : '${data['level']}',
      duration: clampInt(
        toNumber(data['duration'], kDefaultSlotMinutes.toDouble()),
        kMinDuration,
        kMaxDuration,
      ),
      desc: '${data['desc'] ?? ''}',
      link: sanitizeLink(data['link']),
      source: '${data['source'] ?? ''}'.isEmpty ? 'manual' : '${data['source']}',
      createdAt: toInt(data['createdAt'], DateTime.now().millisecondsSinceEpoch),
      // 0 表示历史数据（没有时间戳），合并时视为最旧
      updatedAt: toInt(data['updatedAt'], 0),
      date: isValidDateKey(data['date']) ? '${data['date']}' : todayKey(),
      startHour: clampDouble(
        toNumber(data['startHour'], kFirstHour.toDouble()),
        kFirstHour.toDouble(),
        kEndHour - 0.25,
      ),
      note: '${data['note'] ?? ''}',
      done: data['done'] == true,
      doneNote: '${data['doneNote'] ?? ''}',
      doneImages: sanitizeFileRefs(data['doneImages']),
      doneFiles: sanitizeFileRefs(data['doneFiles']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'category': category,
        'level': level,
        'duration': duration,
        'desc': desc,
        'link': link,
        'source': source,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'date': date,
        'startHour': startHour,
        'note': note,
        'done': done,
        'doneNote': doneNote,
        'doneImages': doneImages,
        'doneFiles': doneFiles,
      };

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
    String? date,
    double? startHour,
    String? note,
    bool? done,
    String? doneNote,
    List<Map<String, dynamic>>? doneImages,
    List<Map<String, dynamic>>? doneFiles,
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
      date: date ?? this.date,
      startHour: startHour ?? this.startHour,
      note: note ?? this.note,
      done: done ?? this.done,
      doneNote: doneNote ?? this.doneNote,
      doneImages: doneImages ?? this.doneImages,
      doneFiles: doneFiles ?? this.doneFiles,
    );
  }
}
