/// Heartbeat runner matching OpenClaw's heartbeat system.
///
/// Periodically reads HEARTBEAT.md and sends tasks to the agent loop.
/// Skips if HEARTBEAT.md is empty or only contains comments.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutterclaw/core/agent/agent_loop.dart';
import 'package:flutterclaw/data/models/config.dart';
import 'package:logging/logging.dart';

final _log = Logger('flutterclaw.heartbeat');

class HeartbeatRunner {
  final ConfigManager configManager;
  final AgentLoop agentLoop;

  Timer? _timer;
  bool _running = false;

  HeartbeatRunner({
    required this.configManager,
    required this.agentLoop,
  });

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;

    final config = configManager.config.heartbeat;
    if (!config.enabled || config.interval <= 0) {
      _log.info('Heartbeat disabled or interval=0, skipping');
      return;
    }

    _running = true;
    final intervalMinutes = config.interval.clamp(5, 1440);
    _log.info('Heartbeat started: every ${intervalMinutes}m');

    // Heartbeat must never block app startup: run first tick in background
    unawaited(_tick());

    _timer = Timer.periodic(Duration(minutes: intervalMinutes), (_) => _tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _log.info('Heartbeat stopped');
  }

  Future<void> _tick() async {
    if (!_running) return;

    try {
      final ws = await configManager.workspacePath;
      final file = File('$ws/HEARTBEAT.md');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final meaningful = content
          .split('\n')
          .where((l) =>
              l.trim().isNotEmpty &&
              !l.trim().startsWith('#') &&
              !l.trim().startsWith('//'))
          .join('\n')
          .trim();

      if (meaningful.isEmpty) return;

      _log.info('Heartbeat firing with ${meaningful.length} chars of tasks');

      await agentLoop.processMessage(
        'heartbeat:main',
        'Heartbeat: Read and execute the tasks in HEARTBEAT.md.\n\n$meaningful',
        channelType: 'system',
        chatId: 'heartbeat',
      );
    } catch (e, st) {
      _log.warning('Heartbeat tick failed: $e\n$st');
    }
  }
}
