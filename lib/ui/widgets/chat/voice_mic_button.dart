import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'package:flutterclaw/l10n/l10n_extension.dart';

/// Microphone button in the chat input bar. Tap to start/stop recording; auto-transcribes on stop.
class VoiceMicButton extends ConsumerStatefulWidget {
  const VoiceMicButton({super.key});

  @override
  ConsumerState<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends ConsumerState<VoiceMicButton> {
  bool _transcribing = false;

  Future<void> _toggle() async {
    final svc = ref.read(voiceRecordingServiceProvider);

    if (svc.isRecording) {
      final path = await svc.stop();
      if (path == null || !mounted) return;
      setState(() => _transcribing = true);
      HapticFeedback.lightImpact();
      final ok = await ref.read(chatProvider.notifier).transcribeAndSend(path);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.couldNotTranscribeAudio),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      if (mounted) setState(() => _transcribing = false);
    } else {
      final started = await svc.start();
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.microphonePermissionDenied),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(voiceRecordingServiceProvider);
    final recording = svc.isRecording;
    final theme = Theme.of(context);

    if (_transcribing) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return IconButton.filled(
      onPressed: _toggle,
      style: recording
          ? IconButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            )
          : null,
      icon: Icon(recording ? Icons.stop_rounded : Icons.mic),
      tooltip: recording ? context.l10n.stopRecording : context.l10n.voiceInput,
    );
  }
}
