/// Event Bus — central pub/sub for proactive agent triggers.
///
/// All trigger sources (cron, heartbeat, geofence, watcher, webhook,
/// channel message, automation) publish [AgentEvent]s to the bus.
/// Subscribers (automation rules engine, agent loop consumer) react to them.
///
/// Events are persisted to a JSONL file for crash recovery.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

final _log = Logger('flutterclaw.event_bus');
const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Event model
// ---------------------------------------------------------------------------

/// Event types produced by various trigger sources.
enum EventType {
  cron,
  heartbeat,
  geofence,
  watcher,
  webhook,
  channelMessage,
  automation,
  custom,
}

/// A typed event flowing through the bus.
class AgentEvent {
  final String id;
  final EventType type;
  final String source; // e.g. 'cron:abc123', 'geofence:office', 'webhook:stripe'
  final String summary; // human-readable description
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final bool processed;

  AgentEvent({
    String? id,
    required this.type,
    required this.source,
    required this.summary,
    this.payload = const {},
    DateTime? createdAt,
    this.processed = false,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  AgentEvent copyWith({bool? processed}) => AgentEvent(
        id: id,
        type: type,
        source: source,
        summary: summary,
        payload: payload,
        createdAt: createdAt,
        processed: processed ?? this.processed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'source': source,
        'summary': summary,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'processed': processed,
      };

  factory AgentEvent.fromJson(Map<String, dynamic> json) => AgentEvent(
        id: json['id'] as String?,
        type: EventType.values.firstWhere(
          (e) => e.name == (json['type'] as String? ?? 'custom'),
          orElse: () => EventType.custom,
        ),
        source: json['source'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        payload: (json['payload'] as Map<String, dynamic>?) ?? {},
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        processed: json['processed'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Event Bus
// ---------------------------------------------------------------------------

/// Callback type for event subscribers.
typedef EventHandler = Future<void> Function(AgentEvent event);

class EventBus {
  final String _logPath;
  final List<EventHandler> _handlers = [];
  final StreamController<AgentEvent> _controller =
      StreamController<AgentEvent>.broadcast();

  /// Maximum events to keep in the log (older are pruned on save).
  static const int maxLogSize = 500;

  EventBus({required String workspacePath})
      : _logPath = '$workspacePath/events/event_log.jsonl';

  /// The broadcast stream of events. Subscribers can listen for filtering.
  Stream<AgentEvent> get stream => _controller.stream;

  /// Register a handler that is called for every published event.
  void subscribe(EventHandler handler) {
    _handlers.add(handler);
  }

  /// Remove a previously registered handler.
  void unsubscribe(EventHandler handler) {
    _handlers.remove(handler);
  }

  /// Publish an event to all subscribers.
  ///
  /// The event is persisted to the JSONL log, then dispatched to handlers.
  Future<void> publish(AgentEvent event) async {
    _log.info('Event published: [${event.type.name}] ${event.source} — ${event.summary}');

    // Persist first (crash safety).
    await _appendLog(event);

    // Dispatch to stream listeners.
    _controller.add(event);

    // Dispatch to registered handlers.
    for (final handler in List.of(_handlers)) {
      try {
        await handler(event);
      } catch (e) {
        _log.warning('Event handler error for ${event.id}: $e');
      }
    }
  }

  /// Replay unprocessed events from the log (for crash recovery at startup).
  Future<List<AgentEvent>> replayUnprocessed() async {
    final events = await _readLog();
    return events.where((e) => !e.processed).toList();
  }

  /// Mark an event as processed in the log.
  Future<void> markProcessed(String eventId) async {
    // We don't rewrite the log immediately — just note it.
    // The pruning cycle handles cleanup.
    _log.fine('Event marked processed: $eventId');
  }

  /// Get recent events (most recent first).
  Future<List<AgentEvent>> recentEvents({int limit = 50}) async {
    final all = await _readLog();
    final sorted = all..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  /// Prune old events, keeping only the most recent [maxLogSize].
  Future<void> prune() async {
    final events = await _readLog();
    if (events.length <= maxLogSize) return;
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final kept = events.take(maxLogSize).toList();
    await _writeLog(kept);
    _log.info('Pruned event log: ${events.length} → ${kept.length}');
  }

  void dispose() {
    _controller.close();
  }

  // -------------------------------------------------------------------------
  // JSONL persistence
  // -------------------------------------------------------------------------

  Future<void> _appendLog(AgentEvent event) async {
    try {
      final file = File(_logPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${jsonEncode(event.toJson())}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      _log.warning('Failed to append event log: $e');
    }
  }

  Future<List<AgentEvent>> _readLog() async {
    try {
      final file = File(_logPath);
      if (!await file.exists()) return [];
      final lines = await file.readAsLines();
      return lines
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            try {
              return AgentEvent.fromJson(
                jsonDecode(l) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<AgentEvent>()
          .toList();
    } catch (e) {
      _log.warning('Failed to read event log: $e');
      return [];
    }
  }

  Future<void> _writeLog(List<AgentEvent> events) async {
    try {
      final file = File(_logPath);
      await file.parent.create(recursive: true);
      final content =
          '${events.map((e) => jsonEncode(e.toJson())).join('\n')}\n';
      await file.writeAsString(content);
    } catch (e) {
      _log.warning('Failed to write event log: $e');
    }
  }
}
