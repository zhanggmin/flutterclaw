/// Watcher CRUD tools for FlutterClaw agents.
///
/// watch_create / watch_list / watch_delete / watch_update / watch_check.
/// Watchers monitor external resources for changes and fire events on the EventBus.
library;

import 'dart:convert';

import 'package:flutterclaw/services/watcher_service.dart';
import 'package:flutterclaw/tools/registry.dart';

// ---------------------------------------------------------------------------
// watch_create
// ---------------------------------------------------------------------------

class WatchCreateTool extends Tool {
  final WatcherService watcherService;

  WatchCreateTool({required this.watcherService});

  @override
  String get name => 'watch_create';

  @override
  String get description =>
      'Create a watcher that monitors a resource for changes and fires events.\n\n'
      'Watcher types:\n'
      '  • url — polls a web page/API endpoint, detects content changes via hash\n'
      '  • file — monitors a local file for modifications\n\n'
      'Examples:\n'
      '  • "Watch this product page for price drops" → type: url, target: URL, interval: 60\n'
      '  • "Watch the log file for new entries" → type: file, target: /path/to/file\n\n'
      'Combine with automation_create (event_type: "watcher") to trigger actions '
      'when a change is detected. Always end automation tasks with '
      '"then call send_notification with the result".';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Human-readable name (e.g. "Product price tracker")',
          },
          'type': {
            'type': 'string',
            'enum': ['url', 'file'],
            'description': 'What to watch: "url" for web pages/APIs, "file" for local files',
          },
          'target': {
            'type': 'string',
            'description': 'The URL or file path to monitor',
          },
          'interval_minutes': {
            'type': 'integer',
            'minimum': 5,
            'description':
                'How often to check, in minutes (default 60). Minimum 5 minutes.',
            'default': 60,
          },
        },
        'required': ['name', 'type', 'target'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final watcherName = (args['name'] as String?)?.trim() ?? '';
    if (watcherName.isEmpty) return ToolResult.error('name is required');

    final typeStr = (args['type'] as String?)?.trim() ?? '';
    if (typeStr.isEmpty) return ToolResult.error('type is required');

    final watcherType = switch (typeStr) {
      'url' => WatcherType.url,
      'file' => WatcherType.file,
      _ => null,
    };
    if (watcherType == null) {
      return ToolResult.error('type must be "url" or "file"');
    }

    final target = (args['target'] as String?)?.trim() ?? '';
    if (target.isEmpty) return ToolResult.error('target is required');

    // Validate URL format
    if (watcherType == WatcherType.url) {
      final uri = Uri.tryParse(target);
      if (uri == null || !uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return ToolResult.error('target must be a valid http/https URL');
      }
    }

    final intervalRaw = args['interval_minutes'];
    final interval = intervalRaw is num ? intervalRaw.toInt() : 60;
    if (interval < 5) {
      return ToolResult.error('interval_minutes must be at least 5');
    }

    final watcher = Watcher(
      name: watcherName,
      type: watcherType,
      target: target,
      intervalMinutes: interval,
    );

    final stored = await watcherService.addWatcher(watcher);

    return ToolResult.success(jsonEncode({
      'ok': true,
      'id': stored.id,
      'name': stored.name,
      'type': stored.type.name,
      'target': stored.target,
      'interval': stored.intervalDisplay,
      'message':
          'Watcher "${stored.name}" created. It will check ${stored.type.name} '
              '"${stored.target}" ${stored.intervalDisplay}. '
              'The first check captures a baseline; subsequent changes fire events. '
              'Create an automation rule with event_type "watcher" and '
              'source_pattern "${stored.id}" to trigger tasks on change.',
    }));
  }
}

// ---------------------------------------------------------------------------
// watch_list
// ---------------------------------------------------------------------------

class WatchListTool extends Tool {
  final WatcherService watcherService;

  WatchListTool({required this.watcherService});

  @override
  String get name => 'watch_list';

  @override
  String get description =>
      'List all watchers with their status, check history, and change counts.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final watchers = watcherService.watchers;

    final list = watchers.map((w) {
      return {
        'id': w.id,
        'name': w.name,
        'type': w.type.name,
        'target': w.target.length > 100
            ? '${w.target.substring(0, 100)}…'
            : w.target,
        'interval': w.intervalDisplay,
        'enabled': w.enabled,
        'status': w.lastStatus.name,
        'change_count': w.changeCount,
        'last_checked': w.lastCheckedAt?.toIso8601String(),
        'last_changed': w.lastChangedAt?.toIso8601String(),
        if (w.lastError != null) 'last_error': w.lastError,
      };
    }).toList();

