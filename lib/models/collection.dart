import 'package:flutter/material.dart';

import '../data/plaza_data.dart';
import '../utils/id_utils.dart';
import 'plaza_item.dart';

/// 系列合集：用户自己在日程广场维护的日程分组。
class Collection {
  const Collection({
    required this.id,
    required this.name,
    this.desc = '',
    this.category = '通用',
    this.color = '',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.items = const <PlazaItem>[],
  });

  final String id;
  final String name;
  final String desc;
  final String category;
  final String color;
  final int createdAt;

  /// 0 表示历史数据（没有时间戳），合并时视为最旧
  final int updatedAt;
  final List<PlazaItem> items;

  /// 兼容旧数据 / 导入数据，补齐缺失字段
  factory Collection.fromJson(Map<String, dynamic>? raw) {
    final data = raw ?? const <String, dynamic>{};
    final category = '${data['category'] ?? ''}'.isEmpty ? '通用' : '${data['category']}';
    final rawItems = data['items'];
    return Collection(
      id: '${data['id'] ?? ''}'.trim().isEmpty ? createId('col') : '${data['id']}',
      name: '${data['name'] ?? ''}'.trim().isEmpty
          ? '未命名合集'
          : '${data['name']}'.trim(),
      desc: '${data['desc'] ?? ''}',
      category: category,
      color: '${data['color'] ?? ''}'.isEmpty
          ? (kCategoryColors[category] ?? kCollectionColors.first)
          : '${data['color']}',
      createdAt: (data['createdAt'] is num)
          ? (data['createdAt'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
      updatedAt: (data['updatedAt'] is num) ? (data['updatedAt'] as num).toInt() : 0,
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => PlazaItem.fromJson(item.cast<String, dynamic>()))
              .toList()
          : const <PlazaItem>[],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'desc': desc,
        'category': category,
        'color': color,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'items': items.map((item) => item.toJson()).toList(),
      };

  Collection copyWith({
    String? id,
    String? name,
    String? desc,
    String? category,
    String? color,
    int? createdAt,
    int? updatedAt,
    List<PlazaItem>? items,
  }) {
    return Collection(
      id: id ?? this.id,
      name: name ?? this.name,
      desc: desc ?? this.desc,
      category: category ?? this.category,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }

  /// 合集展示色
  Color get displayColor => collectionColorOf(color: color, category: category);
}
