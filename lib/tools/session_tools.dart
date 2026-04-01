/// Session tools for FlutterClaw.
///
/// Provides session status and listing. Actual session data is provided
/// via callbacks for integration with the session store.
library;

import 'registry.dart';

/// Callback to get current session info. Returns null if no session.
typedef SessionInfoCallback = Future<Map<String, dynamic>?> Function(
  String? sessionKey,
);

/// Callback to list active sessions.
typedef SessionsListCallback = Future<List<Map<String, dynamic>>> Function({
  int? limit,
});

/// Returns current session info (model, tokens used, etc.).
class SessionStatusTool extends Tool {
  final SessionInfoCallback getSessionInfo;

  SessionStatusTool(this.getSessionInfo);

  @override
  String get name => 'session_status';

  @override
  String get description =>
      'Return the current session info (model, tokens used, etc.).';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'session_key': {
            'type': 'string',
            'description': 'Optional session key. If omitted, uses current session.',
          },
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final sessionKey = args['session_key'] as String? ??
        args['__session_key'] as String?;
    try {
      final info = await getSessionInfo(sessionKey);
      if (info == null) {
        return ToolResult.success('No active session.');
      }
      final lines = info.entries.map((e) => '${e.key}: ${e.value}').toList();
      return ToolResult.success(lines.join('\n'));
    } catch (e) {
      return ToolResult.error('Session status failed: $e');
    }
  }
}

/// Lists active sessions.
class SessionsListTool extends Tool {
  final SessionsListCallback listSessions;

  SessionsListTool(this.listSessions);

  @override
  String get name => 'sessions_list';

  @override
  String get description => 'List active sessions.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of sessions to return (default 10).',
          },
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final limit = args['limit'] as int? ?? 10;
    try {
      final sessions = await listSessions(limit: limit);
      if (sessions.isEmpty) {
        return ToolResult.success('No active sessions.');
      }
      final lines = sessions.asMap().entries.map((e) {
        final i = e.key + 1;
        final s = e.value;
        final key = s['session_key'] ?? s['key'] ?? s['id'] ?? '';
        final model = s['model'] ?? s['model_name'] ?? '';
        final tokens = s['tokens_used'] ?? s['tokens'] ?? '';
        return '$i. $key | model: $model | tokens: $tokens';
      });
      return ToolResult.success(lines.join('\n'));
    } catch (e) {
      return ToolResult.error('Sessions list failed: $e');
    }
  }
}
