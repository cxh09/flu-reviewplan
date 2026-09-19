import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 服务端同步的 HTTP 客户端（对齐网页版 `src/utils/api.js`）。
///
/// 所有请求都基于「设置」里填写的服务端地址拼出，地址为空时直接抛错，
/// 由调用方提示用户先配置。

/// 请求超时时间
const Duration kApiTimeout = Duration(seconds: 10);

/// 归一化服务端地址：
/// - 去掉首尾空白
/// - 没写协议时默认补 http://
/// - 去掉结尾多余的斜杠
///
/// 返回空字符串表示未配置。
String normalizeServerUrl(Object? raw) {
  final trimmed = '${raw ?? ''}'.trim();
  if (trimmed.isEmpty) return '';

  final withProtocol =
      RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
          ? trimmed
          : 'http://$trimmed';
  return withProtocol.replaceAll(RegExp(r'/+$'), '');
}

/// 服务端交互异常
class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.code = 'ERROR', this.payload});

  final String message;
  final int status;
  final String code;
  final Object? payload;

  /// 版本冲突（上传时服务端已有更新的数据）
  bool get isConflict => status == 409 || code == 'CONFLICT';

  /// 访问令牌无效 / 未提供
  bool get isUnauthorized => status == 401;

  /// 连不上服务端
  bool get isNetworkError => status == 0;

  @override
  String toString() => message;
}

/// 统一的请求封装：超时、JSON 解析、错误转换。
class ApiClient {
  ApiClient._();

  static Future<Map<String, dynamic>?> request(
    String baseUrl,
    String path, {
    String method = 'GET',
    Object? body,
    String token = '',
    Duration timeout = kApiTimeout,
  }) async {
    final base = normalizeServerUrl(baseUrl);
    if (base.isEmpty) {
      throw ApiException('未配置服务端地址', code: 'NO_SERVER');
    }

    final uri = Uri.parse('$base$path');
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    http.Response response;
    try {
      if (method == 'PUT') {
        response = await http
            .put(uri, headers: headers, body: jsonEncode(body))
            .timeout(timeout);
      } else if (method == 'POST') {
        response = await http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(timeout);
      } else {
        response = await http.get(uri, headers: headers).timeout(timeout);
      }
    } on TimeoutException {
      throw ApiException('请求超时，请检查服务端地址与网络', code: 'TIMEOUT');
    } catch (_) {
      throw ApiException('无法连接服务端，请检查地址与网络', code: 'NETWORK');
    }

    final text = response.body;
    Map<String, dynamic>? payload;
    if (text.isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) payload = decoded.cast<String, dynamic>();
      } catch (_) {
        payload = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        '${payload?['error'] ?? '服务端返回 ${response.statusCode}'}',
        status: response.statusCode,
        code: '${payload?['code'] ?? 'HTTP_ERROR'}',
        payload: payload,
      );
    }

    return payload;
  }

  /// 健康检查
  static Future<Map<String, dynamic>?> fetchHealth(String baseUrl, String token) =>
      request(baseUrl, '/api/health', token: token);

  /// 拉取整份快照
  static Future<Map<String, dynamic>?> fetchSnapshot(String baseUrl, String token) =>
      request(baseUrl, '/api/data', token: token);

  /// 只拉版本号：轮询「云端是否变了」用，比整份快照轻得多
  static Future<Map<String, dynamic>?> fetchRev(String baseUrl, String token) =>
      request(baseUrl, '/api/rev', token: token);

  /// 上传整份快照。
  /// [rev] 传数字时做乐观锁冲突检测；传 null 表示强制覆盖（不做校验）。
  static Future<Map<String, dynamic>?> putSnapshot(
    String baseUrl,
    String token,
    Map<String, dynamic> data,
    int? rev,
  ) {
    return request(
      baseUrl,
      '/api/data',
      method: 'PUT',
      body: <String, dynamic>{'data': data, 'rev': rev},
      token: token,
    );
  }

  /// 创建分享链接：登记一个日期范围，返回含随机 `code`。
  static Future<Map<String, dynamic>?> createShare(
    String baseUrl,
    String token,
    String dateStart,
    String dateEnd,
  ) {
    return request(
      baseUrl,
      '/api/shares',
      method: 'POST',
      body: <String, dynamic>{'dateStart': dateStart, 'dateEnd': dateEnd},
      token: token,
    );
  }
}
