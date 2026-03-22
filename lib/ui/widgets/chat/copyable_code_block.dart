import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutterclaw/l10n/l10n_extension.dart';
import 'package:markdown/markdown.dart' as md;

/// A [MarkdownElementBuilder] for `pre` (fenced code block) elements that
/// renders the code in a monospace block with a copy-to-clipboard button in
/// the top-right corner.
class CopyableCodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CopyableCodeBlockBuilder(this.context);

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final theme = Theme.of(context);
    final code = element.textContent;
    return Stack(
      alignment: Alignment.topRight,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 40, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13.5,
              color: theme.colorScheme.onSurface,
              height: 1.4,
            ),
          ),
        ),
        IconButton(
          iconSize: 16,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(),
          icon: Icon(Icons.copy, size: 16, color: theme.colorScheme.onSurfaceVariant),
          tooltip: context.l10n.copyTooltip,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.copiedToClipboard),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        ),
      ],
    );
  }
}
