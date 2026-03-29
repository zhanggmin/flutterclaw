/// Watcher Service — detect changes in external resources and fire events.
///
/// Supported watcher types:
///   • **url** — polls a URL, detects content changes via hash comparison
///   • **file** — monitors a local file's modification time
///
/// When a change is detected, publishes a [EventType.watcher] event to the
/// [EventBus]. Combine with automation rules for "detect and act" workflows.
///
/// Pattern follows cron_service.dart: CRUD, persistent JSON storage,
/// periodic polling via Timer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutterclaw/data/models/config.dart';
import 'package:flutterclaw/services/event_bus.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

final _log = Logger('flutterclaw.watcher');
const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Watcher model
// ---------------------------------------------------------------------------

enum WatcherType { url, file }

enum WatcherStatus { pending, checking, changed, unchanged, error }

class Watcher {
  final String id;
  final String name;
  final WatcherType type;

  /// The target to watch: a URL for type=url, a file path for type=file.
  final String target;

  /// How often to check, in minutes.
  final int intervalMinutes;
  final bool enabled;
  final DateTime createdAt;

  /// SHA-256 hash of the last-seen content (for change detection).
  String? lastHash;
  DateTime? lastCheckedAt;
  DateTime? lastChangedAt;
  int changeCount;
  WatcherStatus lastStatus;
  String? lastError;

  Watcher({
    String? id,
    required this.name,
    required this.type,
    required this.target,
    this.intervalMinutes = 60,
    this.enabled = true,
    DateTime? createdAt,
    this.lastHash,
    this.lastCheckedAt,
    this.lastChangedAt,
    this.changeCount = 0,
    this.lastStatus = WatcherStatus.pending,
    this.lastError,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'target': target,
        'interval_minutes': intervalMinutes,
        'enabled': enabled,
        'created_at': createdAt.toIso8601String(),
        if (lastHash != null) 'last_hash': lastHash,
        if (lastCheckedAt != null)
          'last_checked_at': lastCheckedAt!.toIso8601String(),
        if (lastChangedAt != null)
          'last_changed_at': lastChangedAt!.toIso8601String(),
        'change_count': changeCount,
        'last_status': lastStatus.name,
        if (lastError != null) 'last_error': lastError,
      };

  factory Watcher.fromJson(Map<String, dynamic> json) => Watcher(
        id: json['id'] as String?,
        name: json['name'] as String,
        type: WatcherType.values.firstWhere(
          (t) => t.name == (json['type'] as String? ?? 'url'),
          orElse: () => WatcherType.url,
        ),
        target: json['target'] as String,
        intervalMinutes: json['interval_minutes'] as int? ?? 60,
        enabled: json['enabled'] as bool? ?? true,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        lastHash: json['last_hash'] as String?,
        lastCheckedAt: json['last_checked_at'] != null
            ? DateTime.parse(json['last_checked_at'] as String)
            : null,
        lastChangedAt: json['last_changed_at'] != null
            ? DateTime.parse(json['last_changed_at'] as String)
            : null,
        changeCount: json['change_count'] as int? ?? 0,
        lastStatus: WatcherStatus.values.firstWhere(
          (s) => s.name == (json['last_status'] as String? ?? 'pending'),
          orElse: () => WatcherStatus.pending,
        ),
        lastError: json['last_error'] as String?,
      );

  /// Human-readable interval display.
  String get intervalDisplay {
    if (intervalMinutes >= 1440 && intervalMinutes % 1440 == 0) {
      return 'every ${intervalMinutes ~/ 1440}d';
    }
    if (intervalMinutes >= 60 && intervalMinutes % 60 == 0) {
      return 'every ${intervalMinutes ~/ 60}h';
    }
    return 'every ${intervalMinutes}m';
  }
}

// ---------------------------------------------------------------------------
// Watcher Service
// ---------------------------------------------------------------------------

class WatcherService {
  final ConfigManager configManager;

  /// Event bus — set before calling [start].
  EventBus? eventBus;

  final List<Watcher> _watchers = [];
  Timer? _tickTimer;
  bool _running = false;

  /// HTTP client for URL watchers.
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 5);

  WatcherService({required this.configManager});

  bool get isRunning => _running;
  List<Watcher> get watchers => List.unmodifiable(_watchers);

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _loadWatchers();

