import '../data/plaza_data.dart';
import '../utils/id_utils.dart';
import '../utils/url_utils.dart';

/// 合集里的日程：未加入待办前的「素材」。
class PlazaItem {
  const PlazaItem({
    required this.id,
    required this.title,
    this.category = '通用',
    this.level = '基础',
    this.duration = kDefaultItemDuration,
    this.desc = '',
    this.link = '',
    this.updatedAt = 0,
  });

  final String id;
  final String title;
  final String category;
  final String level;
  final int duration;
  final String desc;
  final String link;

  /// 0 表示历史数据（没有时间戳），合并时视为最旧
  final int updatedAt;

  factory PlazaItem.fromJson(Map<String, dynamic>? raw) {
    final data = raw ?? const <String, dynamic>{};
    return PlazaItem(
      id: '${data['id'] ?? ''}'.trim().isEmpty ? createId('item') : '${data['id']}',
      title: '${data['title'] ?? ''}'.trim().isEmpty
          ? '未命名日程'
          : '${data['title']}'.trim(),
      category: '${data['category'] ?? ''}'.isEmpty ? '通用' : '${data['category']}',
      level: '${data['level'] ?? ''}'.isEmpty ? '基础' : '${data['level']}',
      duration: (data['duration'] is num && (data['duration'] as num) != 0)
          ? (data['duration'] as num).toInt()
          : kDefaultItemDuration,
      desc: '${data['desc'] ?? ''}',
      link: sanitizeLink(data['link']),
      updatedAt: (data['updatedAt'] is num) ? (data['updatedAt'] as num).toInt() : 0,
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
        'updatedAt': updatedAt,
      };

  PlazaItem copyWith({
    String? id,
    String? title,
    String? category,
    String? level,
    int? duration,
    String? desc,
    String? link,
    int? updatedAt,
  }) {
    return PlazaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      level: level ?? this.level,
      duration: duration ?? this.duration,
      desc: desc ?? this.desc,
      link: link ?? this.link,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
