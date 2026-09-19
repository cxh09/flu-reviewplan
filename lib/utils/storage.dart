import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地缓存（对齐网页版 `src/utils/storage.js` 的 localStorage 封装）。
///
/// 应用启动时先 [init]，之后所有读写都走内存里的 [SharedPreferences] 实例，
/// 这样 store 里可以保持同步读写的写法。
class AppStorage {
  AppStorage._();

  static SharedPreferences? _prefs;

  /// 存储键（与网页版保持一致，方便同一台设备上互相认数据）
  static const String dataKey = 'reviewplan:data:v1';
  static const String plazaKey = 'reviewplan:plaza:v1';
  static const String tombstonesKey = 'reviewplan:tombstones:v1';
  static const String themeKey = 'reviewplan:theme';
  static const String serverKey = 'reviewplan:server:v1';

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static String readText(String key, [String fallback = '']) {
    try {
      return _prefs?.getString(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static bool writeText(String key, String value) {
    try {
      _prefs?.setString(key, value);
      return true;
    } catch (_) {
      // 配额超限等：忽略，应用继续可用，只是这次没有落盘
      return false;
    }
  }

  static Object? readJson(String key, [Object? fallback]) {
    final raw = readText(key);
    if (raw.isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  static bool writeJson(String key, Object? value) {
    try {
      return writeText(key, jsonEncode(value));
    } catch (_) {
      return false;
    }
  }
}