    return ToolResult.success(jsonEncode({
      'ok': true,
      'count': list.length,
      'watchers': list,
    }));
  }
}

// ---------------------------------------------------------------------------
// watch_delete
// ---------------------------------------------------------------------------

class WatchDeleteTool extends Tool {
  final WatcherService watcherService;

  WatchDeleteTool({required this.watcherService});

  @override
  String get name => 'watch_delete';

  @override
  String get description =>
      'Delete a watcher by id. Use watch_list to find the id first.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'The id of the watcher to delete',
          },
        },
        'required': ['id'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) return ToolResult.error('id is required');

    final existing =
        watcherService.watchers.where((w) => w.id == id).firstOrNull;
    if (existing == null) {
      return ToolResult.error('No watcher found with id "$id"');
    }

    await watcherService.removeWatcher(id);

    return ToolResult.success(jsonEncode({
      'ok': true,
      'deleted_id': id,
      'deleted_name': existing.name,
      'message': 'Watcher "${existing.name}" deleted.',
    }));
  }
}

// ---------------------------------------------------------------------------
// watch_update
// ---------------------------------------------------------------------------

class WatchUpdateTool extends Tool {
  final WatcherService watcherService;

  WatchUpdateTool({required this.watcherService});

  @override
  String get name => 'watch_update';

  @override
  String get description =>
      'Enable, disable, rename, or change the interval of an existing watcher. '
      'Use watch_list to find the id first.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'The id of the watcher to update',
          },
          'name': {
            'type': 'string',
            'description': 'New name for the watcher',
          },
          'enabled': {
            'type': 'boolean',
            'description': 'true to enable, false to disable',
          },
          'interval_minutes': {
            'type': 'integer',
            'minimum': 5,
            'description': 'New check interval in minutes',
          },
        },
        'required': ['id'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) return ToolResult.error('id is required');

    final existing =
        watcherService.watchers.where((w) => w.id == id).firstOrNull;
    if (existing == null) {
      return ToolResult.error('No watcher found with id "$id"');
    }

    final newName = (args['name'] as String?)?.trim();
    final enabled = args['enabled'] as bool?;
    final intervalRaw = args['interval_minutes'];
    final interval = intervalRaw is num ? intervalRaw.toInt() : null;

    if (interval != null && interval < 5) {
      return ToolResult.error('interval_minutes must be at least 5');
    }

    if (newName == null && enabled == null && interval == null) {
      return ToolResult.error(
        'Provide at least one of: name, enabled, interval_minutes',
      );
    }

    await watcherService.updateWatcher(
      id,
      name: newName,
      enabled: enabled,
      intervalMinutes: interval,
    );

    return ToolResult.success(jsonEncode({
      'ok': true,
      'id': id,
      'name': newName ?? existing.name,
      'enabled': enabled ?? existing.enabled,
      'message': 'Watcher "${newName ?? existing.name}" updated.',
    }));
  }
}

// ---------------------------------------------------------------------------
// watch_check
// ---------------------------------------------------------------------------

class WatchCheckTool extends Tool {
  final WatcherService watcherService;

  WatchCheckTool({required this.watcherService});

  @override
  String get name => 'watch_check';

  @override
  String get description =>
      'Force an immediate check of a watcher, regardless of its interval. '
      'Use watch_list to find the id first.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'The id of the watcher to check now',
          },
        },
        'required': ['id'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) return ToolResult.error('id is required');

    final existing =
        watcherService.watchers.where((w) => w.id == id).firstOrNull;
    if (existing == null) {
      return ToolResult.error('No watcher found with id "$id"');
    }

    await watcherService.checkWatcher(id);

    // Re-read after check
    final updated =
        watcherService.watchers.where((w) => w.id == id).firstOrNull;

    return ToolResult.success(jsonEncode({
      'ok': true,
      'id': id,
      'name': updated?.name ?? existing.name,
      'status': updated?.lastStatus.name ?? 'unknown',
      'change_count': updated?.changeCount ?? existing.changeCount,
      if (updated?.lastError != null) 'error': updated!.lastError,
      'message': updated?.lastStatus == WatcherStatus.changed
          ? 'Change detected in "${existing.name}"!'
          : updated?.lastStatus == WatcherStatus.error
              ? 'Check failed: ${updated!.lastError}'
              : 'No change detected in "${existing.name}".',
    }));
  }
}
