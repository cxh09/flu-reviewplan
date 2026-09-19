/// 复习清单的核心数据常量（对齐网页版 `src/stores/plan.js` 与 `src/utils/merge.js`）。
library;

/// 导出数据的格式版本；导入时用它判断备份是否来自更新的版本。
///
/// v2：导出内容在待办 / 计划之外额外带上了日程广场的系列合集。
/// v3：条目带上 updatedAt、快照带上 gaokaoDateUpdatedAt 与删除标记，用于两端按条目合并。
const int kDataVersion = 3;

/// 默认高考日期（2027 年高考首日）
const String kDefaultGaokaoDate = '2027-06-07';

/// 时间线可选时段：06:00 ~ 23:00
const List<int> kTimelineHours = <int>[6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23];

/// 时间轴起始小时
const int kFirstHour = 6;

/// 时间轴结束小时（不含）
const int kEndHour = 24;

/// 时间轴的整点列数
const int kHoursCount = 18;

/// 排到时间线上时默认占用的时长（分钟）
const int kDefaultSlotMinutes = 60;

/// 时长允许范围，与「添加日程 / 详情」里的 5 ~ 600 分钟保持一致
const int kMinDuration = 5;
const int kMaxDuration = 600;

/// 删除标记的保留时长：超过之后不再随快照上传，避免列表无限增长。
const int kTombstoneTtl = 30 * 24 * 60 * 60 * 1000;

/// 数值兜底：无法转成有限数时返回 [fallback]
double toNumber(Object? value, double fallback) {
  if (value is num) {
    return value.isFinite ? value.toDouble() : fallback;
  }
  final parsed = double.tryParse('${value ?? ''}');
  return parsed != null && parsed.isFinite ? parsed : fallback;
}

/// 整数兜底
int toInt(Object? value, int fallback) => toNumber(value, fallback.toDouble()).round();

double clampDouble(num value, double min, double max) {
  if (value < min) return min.toDouble();
  if (value > max) return max.toDouble();
  return value.toDouble();
}

int clampInt(num value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value.round();
}
