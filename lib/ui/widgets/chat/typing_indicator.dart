import 'package:flutter/material.dart';

/// Three animated dots indicating the assistant is typing/thinking.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.15;
            final value = (_controller.value - delay) % 1.0;
            final opacity = (value < 0.5 ? value * 2 : (1 - value) * 2).clamp(0.3, 1.0);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
