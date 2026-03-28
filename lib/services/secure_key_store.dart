import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyStore {
  static const _storage = FlutterSecureStorage();

  static const _keyPrefix = 'api_key_';

  static String _key(String provider) => '$_keyPrefix$provider';

  static Future<void> saveApiKey(String provider, String apiKey) async {
    await _storage.write(key: _key(provider), value: apiKey);
  }

  static Future<String?> getApiKey(String provider) async {
    return _storage.read(key: _key(provider));
  }

  static Future<void> deleteApiKey(String provider) async {
    await _storage.delete(key: _key(provider));
  }

  static Future<bool> hasApiKey(String provider) async {
    final key = await _storage.read(key: _key(provider));
    return key != null && key.isNotEmpty;
  }

  static Future<Map<String, String>> getAllApiKeys() async {
    final all = await _storage.readAll();
    final result = <String, String>{};
    for (final entry in all.entries) {
      if (entry.key.startsWith(_keyPrefix)) {
        final provider = entry.key.substring(_keyPrefix.length);
        result[provider] = entry.value;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Generic named secrets (used by AuthProfileService and SecretsResolver)
  // ---------------------------------------------------------------------------

  static const _secretPrefix = 'secret_';

  static Future<void> saveSecret(String name, String value) async {
    await _storage.write(key: '$_secretPrefix$name', value: value);
  }

  static Future<String?> getSecret(String name) async {
    return _storage.read(key: '$_secretPrefix$name');
  }

  static Future<void> deleteSecret(String name) async {
    await _storage.delete(key: '$_secretPrefix$name');
  }
}
