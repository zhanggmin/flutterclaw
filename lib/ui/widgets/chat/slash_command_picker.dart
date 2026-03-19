import 'package:flutter/material.dart';
import 'slash_commands.dart';

/// Autocomplete picker shown above the input bar when user types '/'.
class SlashCommandPicker extends StatelessWidget {
  final List<SlashCommandDef> suggestions;
  final ValueChanged<String> onSelect;

  const SlashCommandPicker({
    super.key,
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: colors.outlineVariant, width: 0.5),
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final cmd = suggestions[index];
          return InkWell(
            onTap: () => onSelect(cmd.command),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      cmd.command,
                      style: TextStyle(
                        color: colors.onSecondaryContainer,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cmd.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.keyboard_return, size: 14, color: colors.outlineVariant),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
