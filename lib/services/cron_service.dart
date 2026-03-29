import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterclaw/core/agent/subagent_registry.dart';
import 'package:flutterclaw/data/models/config.dart';
import 'package:flutterclaw/services/event_bus.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

final _log = Logger('flutterclaw.cron');
const _uuid = Uuid();

/// Execution status of the last run.
enum CronJobStatus { pending, running, success, failed }

class CronJob {
  final String id;
  final String name;
  final String task;
  final String? cronExpression;
  final Duration? interval;
  final bool repeat;        // false = run once then auto-delete
  final bool enabled;
  final DateTime createdAt;
  DateTime? lastRunAt;
  DateTime? nextRunAt;
  int runCount;
  CronJobStatus lastStatus;
  String? lastError;

  CronJob({
    String? id,
    required this.name,
    required this.task,
    this.cronExpression,
    this.interval,
    this.repeat = true,
    this.enabled = true,
    DateTime? createdAt,
    this.lastRunAt,
    this.nextRunAt,
    this.runCount = 0,
    this.lastStatus = CronJobStatus.pending,
    this.lastError,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'task': task,
        if (cronExpression != null) 'cron_expression': cronExpression,
        if (interval != null) 'interval_seconds': interval!.inSeconds,
        'repeat': repeat,
        'enabled': enabled,
        'created_at': createdAt.toIso8601String(),
        if (lastRunAt != null) 'last_run_at': lastRunAt!.toIso8601String(),
        if (nextRunAt != null) 'next_run_at': nextRunAt!.toIso8601String(),
        'run_count': runCount,
        'last_status': lastStatus.name,
        if (lastError != null) 'last_error': lastError,
      };

  factory CronJob.fromJson(Map<String, dynamic> json) => CronJob(
        id: json['id'] as String?,
        name: json['name'] as String,
        task: json['task'] as String,
        cronExpression: json['cron_expression'] as String?,
        interval: json['interval_seconds'] != null
            ? Duration(seconds: json['interval_seconds'] as int)
            : null,
        repeat: json['repeat'] as bool? ?? true,
        enabled: json['enabled'] as bool? ?? true,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        lastRunAt: json['last_run_at'] != null
            ? DateTime.parse(json['last_run_at'] as String)
            : null,
        nextRunAt: json['next_run_at'] != null
            ? DateTime.parse(json['next_run_at'] as String)
            : null,
        runCount: json['run_count'] as int? ?? 0,
        lastStatus: CronJobStatus.values.firstWhere(
          (s) => s.name == (json['last_status'] as String? ?? 'pending'),
          orElse: () => CronJobStatus.pending,
        ),
        lastError: json['last_error'] as String?,
      );

  /// Human-readable schedule string for display.
  String get scheduleDisplay {
    if (!repeat) {
      if (nextRunAt != null) {
        return 'once at ${nextRunAt!.toLocal().toString().substring(0, 16)}';
      }
      return 'once';
    }
    if (cronExpression != null) return cronExpression!;
    if (interval != null) {
      final secs = interval!.inSeconds;
      if (secs % 86400 == 0) return 'every ${secs ~/ 86400}d';
      if (secs % 3600 == 0) return 'every ${secs ~/ 3600}h';
      if (secs % 60 == 0) return 'every ${secs ~/ 60}m';
      return 'every ${secs}s';
    }
    return 'unscheduled';
  }
}

class CronService {
  final ConfigManager configManager;
  final List<CronJob> _jobs = [];
  Timer? _tickTimer;
  bool _running = false;

  /// Optional event bus — when set, job executions also publish events.
  EventBus? eventBus;

  CronService({required this.configManager});

  bool get isRunning => _running;
  List<CronJob> get jobs => List.unmodifiable(_jobs);

  Future<void> start() async {
    if (_running) return;
    _running = true;

    await _loadJobs();

    _tickTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _tick(),
    );

    _log.info('Cron service started with ${_jobs.length} job(s)');
  }

  Future<void> stop() async {
    _running = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    await _saveJobs();
    _log.info('Cron service stopped');
  }

  /// Add a job. Returns the job as stored (with computed nextRunAt).
  Future<CronJob> addJob(CronJob job) async {
    final now = DateTime.now();
    DateTime? next;
    if (job.nextRunAt != null) {
      // Explicit nextRunAt (e.g. from run_at param) — use as-is
      next = job.nextRunAt;
    } else if (job.cronExpression != null) {
      next = nextRunFromCron(job.cronExpression!, now);
    } else if (job.interval != null) {
      next = now.add(job.interval!);
    }

    final stored = CronJob(
      id: job.id,
      name: job.name,
      task: job.task,
      cronExpression: job.cronExpression,
      interval: job.interval,
      repeat: job.repeat,
      enabled: job.enabled,
      createdAt: job.createdAt,
      lastRunAt: job.lastRunAt,
      nextRunAt: next,
      runCount: job.runCount,
      lastStatus: job.lastStatus,
      lastError: job.lastError,
    );

    _jobs.add(stored);
    await _saveJobs();
    _log.info('Added cron job: ${stored.name} (${stored.id}) next=${stored.nextRunAt}');
    return stored;
  }