    // Tick every minute; each watcher checks its own interval.
    _tickTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _tick(),
    );

    _log.info('Watcher service started with ${_watchers.length} watcher(s)');
  }

  Future<void> stop() async {
    _running = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    await _saveWatchers();
    _log.info('Watcher service stopped');
  }

  // -------------------------------------------------------------------------
  // CRUD
  // -------------------------------------------------------------------------

  Future<Watcher> addWatcher(Watcher watcher) async {
    _watchers.add(watcher);
    await _saveWatchers();
    _log.info('Added watcher: ${watcher.name} (${watcher.id}) '
        'type=${watcher.type.name} target=${watcher.target}');
    return watcher;
  }

  Future<void> removeWatcher(String id) async {
    _watchers.removeWhere((w) => w.id == id);
    await _saveWatchers();
    _log.info('Removed watcher: $id');
  }

  Future<void> updateWatcher(
    String id, {
    String? name,
    bool? enabled,
    int? intervalMinutes,
  }) async {
    final idx = _watchers.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    final w = _watchers[idx];
    _watchers[idx] = Watcher(
      id: w.id,
      name: name ?? w.name,
      type: w.type,
      target: w.target,
      intervalMinutes: intervalMinutes ?? w.intervalMinutes,
      enabled: enabled ?? w.enabled,
      createdAt: w.createdAt,
      lastHash: w.lastHash,
      lastCheckedAt: w.lastCheckedAt,
      lastChangedAt: w.lastChangedAt,
      changeCount: w.changeCount,
      lastStatus: w.lastStatus,
      lastError: w.lastError,
    );
    await _saveWatchers();
  }

  /// Force-check a specific watcher right now.
  Future<void> checkWatcher(String id) async {
    final w = _watchers.where((w) => w.id == id).firstOrNull;
    if (w == null) return;
    await _checkWatcher(w);
  }

  // -------------------------------------------------------------------------
  // Tick & check logic
  // -------------------------------------------------------------------------

  Future<void> _tick() async {
    if (!_running) return;

    final now = DateTime.now();
    for (final watcher in List.of(_watchers)) {
      if (!watcher.enabled) continue;
      if (watcher.lastStatus == WatcherStatus.checking) continue;

      // Check if enough time has passed since last check
      if (watcher.lastCheckedAt != null) {
        final elapsed = now.difference(watcher.lastCheckedAt!);
        if (elapsed.inMinutes < watcher.intervalMinutes) continue;
      }

      await _checkWatcher(watcher);
    }
  }

  Future<void> _checkWatcher(Watcher watcher) async {
    watcher.lastStatus = WatcherStatus.checking;

    try {
      final content = switch (watcher.type) {
        WatcherType.url => await _fetchUrl(watcher.target),
        WatcherType.file => await _readFile(watcher.target),
      };

      final newHash = sha256.convert(utf8.encode(content)).toString();
      final now = DateTime.now();
      watcher.lastCheckedAt = now;
      watcher.lastError = null;

      if (watcher.lastHash == null) {
        // First check — store baseline, no event
        watcher.lastHash = newHash;
        watcher.lastStatus = WatcherStatus.unchanged;
        _log.info('Watcher "${watcher.name}" baseline captured');
      } else if (newHash != watcher.lastHash) {
        // Content changed!
        watcher.lastHash = newHash;
        watcher.lastChangedAt = now;
        watcher.changeCount++;
        watcher.lastStatus = WatcherStatus.changed;

        _log.info('Watcher "${watcher.name}" detected change #${watcher.changeCount}');

        eventBus?.publish(AgentEvent(
          type: EventType.watcher,
          source: 'watcher:${watcher.id}',
          summary: 'Watcher "${watcher.name}" detected a change in ${watcher.type.name}: ${watcher.target}',
          payload: {
            'watcher_id': watcher.id,
            'watcher_name': watcher.name,
            'type': watcher.type.name,
            'target': watcher.target,
            'change_count': watcher.changeCount,
          },
        ));
      } else {
        watcher.lastStatus = WatcherStatus.unchanged;
      }
    } catch (e) {
      watcher.lastCheckedAt = DateTime.now();
      watcher.lastStatus = WatcherStatus.error;
      watcher.lastError = e.toString().length > 300
          ? '${e.toString().substring(0, 300)}…'
          : e.toString();
      _log.warning('Watcher "${watcher.name}" check failed: $e');
    }

    await _saveWatchers();
  }

  // -------------------------------------------------------------------------
  // Content fetchers
  // -------------------------------------------------------------------------

  Future<String> _fetchUrl(String url) async {
    final uri = Uri.parse(url);
    final request = await _httpClient.getUrl(uri);
    request.headers.set('User-Agent', 'FlutterClaw-Watcher/1.0');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return body;
  }

  Future<String> _readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }
    // For binary files, use mtime as the "content"
    final stat = await file.stat();
    final isText = await _isTextFile(file);
    if (isText) {
      return await file.readAsString();
    }
    return 'mtime:${stat.modified.toIso8601String()}:size:${stat.size}';
  }

  Future<bool> _isTextFile(File file) async {
    try {
      // Read first 512 bytes to check for binary content
      final raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(512);
      await raf.close();
      // Check for null bytes (binary indicator)
      return !bytes.any((b) => b == 0);
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<void> _loadWatchers() async {
    try {
      final ws = await configManager.workspacePath;
      final file = File('$ws/watcher/watchers.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _watchers.clear();
        _watchers.addAll(
          list.map((e) => Watcher.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      _log.warning('Failed to load watchers: $e');
    }
  }

  Future<void> _saveWatchers() async {
    try {
      final ws = await configManager.workspacePath;
      final dir = Directory('$ws/watcher');
      await dir.create(recursive: true);
      final file = File('${dir.path}/watchers.json');
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(
        encoder.convert(_watchers.map((w) => w.toJson()).toList()),
      );
    } catch (e) {
      _log.warning('Failed to save watchers: $e');
    }
  }
}
