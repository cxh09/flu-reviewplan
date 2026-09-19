import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 可选科目
const List<String> kCategoryOptions = <String>[
  '语文',
  '数学',
  '英语',
  '物理',
  '化学',
  '生物',
  '文综',
  '通用',
];

/// 新建日程时的默认预计时长（分钟）
const int kDefaultItemDuration = 30;

/// 合集可选主题色
const List<String> kCollectionColors = <String>[
  '#0052d9',
  '#00a870',
  '#ed7b2f',
  '#d54941',
  '#7b4ee0',
  '#0e7a8a',
  '#b8860b',
  '#64748b',
];

/// 科目主题色，用于计划卡片左侧色条与标签
const Map<String, String> kCategoryColors = <String, String>{
  '语文': '#d54941',
  '数学': '#0052d9',
  '英语': '#7b4ee0',
  '物理': '#0e7a8a',
  '化学': '#ed7b2f',
  '生物': '#00a870',
  '文综': '#b8860b',
  '通用': '#64748b',
};

/// 难度对应的 TDesign Tag 语义色
const Map<String, TTagColorScheme> kLevelTheme = <String, TTagColorScheme>{
  '基础': TTagColorScheme.primary,
  '提升': TTagColorScheme.warning,
  '冲刺': TTagColorScheme.danger,
};

/// 把 `#RRGGBB` / `#AARRGGBB` 解析成 [Color]，非法时返回兜底色
Color colorFromHex(String? hex, {Color fallback = const Color(0xFF64748B)}) {
  final value = (hex ?? '').trim().replaceFirst('#', '');
  if (value.isEmpty) return fallback;

  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return fallback;

  if (value.length == 6) return Color(0xFF000000 | parsed);
  if (value.length == 8) return Color(parsed);
  return fallback;
}

/// 科目展示色，未知科目兜底为「通用」色
Color categoryColor(String? category) => colorFromHex(kCategoryColors[category]);

/// 难度对应的 TDesign Tag 语义色，未知难度兜底为 default
TTagColorScheme levelColorScheme(String? level) =>
    kLevelTheme[level ?? ''] ?? TTagColorScheme.defaultTheme;

/// 合集主题色：优先用合集自带颜色，其次跟随科目色
Color collectionColorOf({String? color, String? category}) {
  final raw = (color ?? '').trim();
  if (raw.isNotEmpty) return colorFromHex(raw, fallback: categoryColor(category));
  return categoryColor(category);
}