  Future<void> removeJob(String id) async {
    _jobs.removeWhere((j) => j.id == id);
    await _saveJobs();
    _log.info('Removed cron job: $id');
  }

  Future<void> updateJob(String id, {bool? enabled, String? task}) async {
    final idx = _jobs.indexWhere((j) => j.id == id);
    if (idx == -1) return;
    final job = _jobs[idx];
    _jobs[idx] = CronJob(
      id: job.id,
      name: job.name,
      task: task ?? job.task,
      cronExpression: job.cronExpression,
      interval: job.interval,
      repeat: job.repeat,
      enabled: enabled ?? job.enabled,
      createdAt: job.createdAt,
      lastRunAt: job.lastRunAt,
      nextRunAt: job.nextRunAt,
      runCount: job.runCount,
      lastStatus: job.lastStatus,
      lastError: job.lastError,
    );
    await _saveJobs();
  }

  Future<void> runJob(String id) async {
    final job = _jobs.where((j) => j.id == id).firstOrNull;
    if (job == null) return;
    await _executeJob(job);
  }

  Future<void> _tick() async {
    if (!_running) return;

    final now = DateTime.now();
    for (final job in List.of(_jobs)) {
      if (!job.enabled) continue;
      if (job.lastStatus == CronJobStatus.running) continue; // already running
      if (job.nextRunAt != null && now.isAfter(job.nextRunAt!)) {
        await _executeJob(job);
      }
    }
  }

  Future<void> _executeJob(CronJob job) async {
    _log.info('Executing cron job: ${job.name} (${job.id})');

    // Mark as running
    _updateJob(job.id, status: CronJobStatus.running);
    await _saveJobs();

    try {
      // Publish event to bus (for automation rules and logging).
      eventBus?.publish(AgentEvent(
        type: EventType.cron,
        source: 'cron:${job.id}',
        summary: 'Cron job "${job.name}" fired',
        payload: {'job_id': job.id, 'task': job.task},
      ));

      // Use SubagentLoopProxy (bound in agentLoopProvider at startup).
      await SubagentLoopProxy.instance.processMessage(
        'cron:${job.id}',
        'Scheduled task: ${job.task}\n\n'
        'Execute this task completely using available tools.\n'
        'To deliver the result:\n'
        '1. Call channel_sessions to find active channel sessions (Telegram, Discord, etc.).\n'
        '2. If a channel session exists, use the "message" tool with the chat_id to send the result there.\n'
        '3. Also call send_notification with the result and session_key="cron:${job.id}" '
        'so the user gets a push notification.',
      );

      final now = DateTime.now();
      final idx = _jobs.indexWhere((j) => j.id == job.id);
      if (idx == -1) return; // was deleted mid-run

      if (!job.repeat) {
        // One-shot: remove after successful execution
        _jobs.removeAt(idx);
        _log.info('One-shot cron job ${job.name} completed and removed');
      } else {
        // Recurring: schedule next run
        DateTime? next;
        if (job.cronExpression != null) {
          next = nextRunFromCron(job.cronExpression!, now);
        } else if (job.interval != null) {
          next = now.add(job.interval!);
        }
        _jobs[idx] = CronJob(
          id: job.id,
          name: job.name,
          task: job.task,
          cronExpression: job.cronExpression,
          interval: job.interval,
          repeat: job.repeat,
          enabled: job.enabled,
          createdAt: job.createdAt,
          lastRunAt: now,
          nextRunAt: next,
          runCount: job.runCount + 1,
          lastStatus: CronJobStatus.success,
          lastError: null,
        );
      }

      await _saveJobs();
    } catch (e) {
      _log.warning('Cron job ${job.name} failed: $e');
      final idx = _jobs.indexWhere((j) => j.id == job.id);
      if (idx != -1) {
        _jobs[idx] = CronJob(
          id: job.id,
          name: job.name,
          task: job.task,
          cronExpression: job.cronExpression,
          interval: job.interval,
          repeat: job.repeat,
          enabled: job.enabled,
          createdAt: job.createdAt,
          lastRunAt: DateTime.now(),
          nextRunAt: job.nextRunAt, // keep original nextRunAt for retry visibility
          runCount: job.runCount + 1,
          lastStatus: CronJobStatus.failed,
          lastError: e.toString().length > 300
              ? '${e.toString().substring(0, 300)}…'
              : e.toString(),
        );
        await _saveJobs();
      }
    }
  }

