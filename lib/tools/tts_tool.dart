/// TTS (Text-to-Speech) tool for FlutterClaw.
///
/// Wraps [TextToSpeechService] so the agent can invoke speech synthesis
/// programmatically. Supports direct playback or file synthesis.
library;

import 'package:flutterclaw/services/text_to_speech_service.dart';

import 'registry.dart';

class TtsTool extends Tool {
  final TextToSpeechService _tts;

  TtsTool(this._tts);

  @override
  String get name => 'tts';

  @override
  String get description =>
      'Convert text to speech. '
      'Use mode "speak" for immediate audio playback (hands-free), '
      'or mode "file" to synthesize to a WAV file and return its path. '
      'Optionally set language (BCP-47 tag, e.g. "es-ES", "ja-JP").';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': 'Text to synthesize.',
          },
          'mode': {
            'type': 'string',
            'enum': ['speak', 'file'],
            'description':
                '"speak" plays audio immediately on device (default). '
                '"file" saves to a WAV file and returns the path.',
          },
          'language': {
            'type': 'string',
            'description':
                'BCP-47 language tag for synthesis, e.g. "en-US", "es-ES", "ja-JP". '
                'Defaults to device locale.',
          },
        },
        'required': ['text'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final text = args['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      return ToolResult.error('text is required');
    }

    final mode = (args['mode'] as String?)?.toLowerCase() ?? 'speak';
    final language = args['language'] as String?;

    if (language != null && language.isNotEmpty) {
      await _tts.setLanguage(language);
    }

    if (mode == 'file') {
      final path = await _tts.synthesizeToFile(text);
      if (path == null) {
        return ToolResult.error(
          'TTS synthesis failed. The device TTS engine may not support file synthesis.',
        );
      }
      return ToolResult.success('Audio saved to: $path');
    }

    // Default: speak immediately
    await _tts.speak(text);
    return ToolResult.success('Speaking aloud: "${text.length > 80 ? '${text.substring(0, 80)}…' : text}"');
  }
}
