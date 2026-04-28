import 'package:flutter/material.dart';

class IdeaEmptyState extends StatelessWidget {
  const IdeaEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.lightbulb_outline,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
