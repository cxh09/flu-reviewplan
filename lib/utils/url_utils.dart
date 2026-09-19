/// 用户填写的链接归一化（对齐网页版 `src/utils/url.js`）。
///
/// 日程 / 待办的 link 会直接用于外部打开，如果放任 `javascript:`、`data:`
/// 这类协议进来就是一个可点击的注入点（表单校验拦得住，但导入的 JSON 绕得过去）。
/// 这里统一只放行 http / https。
String sanitizeLink(Object? raw) {
  final value = '${raw ?? ''}'.trim();
  if (value.isEmpty) return '';

  // 已经写了协议的：只放行 http / https
  if (RegExp(r'^[a-z][a-z\d+.-]*:', caseSensitive: false).hasMatch(value)) {
    final uri = Uri.tryParse(value);
    if (uri == null) return '';
    return (uri.scheme == 'http' || uri.scheme == 'https') ? value : '';
  }

  // 没写协议的裸域名：补上 https，否则会被当成相对路径
  if (!value.contains('.') || RegExp(r'\s').hasMatch(value)) return '';
  final uri = Uri.tryParse('https://$value');
  if (uri == null || uri.host.isEmpty) return '';
  return uri.toString();
}

/// 判断是否是合法的 http / https 链接（表单校验用）
bool isValidHttpLink(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  return sanitizeLink(trimmed).isNotEmpty;
}
