import '../data/plan_data.dart';
import '../utils/id_utils.dart';
import '../utils/url_utils.dart';

/// 待办清单条目：还没有安排具体时间的复习任务。
///
/// 字段与网页版 `stores/plan.js` 的 `todo` 完全一致，服务端快照可直接互通。
class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.category = '通用',
    this.level = '基础',
    this.duration = 30,
    this.desc = '',
    this.link = '',
    this.source = 'manual',
    this.createdAt = 0,
    this.updatedAt = 0,
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

  /// 兼容旧数据与导入数据：补齐待办缺失字段
  factory Todo.fromJson(Map<String, dynamic>? raw) {
    final data = raw ?? const <String, dynamic>{};
    return Todo(
      id: '${data['id'] ?? ''}'.trim().isEmpty ? createId('todo') : '${data['id']}',
      title: '${data['title'] ?? ''}'.trim().isEmpty
          ? '未命名待办'
          : '${data['title']}'.trim(),
      category: '${data['category'] ?? ''}'.isEmpty ? '通用' : '${data['category']}',
      level: '${data['level'] ?? ''}'.isEmpty ? '基础' : '${data['level']}',
      duration: clampInt(toNumber(data['duration'], 30), kMinDuration, kMaxDuration),
      desc: '${data['desc'] ?? ''}',
      link: sanitizeLink(data['link']),
      source: '${data['source'] ?? ''}'.isEmpty ? 'manual' : '${data['source']}',
      createdAt: toInt(data['createdAt'], DateTime.now().millisecondsSinceEpoch),
      updatedAt: toInt(data['updatedAt'], 0),
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
      };

  Todo copyWith({
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
  }) {
    return Todo(
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
    );
  }
}
