/// Secrets resolver — resolves $ref references in config values.
///
/// Inspired by OpenClaw's secrets/ system. Allows workspace config files
/// to reference secrets by name instead of inlining keys:
///
///   {"$ref": "secrets/my-api-key"}   → looks up key in SecureKeyStore
///   {"$ref": "env:MY_API_KEY"}       → reads environment variable
///
/// This lets users share agent workspace configs safely.
library;

import 'dart:io';

import 'package:logging/logging.dart';

final _log = Logger('flutterclaw.secrets_resolver');

const _kSecretsPrefix = 'secrets/';
const _kEnvPrefix = 'env:';

class SecretsResolver {
  final Future<String?> Function(String name) _readSecret;

  /// Per-session resolution cache — cleared on dispose.
  final Map<String, String?> _cache = {};

  /// Audit log: names of secrets resolved this session (never values).
  final List<String> _auditLog = [];

  SecretsResolver({required Future<String?> Function(String name) readSecret})
      : _readSecret = readSecret;

  List<String> get auditLog => List.unmodifiable(_auditLog);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Resolves a value that may contain a `{"$ref": "..."}` reference.
  ///
  /// If [value] is a Map with a single `$ref` key, resolves the reference.
  /// Otherwise returns [value] unchanged (including plain strings).
  Future<dynamic> resolve(dynamic value) async {
    if (value is! Map) return value;
    final ref = value[r'$ref'];
    if (ref is! String || ref.isEmpty) return value;
    return _resolveRef(ref);
  }

  /// Resolves a plain ref string like "secrets/my-key" or "env:MY_KEY".
  Future<String?> resolveRef(String ref) => _resolveRef(ref);

  /// Recursively resolves all `$ref` values in a Map or List.
  Future<dynamic> resolveDeep(dynamic value) async {
    if (value is Map) {
      final ref = value[r'$ref'];
      if (ref is String && ref.isNotEmpty) return _resolveRef(ref);
      final resolved = <String, dynamic>{};
      for (final entry in value.entries) {
        resolved[entry.key as String] = await resolveDeep(entry.value);
      }
      return resolved;
    }
    if (value is List) {
      return [for (final item in value) await resolveDeep(item)];
    }
    return value;
  }

  void clearCache() => _cache.clear();

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<String?> _resolveRef(String ref) async {
    if (_cache.containsKey(ref)) return _cache[ref];

    String? result;
    if (ref.startsWith(_kEnvPrefix)) {
      final envKey = ref.substring(_kEnvPrefix.length);
      result = Platform.environment[envKey];
      if (result == null) {
        _log.warning('Secrets resolver: env var "$envKey" not found');
      } else {
        _log.fine('Secrets resolver: resolved env:$envKey');
        _auditLog.add('env:$envKey');
      }
    } else if (ref.startsWith(_kSecretsPrefix)) {
      final name = ref.substring(_kSecretsPrefix.length);
      result = await _readSecret(name);
      if (result == null) {
        _log.warning('Secrets resolver: secret "$name" not found');
      } else {
        _log.fine('Secrets resolver: resolved secrets/$name');
        _auditLog.add('secrets/$name');
      }
    } else {
      _log.warning('Secrets resolver: unknown ref format "$ref"');
    }

    _cache[ref] = result;
    return result;
  }
}