  void _updateJob(String id, {CronJobStatus? status}) {
    final idx = _jobs.indexWhere((j) => j.id == id);
    if (idx == -1) return;
    final job = _jobs[idx];
    _jobs[idx] = CronJob(
      id: job.id,
      name: job.name,
      task: job.task,
      cronExpression: job.cronExpression,
      interval: job.interval,
      repeat: job.repeat,
      enabled: job.enabled,
      createdAt: job.createdAt,
      lastRunAt: job.lastRunAt,
      nextRunAt: job.nextRunAt,
      runCount: job.runCount,
      lastStatus: status ?? job.lastStatus,
      lastError: job.lastError,
    );
  }

  Future<void> _loadJobs() async {
    try {
      final workspace = await configManager.workspacePath;
      final file = File('$workspace/cron/jobs.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _jobs.clear();
        _jobs.addAll(
            list.map((e) => CronJob.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      _log.warning('Failed to load cron jobs: $e');
    }
  }

  Future<void> _saveJobs() async {
    try {
      final workspace = await configManager.workspacePath;
      final dir = Directory('$workspace/cron');
      await dir.create(recursive: true);
      final file = File('${dir.path}/jobs.json');
      final encoder = const JsonEncoder.withIndent('  ');
      await file
          .writeAsString(encoder.convert(_jobs.map((j) => j.toJson()).toList()));
    } catch (e) {
      _log.warning('Failed to save cron jobs: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cron expression evaluation
  //
  // Supports standard 5-field syntax: "minute hour day month weekday"
  // - *         any value
  // - */n       every n units
  // - n         exact value
  // - n,m       list
  // - n-m       range
  // Weekday: 0=Sun, 1=Mon, ..., 6=Sat, 7=Sun (both 0 and 7 = Sunday)
  // ---------------------------------------------------------------------------

  /// Returns the next DateTime after [after] that matches [expression].
  /// Returns null if the expression is invalid or no match found within 1 year.
  static DateTime? nextRunFromCron(String expression, DateTime after) {
    final fields = expression.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) return null;

    var t =
        DateTime(after.year, after.month, after.day, after.hour, after.minute)
            .add(const Duration(minutes: 1));

    for (var i = 0; i < 527040; i++) {
      if (!_fieldMatches(fields[3], t.month, 1, 12)) {
        t = DateTime(t.year, t.month + 1, 1, 0, 0);
        continue;
      }

      final dayMatch =
          fields[2] == '*' || _fieldMatches(fields[2], t.day, 1, 31);
      final wdayMatch =
          fields[4] == '*' || _fieldMatchesWeekday(fields[4], t.weekday);

      final dayOk = (fields[2] == '*' && fields[4] == '*')
          ? true
          : (fields[2] != '*' && fields[4] != '*')
              ? dayMatch && wdayMatch
              : dayMatch || wdayMatch;

      if (!dayOk) {
        t = DateTime(t.year, t.month, t.day + 1, 0, 0);
        continue;
      }

      if (!_fieldMatches(fields[1], t.hour, 0, 23)) {
        t = DateTime(t.year, t.month, t.day, t.hour + 1, 0);
        continue;
      }

      if (!_fieldMatches(fields[0], t.minute, 0, 59)) {
        t = t.add(const Duration(minutes: 1));
        continue;
      }

      return t;
    }

    return null;
  }

  /// Validates a 5-field cron expression. Returns null if valid, error if not.
  static String? validateCronExpression(String expression) {
    final fields = expression.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) {
      return 'Expected 5 fields (minute hour day month weekday), got ${fields.length}';
    }
    for (final f in fields) {
      if (!RegExp(r'^[\d\*\/\-,]+$').hasMatch(f)) {
        return 'Invalid character in field "$f"';
      }
    }
    final next = nextRunFromCron(expression, DateTime.now());
    if (next == null) {
      return 'Expression produces no valid schedule within 1 year';
    }
    return null;
  }

  static bool _fieldMatches(String field, int value, int min, int max) {
    if (field == '*') return true;

    if (field.contains('/')) {
      final parts = field.split('/');
      final step = int.tryParse(parts[1]) ?? 1;
      if (step <= 0) return false;
      final start =
          parts[0] == '*' ? min : (int.tryParse(parts[0]) ?? min);
      for (var v = start; v <= max; v += step) {
        if (v == value) return true;
      }
      return false;
    }

    if (field.contains(',')) {
      return field.split(',').any((p) => int.tryParse(p.trim()) == value);
    }

    if (field.contains('-')) {
      final parts = field.split('-');
      final lo = int.tryParse(parts[0]) ?? min;
      final hi = int.tryParse(parts[1]) ?? max;
      return value >= lo && value <= hi;
    }

    return int.tryParse(field) == value;
  }

  static bool _fieldMatchesWeekday(String field, int dartWeekday) {
    final cronDay = dartWeekday == 7 ? 0 : dartWeekday;
    if (field == '*') return true;
    if (field == '7' && cronDay == 0) return true;
    return _fieldMatches(field, cronDay, 0, 7);
  }
}
