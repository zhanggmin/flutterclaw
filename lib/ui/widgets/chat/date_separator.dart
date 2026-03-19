import 'package:flutter/material.dart';

/// A horizontal date separator shown between messages from different days.
class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({super.key, required this.timestamp});

  final DateTime timestamp;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _label(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}
