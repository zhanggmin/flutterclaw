/// Battery monitoring service.
///
/// Wraps battery_plus to expose battery level and charging state.
/// The AgentLoop reads this to select lighter models on low battery.
library;

import 'package:battery_plus/battery_plus.dart';
import 'package:logging/logging.dart';

final _log = Logger('flutterclaw.battery');

class BatteryService {
  final _battery = Battery();

  /// Returns the current battery level as a percentage (0–100), or 100 if
  /// the platform doesn't support battery info (desktop/web).
  Future<int> getBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      _log.fine('Battery level unavailable: $e');
      return 100;
    }
  }

  /// Returns true if the device is currently charging or on AC power.
  Future<bool> isCharging() async {
    try {
      final state = await _battery.batteryState;
      return state == BatteryState.charging || state == BatteryState.full;
    } catch (e) {
      _log.fine('Battery state unavailable: $e');
      return true; // assume charging to avoid unnecessary restrictions
    }
  }

  /// Returns a concise runtime context string for the system prompt, e.g.:
  /// "Battery: 18% (not charging)"
  Future<String?> buildRuntimeContext() async {
    try {
      final level = await getBatteryLevel();
      final charging = await isCharging();
      if (charging) return null; // no restriction needed
      if (level > 30) return null; // healthy — no need to mention
      final status = charging ? 'charging' : 'not charging';
      return 'Battery: $level% ($status)';
    } catch (_) {
      return null;
    }
  }
}
