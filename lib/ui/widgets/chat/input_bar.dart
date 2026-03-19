import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/l10n/l10n_extension.dart';
import 'slash_commands.dart';
import 'slash_command_picker.dart';
import 'voice_mic_button.dart';

/// The chat input bar — text field, attach button, send/stop/mic, slash command autocomplete.
class ChatInputBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isProcessing;
  final VoidCallback onSend;
  final VoidCallback? onCancel;
  final VoidCallback? onAttach;
  final VoidCallback? onAttachDocument;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isProcessing,
    required this.onSend,
    this.onCancel,
    this.onAttach,
    this.onAttachDocument,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onAttach != null)
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(context.l10n.photoImage),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onAttach!();
                },
              ),
            if (widget.onAttachDocument != null)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(context.l10n.documentPdfTxt),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onAttachDocument!();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openSlashCommands() {
    widget.controller.text = '/';
    widget.controller.selection = const TextSelection.collapsed(offset: 1);
    widget.focusNode.requestFocus();
    setState(() {});
  }

  List<SlashCommandDef> get _suggestions {
    final text = widget.controller.text;
    if (!text.startsWith('/') || text.contains(' ')) return [];
    final query = text.toLowerCase();
    return kSlashCommands.where((c) => c.command.startsWith(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = _suggestions;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (suggestions.isNotEmpty)
          SlashCommandPicker(
            suggestions: suggestions,
            onSelect: (cmd) {
              widget.controller.text = cmd;
              widget.controller.selection = TextSelection.fromPosition(
                TextPosition(offset: cmd.length),
              );
              setState(() {});
              widget.focusNode.requestFocus();
            },
          ),
        Listener(
          onPointerMove: (event) {
            if (event.delta.dy > 2 && widget.focusNode.hasFocus) {
              widget.focusNode.unfocus();
            }
          },
          child: Container(
            padding: EdgeInsets.only(
              left: 4,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Slash commands button
                IconButton(
                  onPressed: widget.isProcessing ? null : _openSlashCommands,
                  icon: const Icon(Icons.terminal, size: 20),
                  tooltip: 'Commands',
                  visualDensity: VisualDensity.compact,
                ),
                if (widget.onAttach != null || widget.onAttachDocument != null)
                  IconButton(
                    onPressed: widget.isProcessing
                        ? null
                        : () => _showAttachMenu(context),
                    icon: const Icon(Icons.attach_file),
                    tooltip: context.l10n.attachImage,
                    visualDensity: VisualDensity.compact,
                  ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: widget.isProcessing ? null : (_) => widget.onSend(),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: context.l10n.messageFlutterClaw,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (widget.isProcessing)
                  IconButton.filled(
                    onPressed: widget.onCancel,
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    icon: const Icon(Icons.stop_rounded),
                  )
                else if (widget.controller.text.trim().isEmpty)
                  const VoiceMicButton()
                else
                  IconButton.filled(
                    onPressed: widget.onSend,
                    icon: const Icon(Icons.send),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
