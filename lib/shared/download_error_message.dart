import 'package:dio/dio.dart';

/// Render a concise, user-facing message for a download failure.
///
/// - HTTP 4xx → `获取$noun失败(<code>)`
/// - HTTP 5xx → `服务器错误(<code>)`
/// - Timeout  → `网络超时`
/// - Connection error → `网络连接失败`
/// - Cancellation → `已取消`
/// - Anything else → [fallback]
String downloadErrorMessage(
  Object error, {
  String noun = '安装包',
  String fallback = '下载失败',
}) {
  if (error is! DioException) return fallback;
  switch (error.type) {
    case DioExceptionType.badResponse:
      final code = error.response?.statusCode;
      if (code == null) return fallback;
      if (code >= 500 && code < 600) return '服务器错误($code)';
      if (code >= 400 && code < 500) return '获取$noun失败($code)';
      return fallback;
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return '网络超时';
    case DioExceptionType.cancel:
      return '已取消';
    case DioExceptionType.connectionError:
      return '网络连接失败';
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return fallback;
  }
}
