/// 日期计算（对齐网页版 `src/utils/date.js`），全部按设备本地时区处理。
library;

const List<String> _weekdays = <String>[
  '星期日',
  '星期一',
  '星期二',
  '星期三',
  '星期四',
  '星期五',
  '星期六',
];

const List<String> _weekdayShort = <String>['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

String _pad2(int value) => value.toString().padLeft(2, '0');

/// 转成 `YYYY-MM-DD` 字符串（本地时区）
String toDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${_pad2(date.month)}-${_pad2(date.day)}';

/// 今天
String todayKey() => toDateKey(DateTime.now());

/// `YYYY-MM-DD` 字符串转本地 0 点的 [DateTime]
DateTime parseDateKey(String? key) {
  if (key == null || key.isEmpty) return DateTime.now();
  final parts = key.split('-');
  if (parts.length != 3) return DateTime.now();
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return DateTime.now();
  return DateTime(year, month, day);
}

/// 形如 `YYYY-MM-DD` 且是真实存在的日期（能原样往返），用来挡住导入的脏日期
bool isValidDateKey(Object? key) {
  if (key is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return false;
  return toDateKey(parseDateKey(key)) == key;
}

/// 在日期上加减天数
String addDays(String key, int days) {
  final date = parseDateKey(key);
  return toDateKey(DateTime(date.year, date.month, date.day + days));
}

/// 两个日期相差的天数（to - from）
int diffDays(String fromKey, String toKey) {
  final from = parseDateKey(fromKey);
  final to = parseDateKey(toKey);
  return ((to.millisecondsSinceEpoch - from.millisecondsSinceEpoch) / 86400000).round();
}

/// `2026 年 9 月 11 日`
String formatCN(String key) {
  final date = parseDateKey(key);
  return '${date.year} 年 ${date.month} 月 ${date.day} 日';
}

/// `星期五`
String weekdayCN(String key) => _weekdays[parseDateKey(key).weekday % 7];

/// 是否是今天
bool isToday(String key) => key == todayKey();

/// 把整点小时格式化成 `09:00`
String formatHour(num hour) => '${_pad2(hour.toInt())}:00';

/// 把小数小时格式化成 `07:30`
String formatClock(num hourValue) {
  final total = (hourValue * 60).round();
  final hour = (total ~/ 60) % 24;
  final minute = total % 60;
  return '${_pad2(hour)}:${_pad2(minute)}';
}

/// `周一`
String weekdayShortCN(String key) => _weekdayShort[parseDateKey(key).weekday % 7];

/// `9月11日`
String formatMD(String key) {
  final date = parseDateKey(key);
  return '${date.month} 月 ${date.day} 日';
}

/// 从 [startKey] 开始连续 [days] 天的日期数组
List<String> dateRange(String startKey, int days) =>
    List<String>.generate(days, (index) => addDays(startKey, index));

/// 是否是周末
bool isWeekend(String key) {
  final weekday = parseDateKey(key).weekday;
  return weekday == DateTime.saturday || weekday == DateTime.sunday;
}
