import 'package:flutter/material.dart';

class IdeaTagChip extends StatelessWidget {
  const IdeaTagChip({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(tag),
      avatar: const Icon(Icons.tag, size: 14),
      side: BorderSide.none,
    );
  }
}
