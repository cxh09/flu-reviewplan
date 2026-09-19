import 'dart:math';

final Random _random = Random();

/// 统一生成移动端用的随机 id（与网页版 `createId` 同构：前缀 + 时间戳 36 进制 + 随机后缀）
String createId([String prefix = 'id']) {
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final suffix = _random.nextInt(0x1FFFFFFF).toRadixString(36).padLeft(5, '0');
  return '$prefix-$stamp$suffix';
}
