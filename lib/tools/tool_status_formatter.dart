/// Shared utility for formatting tool status into human-readable overlay text.
library;

/// Formats a tool name + args into a friendly, human-readable label for the
/// overlay and notifications. UI automation tools get special treatment;
/// everything else falls back to a generic "name: first_arg" format.
String formatFriendlyToolStatus(String name, Map<String, dynamic>? args) {
  switch (name) {
    // ── UI automation tools ──────────────────────────────────────────────
    case 'ui_tap':
      return 'Tapping the screen...';
    case 'ui_swipe':
      return 'Swiping...';
    case 'ui_type_text':
      final text = args?['text'] as String? ?? '';
      final preview =
          text.length > 20 ? '${text.substring(0, 20)}...' : text;
      return 'Typing "$preview"';
    case 'ui_click_element':
      final query = args?['query'] as String? ?? '';
      return 'Tapping "$query"';
    case 'ui_find_elements':
      return 'Scanning the screen...';
    case 'ui_screenshot':
      return 'Looking at the screen...';
    case 'ui_global_action':
      final action = args?['action'] as String? ?? '';
      const labels = {
        'back': 'Going back...',
        'home': 'Going home...',
        'recents': 'Opening recents...',
        'notifications': 'Opening notifications...',
        'quick_settings': 'Opening quick settings...',
      };
      return labels[action] ?? 'Performing action...';
    case 'ui_launch_app':
      final app =
          args?['search'] as String? ?? args?['package'] as String? ?? '';
      return 'Opening $app...';
    case 'ui_launch_intent':
      return 'Opening link...';
    case 'ui_batch_actions':
      return 'Performing multiple actions...';
    case 'ui_ask_user':
      return 'Asking you a question...';
    case 'ui_list_apps':
      return 'Looking up apps...';
    case 'ui_app_intents':
      return 'Looking up app actions...';
    case 'ui_check_permission':
      return 'Checking permissions...';
    case 'ui_request_permission':
      return 'Requesting permissions...';
    case 'ui_status':
      // The tool itself already pushes to the overlay; return its text
      // so the onToolStatus callback doesn't overwrite with something generic.
      return args?['text'] as String? ?? '';

    // ── Fallback for non-UI tools ────────────────────────────────────────
    default:
      return _formatGenericLabel(name, args);
  }
}

String _formatGenericLabel(String name, Map<String, dynamic>? args) {
  if (args == null || args.isEmpty) return name;
  final raw = args['path'] ??
      args['query'] ??
      args['url'] ??
      args['key'] ??
      args.values.whereType<String>().firstOrNull;
  if (raw == null) return name;
  final label = raw.toString();
  final display = label.contains('/')
      ? label.split('/').where((s) => s.isNotEmpty).last
      : label;
  final truncated =
      display.length > 40 ? '${display.substring(0, 40)}...' : display;
  return '$name: $truncated';
}
