/// Interactive reply payload model for agent tool results.
///
/// Port of OpenClaw's interactive/payload.ts.
/// Allows tools to return structured UI blocks (buttons, selects, text)
/// that the chat UI renders as touch-friendly widgets.
library;

enum InteractiveButtonStyle { primary, secondary, success, danger }

class InteractiveReplyButton {
  final String label;
  final String value;
  final InteractiveButtonStyle style;

  const InteractiveReplyButton({
    required this.label,
    required this.value,
    this.style = InteractiveButtonStyle.primary,
  });
}

class InteractiveReplyOption {
  final String label;
  final String value;

  const InteractiveReplyOption({required this.label, required this.value});
}

sealed class InteractiveReplyBlock {}

class InteractiveTextBlock extends InteractiveReplyBlock {
  final String text;
  InteractiveTextBlock(this.text);
}

class InteractiveButtonsBlock extends InteractiveReplyBlock {
  final List<InteractiveReplyButton> buttons;
  InteractiveButtonsBlock(this.buttons);
}

class InteractiveSelectBlock extends InteractiveReplyBlock {
  final List<InteractiveReplyOption> options;
  final String? placeholder;
  InteractiveSelectBlock(this.options, {this.placeholder});
}

class InteractiveReply {
  final List<InteractiveReplyBlock> blocks;
  const InteractiveReply(this.blocks);
}

// ---------------------------------------------------------------------------
// Parser (port of normalizeInteractiveReply from OpenClaw)
// ---------------------------------------------------------------------------

String? _readTrimmed(dynamic value) {
  if (value is! String) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}

InteractiveButtonStyle _parseButtonStyle(dynamic value) {
  switch (_readTrimmed(value)?.toLowerCase()) {
    case 'secondary':
      return InteractiveButtonStyle.secondary;
    case 'success':
      return InteractiveButtonStyle.success;
    case 'danger':
      return InteractiveButtonStyle.danger;
    default:
      return InteractiveButtonStyle.primary;
  }
}

InteractiveReplyButton? _parseButton(dynamic raw) {
  if (raw is! Map) return null;
  final label = _readTrimmed(raw['label']) ?? _readTrimmed(raw['text']);
  final value = _readTrimmed(raw['value']) ??
      _readTrimmed(raw['callbackData']) ??
      _readTrimmed(raw['callback_data']);
  if (label == null || value == null) return null;
  return InteractiveReplyButton(
    label: label,
    value: value,
    style: _parseButtonStyle(raw['style']),
  );
}

InteractiveReplyOption? _parseOption(dynamic raw) {
  if (raw is! Map) return null;
  final label = _readTrimmed(raw['label']) ?? _readTrimmed(raw['text']);
  final value = _readTrimmed(raw['value']);
  if (label == null || value == null) return null;
  return InteractiveReplyOption(label: label, value: value);
}

InteractiveReplyBlock? _parseBlock(dynamic raw) {
  if (raw is! Map) return null;
  final type = _readTrimmed(raw['type'])?.toLowerCase();
  switch (type) {
    case 'text':
      final text = _readTrimmed(raw['text']);
      return text != null ? InteractiveTextBlock(text) : null;
    case 'buttons':
      final buttons = (raw['buttons'] as List<dynamic>? ?? [])
          .map(_parseButton)
          .whereType<InteractiveReplyButton>()
          .toList();
      return buttons.isNotEmpty ? InteractiveButtonsBlock(buttons) : null;
    case 'select':
      final options = (raw['options'] as List<dynamic>? ?? [])
          .map(_parseOption)
          .whereType<InteractiveReplyOption>()
          .toList();
      return options.isNotEmpty
          ? InteractiveSelectBlock(options,
              placeholder: _readTrimmed(raw['placeholder']))
          : null;
    default:
      return null;
  }
}

/// Parse raw JSON into an [InteractiveReply], or return null if invalid.
InteractiveReply? parseInteractiveReply(dynamic raw) {
  if (raw is! Map) return null;
  final blocks = (raw['blocks'] as List<dynamic>? ?? [])
      .map(_parseBlock)
      .whereType<InteractiveReplyBlock>()
      .toList();
  return blocks.isNotEmpty ? InteractiveReply(blocks) : null;
}
