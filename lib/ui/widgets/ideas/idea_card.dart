import 'package:flutter/material.dart';
import 'package:flutterclaw/ui/widgets/ideas/idea_tag_chip.dart';

class IdeaCard extends StatelessWidget {
  const IdeaCard({
    super.key,
    required this.title,
    required this.body,
    required this.statusLabel,
    required this.statusColor,
    required this.tags,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
  });

  final String title;
  final String body;
  final String statusLabel;
  final Color statusColor;
  final List<String> tags;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: onPrimaryAction,
                  child: Text(primaryActionLabel),
                ),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tags.map((tag) => IdeaTagChip(tag: tag)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
