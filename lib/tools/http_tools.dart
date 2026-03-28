/// HTTP request tool for FlutterClaw.
///
/// Supports arbitrary HTTP methods, headers, body, content-type formats,
/// query parameters, and optional SSL certificate verification bypass.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutterclaw/services/ssrf_guard.dart';

import 'registry.dart';

/// Generic HTTP request tool.
///
/// Exposes full control over method, URL, headers, body, content-type,
/// query params, SSL verification, and timeout.
class HttpRequestTool extends Tool {
  @override
  String get name => 'http_request';

  @override
  String get description =>
      'Make an HTTP/HTTPS request (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS). '
      'Supports JSON, XML, form-urlencoded, multipart, and plain-text bodies. '
      'Custom headers (e.g. Authorization), query parameters, optional SSL '
      'certificate verification bypass, and configurable timeout.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'Full URL including scheme (http:// or https://).',
          },
          'method': {
            'type': 'string',
            'enum': ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'],
            'description': 'HTTP method (default: GET).',
          },
          'headers': {
            'type': 'object',
            'description':
                'Key-value map of request headers. '
                'E.g. {"Authorization": "Bearer token", "X-Api-Key": "key"}.',
            'additionalProperties': {'type': 'string'},
          },
          'query_params': {
            'type': 'object',
            'description': 'Key-value map of URL query parameters.',
            'additionalProperties': {'type': 'string'},
          },
          'body': {
            'description':
                'Request body. Use a JSON object/array for content_type json, '
                'a plain string for xml/text, or a key-value object for '
                'form-urlencoded/multipart.',
          },
          'content_type': {
            'type': 'string',
            'enum': [
              'json',
              'xml',
              'form',
              'multipart',
              'text',
              'raw',
            ],
            'description':
                'Body format. '
                '"json" → application/json (default when body is present), '
                '"xml" → application/xml, '
                '"form" → application/x-www-form-urlencoded, '
                '"multipart" → multipart/form-data, '
                '"text" → text/plain, '
                '"raw" → sends body string as-is without setting Content-Type.',
          },
          'verify_ssl': {
            'type': 'boolean',
            'description':
                'Verify SSL/TLS certificate (default: true). '
                'Set to false to allow self-signed or invalid certificates.',
          },
          'timeout_seconds': {
            'type': 'integer',
            'description': 'Request timeout in seconds (default: 30).',
          },
          'max_response_chars': {
            'type': 'integer',
            'description': 'Maximum characters to return from the response body (default: 20000).',
          },
          'follow_redirects': {
            'type': 'boolean',
            'description': 'Follow HTTP redirects (default: true).',
          },
        },
        'required': ['url'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final urlStr = args['url'] as String?;
    if (urlStr == null || urlStr.isEmpty) {
      return ToolResult.error('url is required');
    }

    final ssrfError = validateFetchUrl(urlStr);
    if (ssrfError != null) return ToolResult.error(ssrfError);

    final method = ((args['method'] as String?) ?? 'GET').toUpperCase();
    final headers = _toStringMap(args['headers']);
    final queryParams = _toStringMap(args['query_params']);
    final body = args['body'];
    final contentTypeKey = (args['content_type'] as String?) ?? '';
    final verifySsl = args['verify_ssl'] as bool? ?? true;
    final timeoutSecs = args['timeout_seconds'] as int? ?? 30;
    final maxChars = args['max_response_chars'] as int? ?? 20000;
    final followRedirects = args['follow_redirects'] as bool? ?? true;

    // Build Dio instance with SSL configuration
    final dio = _buildDio(verifySsl: verifySsl, timeoutSecs: timeoutSecs);

    // Resolve Content-Type and encode body
    final resolved = _resolveBody(body, contentTypeKey, headers);
    final encodedBody = resolved.body;
    final finalHeaders = {...headers, ...resolved.extraHeaders};

    final options = Options(
      method: method,
      headers: finalHeaders.isEmpty ? null : finalHeaders,
      validateStatus: (_) => true, // never throw on HTTP error codes
      followRedirects: followRedirects,
      maxRedirects: followRedirects ? 5 : 0,
      responseType: ResponseType.plain,
    );

    try {
      final response = await dio.request<String>(
        urlStr,
        data: encodedBody,
        queryParameters: queryParams.isEmpty ? null : queryParams,
        options: options,
      );

      final statusCode = response.statusCode ?? 0;
      final responseHeaders = _formatResponseHeaders(response.headers);
      final rawBody = response.data ?? '';
      final truncated = rawBody.length > maxChars
          ? '${rawBody.substring(0, maxChars)}\n\n[... truncated, ${rawBody.length - maxChars} chars omitted]'
          : rawBody;

      final sb = StringBuffer();
      sb.writeln('HTTP $statusCode ${_statusText(statusCode)}');
      if (responseHeaders.isNotEmpty) {
        sb.writeln('\n--- Response Headers ---');
        sb.writeln(responseHeaders);
      }
      if (truncated.isNotEmpty) {
        sb.writeln('\n--- Response Body ---');
        sb.write(truncated);
      } else {
        sb.write('\n(empty body)');
      }

      // Surface as error result when server returned 4xx/5xx so the LLM
      // knows the request did not succeed, but include the full response.
      final isError = statusCode >= 400;
      return ToolResult(content: sb.toString(), isError: isError);
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return ToolResult.error('Request timed out after ${timeoutSecs}s: $msg');
      }
      if (e.type == DioExceptionType.badCertificate) {
        return ToolResult.error(
          'SSL certificate verification failed. '
          'Set verify_ssl: false to bypass (use with caution). Detail: $msg',
        );
      }
      return ToolResult.error('Request failed: $msg');
    } catch (e) {
      return ToolResult.error('Unexpected error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Dio _buildDio({required bool verifySsl, required int timeoutSecs}) {
    final timeout = Duration(seconds: timeoutSecs);
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );

    if (!verifySsl) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        },
      );
    }

    return dio;
  }

  _BodyResult _resolveBody(
    dynamic body,
    String contentTypeKey,
    Map<String, String> existingHeaders,
  ) {
    if (body == null) return _BodyResult(body: null, extraHeaders: {});

    // Detect content-type from existing headers if not specified
    final effectiveKey = contentTypeKey.isNotEmpty
        ? contentTypeKey
        : _detectContentTypeFromHeaders(existingHeaders);

    switch (effectiveKey) {
      case 'json':
        final encoded = body is String ? body : jsonEncode(body);
        return _BodyResult(
          body: encoded,
          extraHeaders: _headerIfAbsent(
            existingHeaders,
            'content-type',
            'application/json; charset=utf-8',
          ),
        );

      case 'xml':
        final encoded = body is String ? body : body.toString();
        return _BodyResult(
          body: encoded,
          extraHeaders: _headerIfAbsent(
            existingHeaders,
            'content-type',
            'application/xml; charset=utf-8',
          ),
        );

      case 'form':
        String encoded;
        if (body is Map) {
          encoded = body.entries
              .map((e) =>
                  '${Uri.encodeQueryComponent(e.key.toString())}='
                  '${Uri.encodeQueryComponent(e.value.toString())}')
              .join('&');
        } else {
          encoded = body.toString();
        }
        return _BodyResult(
          body: encoded,
          extraHeaders: _headerIfAbsent(
            existingHeaders,
            'content-type',
            'application/x-www-form-urlencoded',
          ),
        );

      case 'multipart':
        // Build FormData from a map
        if (body is Map) {
          final formData = FormData.fromMap(
            body.map((k, v) => MapEntry(k.toString(), v.toString())),
          );
          return _BodyResult(body: formData, extraHeaders: {});
        }
        return _BodyResult(body: body.toString(), extraHeaders: {});

      case 'text':
        return _BodyResult(
          body: body.toString(),
          extraHeaders: _headerIfAbsent(
            existingHeaders,
            'content-type',
            'text/plain; charset=utf-8',
          ),
        );

      case 'raw':
        return _BodyResult(body: body.toString(), extraHeaders: {});

      default:
        // Auto-detect: if body is a Map/List → JSON, else plain string
        if (body is Map || body is List) {
          return _BodyResult(
            body: jsonEncode(body),
            extraHeaders: _headerIfAbsent(
              existingHeaders,
              'content-type',
              'application/json; charset=utf-8',
            ),
          );
        }
        return _BodyResult(body: body.toString(), extraHeaders: {});
    }
  }

  String _detectContentTypeFromHeaders(Map<String, String> headers) {
    final ct = headers.entries
        .where((e) => e.key.toLowerCase() == 'content-type')
        .map((e) => e.value.toLowerCase())
        .firstOrNull ?? '';
    if (ct.contains('json')) return 'json';
    if (ct.contains('xml')) return 'xml';
    if (ct.contains('form-urlencoded')) return 'form';
    if (ct.contains('multipart')) return 'multipart';
    if (ct.contains('text/plain')) return 'text';
    return '';
  }

  Map<String, String> _headerIfAbsent(
    Map<String, String> existing,
    String key,
    String value,
  ) {
    final alreadySet = existing.keys.any((k) => k.toLowerCase() == key);
    return alreadySet ? {} : {key: value};
  }

  Map<String, String> _toStringMap(dynamic value) {
    if (value == null) return {};
    if (value is Map) {
      return Map.fromEntries(
        value.entries.map((e) => MapEntry(e.key.toString(), e.value.toString())),
      );
    }
    return {};
  }

  String _formatResponseHeaders(Headers headers) {
    final lines = <String>[];
    headers.forEach((name, values) {
      lines.add('$name: ${values.join(', ')}');
    });
    return lines.join('\n');
  }

  String _statusText(int code) {
    const texts = {
      200: 'OK', 201: 'Created', 204: 'No Content',
      301: 'Moved Permanently', 302: 'Found', 304: 'Not Modified',
      400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden',
      404: 'Not Found', 405: 'Method Not Allowed', 409: 'Conflict',
      422: 'Unprocessable Entity', 429: 'Too Many Requests',
      500: 'Internal Server Error', 502: 'Bad Gateway',
      503: 'Service Unavailable', 504: 'Gateway Timeout',
    };
    return texts[code] ?? '';
  }
}

class _BodyResult {
  final dynamic body;
  final Map<String, String> extraHeaders;
  const _BodyResult({required this.body, required this.extraHeaders});
}
