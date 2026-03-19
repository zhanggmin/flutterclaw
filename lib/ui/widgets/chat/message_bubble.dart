import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'copyable_code_block.dart';
import 'typing_indicator.dart';

/// A single chat message bubble (user, assistant, tool status, image, or document).
class MessageBubble extends ConsumerStatefulWidget {
  final ChatMessage message;
  final VoidCallback onCopy;

  const MessageBubble({super.key, required this.message, required this.onCopy});

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  bool _toolExpanded = false;

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-expand the card when streaming tool output starts arriving.
    if (!_toolExpanded &&
        widget.message.isToolStatus &&
        widget.message.toolResultText != null &&
        oldWidget.message.toolResultText == null) {
      setState(() => _toolExpanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isUser = widget.message.isUser;

    if (widget.message.isToolStatus) {
      return _buildToolPill(context, theme, colors);
    }

    if (isUser && widget.message.imageData != null) {
      return _buildImageBubble(context, theme);
    }

    if (widget.message.isDocumentMessage) {
      return _buildDocumentBubble(context, theme);
    }

    if (isUser && widget.message.text.startsWith('/')) {
      return _buildSlashCommandBubble(context, theme);
    }

    final agentEmoji = isUser
        ? null
        : (ref.watch(activeAgentProvider)?.emoji ?? '🤖');

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 6, bottom: 4),
              alignment: Alignment.center,
              child: Text(agentEmoji!, style: const TextStyle(fontSize: 18)),
            ),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: widget.onCopy,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: widget.message.isStreaming && widget.message.text.isEmpty
                    ? const TypingIndicator()
                    : isUser
                        ? SelectableText(
                            widget.message.text,
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontSize: 15,
                            ),
                          )
                        : MarkdownBody(
                            data: widget.message.text,
                            selectable: true,
                            onTapLink: (text, href, title) {
                              if (href != null) {
                                launchUrl(Uri.parse(href),
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            builders: {
                              'pre': CopyableCodeBlockBuilder(context),
                            },
                            sizedImageBuilder: (config) =>
                                _buildMarkdownImage(config, theme),
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                color: colors.onSurface,
                                fontSize: 15,
                                height: 1.4,
                              ),
                              h1: TextStyle(
                                color: colors.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              h2: TextStyle(
                                color: colors.onSurface,
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                              h3: TextStyle(
                                color: colors.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                              strong: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                              em: TextStyle(
                                color: colors.onSurface,
                                fontStyle: FontStyle.italic,
                              ),
                              code: TextStyle(
                                color: colors.primary,
                                backgroundColor:
                                    colors.primaryContainer.withValues(alpha: 0.3),
                                fontFamily: 'monospace',
                                fontSize: 13.5,
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              codeblockPadding: const EdgeInsets.all(12),
                              blockquoteDecoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: colors.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                              blockquotePadding:
                                  const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                              listBullet: TextStyle(
                                color: colors.onSurface,
                                fontSize: 15,
                              ),
                              a: TextStyle(
                                color: colors.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildToolPill(BuildContext context, ThemeData theme, ColorScheme colors) {
    final running = widget.message.isStreaming == true;
    final hasResult = widget.message.toolResultText != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: (!running && hasResult)
                ? () => setState(() => _toolExpanded = !_toolExpanded)
                : null,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build_circle, size: 14, color: colors.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.message.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (running)
                    SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: colors.primary,
                      ),
                    )
                  else ...[
                    Icon(Icons.check, size: 12, color: Colors.green.shade600),
                    if (hasResult) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _toolExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (_toolExpanded && hasResult)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
                maxHeight: 200,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.message.toolResultText!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSlashCommandBubble(BuildContext context, ThemeData theme) {
    final colors = theme.colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: widget.onCopy,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(
              color: colors.secondary.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.terminal, size: 14, color: colors.secondary),
              const SizedBox(width: 6),
              Flexible(
                child: SelectableText(
                  widget.message.text,
                  style: TextStyle(
                    color: colors.onSecondaryContainer,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownImage(MarkdownImageConfig config, ThemeData theme) {
    final uri = config.uri;
    const borderRadius = BorderRadius.all(Radius.circular(12));

    Widget imageWidget;

    if (uri.scheme == 'data') {
      final dataUri = UriData.fromUri(uri);
      imageWidget = Image.memory(
        dataUri.contentAsBytes(),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => const Padding(
          padding: EdgeInsets.all(16),
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    } else {
      imageWidget = Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        width: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (_, _, _) => const Padding(
          padding: EdgeInsets.all(16),
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: imageWidget,
      ),
    );
  }

  Widget _buildImageBubble(BuildContext context, ThemeData theme) {
    final imageBytes = base64Decode(widget.message.imageData!);
    final caption = widget.message.text.trim();
    const radius = BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(4),
    );

    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: widget.onCopy,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.memory(
                  imageBytes,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
                if (caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      caption,
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentBubble(BuildContext context, ThemeData theme) {
    final isUser = widget.message.isUser;
    final fileName = widget.message.documentFileName ?? 'Document';
    final mimeType = widget.message.documentMimeType ?? 'application/pdf';
    final isPdf = mimeType == 'application/pdf';
    final caption = widget.message.text.trim();
    final displayCaption = caption.isNotEmpty && caption != fileName ? caption : null;

    final base64Data = widget.message.documentData;
    final fileSizeLabel = base64Data != null
        ? _formatFileSize((base64Data.length * 3 / 4).round())
        : null;

    final ext = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'FILE';

    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: widget.onCopy,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: isUser
                      ? theme.colorScheme.onPrimary.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isPdf
                            ? const Color(0xFFE53935)
                            : theme.colorScheme.tertiary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isPdf ? Icons.picture_as_pdf : Icons.description,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            ext,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isUser
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              ?fileSizeLabel,
                              ext,
                            ].nonNulls.join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isUser
                                  ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                                  : theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (displayCaption != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  child: Text(
                    displayCaption,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isUser
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              if (displayCaption == null) const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
