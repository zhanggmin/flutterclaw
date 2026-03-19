import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'package:flutterclaw/l10n/l10n_extension.dart';
import 'package:flutterclaw/services/analytics_service.dart';
import 'package:flutterclaw/ui/widgets/agent_switcher_chip.dart';
import 'package:flutterclaw/ui/widgets/chat/message_bubble.dart';
import 'package:flutterclaw/ui/widgets/chat/date_separator.dart';
import 'package:flutterclaw/ui/widgets/chat/input_bar.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _hatchChecked = false;
  bool _isNearBottom = true;
  bool _programmaticScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
      // Auto-scroll when messages change (instead of inside build).
      // Also fire a light haptic when a tool pill transitions to done.
      ref.listenManual(chatProvider, (prev, next) {
        _scrollToBottom();
        if (prev != null) {
          final prevRunning = prev.where((m) => m.isToolStatus && m.isStreaming == true).length;
          final nextRunning = next.where((m) => m.isToolStatus && m.isStreaming == true).length;
          if (nextRunning < prevRunning) HapticFeedback.selectionClick();
        }
      });
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _programmaticScroll) return;
    final pos = _scrollController.position;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (nearBottom != _isNearBottom) {
      setState(() => _isNearBottom = nearBottom);
    }
  }

  void _onFocusChange() {
    // When keyboard opens, scroll to bottom after it animates in
    if (_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _scrollToBottom(force: true);
      });
    }
  }

  Future<void> _init() async {
    // Get user's locale to pass to the agent (before any async operations)
    final locale = Localizations.maybeLocaleOf(context);
    final languageCode = locale?.languageCode;

    // Load previous messages from persisted session
    await ref.read(chatProvider.notifier).loadHistory();

    // Then check if we need to trigger the bootstrap hatch
    if (_hatchChecked) return;
    _hatchChecked = true;

    ref.read(chatProvider.notifier).triggerHatch(userLanguage: languageCode);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(chatProvider.notifier);
    if (state == AppLifecycleState.paused) {
      notifier.onAppBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      notifier.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickAndSendImage() async {
    final defaultCaption = context.l10n.whatDoYouSeeInImage;
    final errorSimulator = context.l10n.imagePickerNotAvailable;
    final errorGeneric = context.l10n.couldNotOpenImagePicker;

    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(context.l10n.photoLibrary),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(context.l10n.camera),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;

      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image == null) return;

      final bytes = await File(image.path).readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType =
          image.path.endsWith('.png') ? 'image/png' : 'image/jpeg';

      final caption = _controller.text.trim();
      _controller.clear();

      await ref.read(chatProvider.notifier).sendImageMessage(
            base64Image: base64Image,
            mimeType: mimeType,
            caption: caption.isNotEmpty
                ? caption
                : defaultCaption,
            fileName: image.name,
          );
    } catch (e) {
      if (!mounted) return;
      final isSimulator = e.toString().contains('channel-error') ||
          e.toString().contains('Unable to establish connection');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isSimulator
              ? errorSimulator
              : errorGeneric),
        ),
      );
    }
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_isNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _programmaticScroll = true;
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
        _programmaticScroll = false;
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    _controller.clear();
    _isNearBottom = true;
    _focusNode.requestFocus();

    await ref.read(analyticsServiceProvider).logAction(
      name: 'send_message',
      parameters: {
        'length': text.length,
      },
    );

    await ref.read(chatProvider.notifier).sendMessage(text);
  }

  Future<void> _sendDocumentMessage(String base64Data, String mimeType, String fileName) async {
    await ref.read(chatProvider.notifier).sendDocumentMessage(
      base64Data: base64Data,
      mimeType: mimeType,
      fileName: fileName,
    );
  }

  Future<void> _pickAndSendDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;

      final base64Data = base64Encode(file.bytes!);
      final ext = (file.extension ?? 'pdf').toLowerCase();
      final mimeType = ext == 'pdf' ? 'application/pdf' : 'text/plain';
      final fileName = file.name;

      await _sendDocumentMessage(base64Data, mimeType, fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotOpenDocument(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final isProcessing = ref.read(chatProvider.notifier).isProcessing;
    final modelSupportsVision = ref.watch(activeModelSupportsVisionProvider);
    final activeAgent = ref.watch(activeAgentProvider);

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.appTitle),
          actions: [
            const SessionSwitcherChip(),
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: context.l10n.newSession,
              onPressed: () => ref.read(chatProvider.notifier).clear(),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  messages.isEmpty
                      ? _ChatEmptyState(agent: activeAgent)
                      : ListView.builder(
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final prev = index > 0 ? messages[index - 1] : null;
                            final showSeparator =
                                _shouldShowDateSeparator(prev, msg);
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showSeparator)
                                  ChatDateSeparator(timestamp: msg.timestamp),
                                MessageBubble(
                                  message: msg,
                                  onCopy: () {
                                    Clipboard.setData(
                                        ClipboardData(text: msg.text));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text(context.l10n.copiedToClipboard),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                  // Scroll-to-bottom FAB
                  if (!_isNearBottom && messages.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'scroll_to_bottom',
                        onPressed: () => _scrollToBottom(force: true),
                        child: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                ],
              ),
            ),
            ChatInputBar(
              controller: _controller,
              focusNode: _focusNode,
              isProcessing: isProcessing,
              onSend: _sendMessage,
              onCancel: () =>
                  ref.read(chatProvider.notifier).cancelProcessing(),
              onAttach: modelSupportsVision ? _pickAndSendImage : null,
              onAttachDocument: _pickAndSendDocument,
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowDateSeparator(ChatMessage? prev, ChatMessage current) {
    if (prev == null) return true;
    final p = prev.timestamp;
    final c = current.timestamp;
    return p.year != c.year || p.month != c.month || p.day != c.day;
  }
}

// ---------------------------------------------------------------------------
// Personalized empty state — shows active agent emoji and name
// ---------------------------------------------------------------------------

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({this.agent});
  final dynamic agent; // AgentProfile?

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = agent?.emoji as String? ?? '🤖';
    final name = agent?.name as String? ?? context.l10n.appTitle;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 12),
            Text(
              name,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.yourPersonalAssistant,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(label: 'What can you do?'),
                _SuggestionChip(label: '/help'),
                _SuggestionChip(label: '/status'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends ConsumerWidget {
  const _SuggestionChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ActionChip(
      label: Text(label),
      onPressed: () => ref.read(chatProvider.notifier).sendMessage(label),
    );
  }
}

