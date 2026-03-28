/// Auth profile service — multi-credential round-robin rotation with cooldown.
///
/// Port of OpenClaw's agents/auth-profiles/ (types.ts, credential-state.ts,
/// order.ts, usage.ts). Profiles are persisted in the workspace as JSON and
/// their secrets are stored in [SecureKeyStore].
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutterclaw/data/models/auth_profile.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

final _log = Logger('flutterclaw.auth_profiles');
const _uuid = Uuid();

/// Cooldown durations matching OpenClaw's failover policy.
const _kCooldownRateLimitMs = 60 * 1000; // 1 min
const _kCooldownOverloadMs = 5 * 60 * 1000; // 5 min
const _kCooldownServerErrorMs = 2 * 60 * 1000; // 2 min

class AuthProfileService {
  final String _profilesFilePath;
  final Future<String?> Function(String id) _readKey;
  final Future<void> Function(String id, String key) _writeKey;
  final Future<void> Function(String id) _deleteKey;

  final Map<String, List<AuthProfile>> _profilesByProvider = {};

  /// Round-robin index per provider.
  final Map<String, int> _lastUsedIndex = {};

  AuthProfileService({
    required String profilesFilePath,
    required Future<String?> Function(String id) readKey,
    required Future<void> Function(String id, String key) writeKey,
    required Future<void> Function(String id) deleteKey,
  })  : _profilesFilePath = profilesFilePath,
        _readKey = readKey,
        _writeKey = writeKey,
        _deleteKey = deleteKey;

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final file = File(_profilesFilePath);
    if (!await file.exists()) return;
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _profilesByProvider.clear();
      for (final item in list) {
        final profile = AuthProfile.fromJson(item as Map<String, dynamic>);
        _profilesByProvider.putIfAbsent(profile.provider, () => []).add(profile);
      }
      _log.info(
        'Loaded ${_profilesByProvider.values.expand((l) => l).length} auth profiles',
      );
    } catch (e) {
      _log.warning('Failed to load auth profiles: $e');
    }
  }

  Future<void> _save() async {
    final all = _profilesByProvider.values.expand((l) => l).toList();
    final file = File(_profilesFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(all.map((p) => p.toJson()).toList()),
    );
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<AuthProfile> addProfile({
    required String provider,
    required String apiKey,
    required String displayName,
  }) async {
    final id = 'ap_${_uuid.v4().replaceAll('-', '').substring(0, 12)}';
    final profile = AuthProfile(id: id, provider: provider, displayName: displayName);
    await _writeKey(id, apiKey);
    _profilesByProvider.putIfAbsent(provider, () => []).add(profile);
    await _save();
    _log.info('Added auth profile: $id ($provider / $displayName)');
    return profile;
  }

  Future<void> removeProfile(String id) async {
    for (final list in _profilesByProvider.values) {
      list.removeWhere((p) => p.id == id);
    }
    await _deleteKey(id);
    await _save();
    _log.info('Removed auth profile: $id');
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    final profile = _findById(id);
    if (profile == null) return;
    profile.enabled = enabled;
    await _save();
  }

  List<AuthProfile> profilesFor(String provider) =>
      List.unmodifiable(_profilesByProvider[provider] ?? []);

  AuthProfile? _findById(String id) => _profilesByProvider.values
      .expand((l) => l)
      .where((p) => p.id == id)
      .firstOrNull;

  // ---------------------------------------------------------------------------
  // Rotation
  // ---------------------------------------------------------------------------

  /// Returns the next eligible [apiKey] for [provider] using round-robin,
  /// or null if no profiles are configured/eligible for that provider.
  Future<String?> resolveApiKey(String provider) async {
    final profiles = _profilesByProvider[provider] ?? [];
    if (profiles.isEmpty) return null;

    final eligible = profiles.where((p) => p.isEligible).toList();
    if (eligible.isEmpty) {
      _log.warning(
        'All $provider profiles are on cooldown — using first enabled profile anyway',
      );
      final any = profiles.where((p) => p.enabled).toList();
      if (any.isEmpty) return null;
      return _readKey(any.first.id);
    }

    // Round-robin across eligible profiles
    final idx = (_lastUsedIndex[provider] ?? -1) + 1;
    final next = eligible[idx % eligible.length];
    _lastUsedIndex[provider] = idx % eligible.length;

    next.lastUsedMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
    return _readKey(next.id);
  }

  /// Records a successful API call for the most-recently used profile.
  Future<void> reportSuccess(String provider) async {
    final idx = _lastUsedIndex[provider];
    final profiles = _profilesByProvider[provider] ?? [];
    final eligible = profiles.where((p) => p.isEligible).toList();
    if (idx == null || eligible.isEmpty) return;
    final profile = eligible[idx % eligible.length];
    profile.errorCount = 0;
    profile.cooldownUntilMs = 0;
    profile.cooldownReason = null;
    await _save();
  }

  /// Puts the most-recently used profile for [provider] on cooldown.
  Future<void> reportFailure(String provider, CooldownReason reason) async {
    final idx = _lastUsedIndex[provider];
    final profiles = _profilesByProvider[provider] ?? [];
    if (idx == null || profiles.isEmpty) return;
    final eligible = profiles.where((p) => p.isEligible).toList();
    if (eligible.isEmpty) return;
    final profile = eligible[idx % eligible.length];

    profile.errorCount++;
    profile.cooldownReason = reason;
    final durationMs = switch (reason) {
      CooldownReason.rateLimited => _kCooldownRateLimitMs,
      CooldownReason.overloaded => _kCooldownOverloadMs,
      CooldownReason.serverError => _kCooldownServerErrorMs,
    };
    profile.cooldownUntilMs =
        DateTime.now().millisecondsSinceEpoch + durationMs;
    _log.info(
      'Profile ${profile.id} on cooldown: ${reason.name} for ${durationMs ~/ 1000}s',
    );
    await _save();
  }

  bool hasProfilesFor(String provider) =>
      (_profilesByProvider[provider]?.isNotEmpty) ?? false;
}
