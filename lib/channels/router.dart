import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterclaw/channels/channel_interface.dart';
import 'package:flutterclaw/services/audio_transcription_service.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

/// Routes messages between channel adapters and the agent.
///
/// - Forwards incoming messages to the agent
/// - Sends outgoing messages to the correct channel adapter
/// - Provides per-channel session isolation via session keys
/// - Buffers outgoing messages when a channel is offline
/// - Transcribes incoming voice messages via Whisper API before forwarding
class ChannelRouter {
  ChannelRouter({
    this.agentHandler,
    this.maxQueueSize = 100,
    this.transcriptionServiceFactory,
  });

  final _log = Logger('ChannelRouter');
  final Map<String, ChannelAdapter> _adapters = {};
  final Map<String, Queue<OutgoingMessage>> _pendingQueues = {};
  final int maxQueueSize;

  /// Called for each incoming message. Set this to your agent's handler.
  MessageHandler? agentHandler;

  /// Factory that returns an [AudioTranscriptionService] for transcribing
  /// incoming voice messages. If null, voice messages are silently ignored.
  AudioTranscriptionService? Function()? transcriptionServiceFactory;

  bool _running = false;

  bool get isRunning => _running;

  /// All registered adapters (for status display).
  List<ChannelAdapter> get adapters => _adapters.values.toList();

  /// Register a channel adapter.
  void registerAdapter(ChannelAdapter adapter) {
    if (_adapters.containsKey(adapter.type)) {
      _log.warning('Replacing existing adapter for type ${adapter.type}');
    }
    _adapters[adapter.type] = adapter;
  }

  /// Unregister a channel adapter by type.
  void unregisterAdapter(String type) {
    _adapters.remove(type);
    _pendingQueues.remove(type);
  }

  /// Get session key for isolation (channel + chatId).
  String sessionKey(IncomingMessage msg) => msg.sessionKey;

  /// Start all registered adapters.
  Future<void> start() async {
    if (_running) {
      _log.warning('Router already running');
      return;
    }
    _running = true;
    for (final adapter in _adapters.values) {
      try {
        await adapter.start(_handleIncoming);
        _log.info('Started channel ${adapter.type}');
      } catch (e, st) {
        _log.severe('Failed to start channel ${adapter.type}', e, st);
      }
    }
  }

  /// Stop all adapters and flush pending queues.
  Future<void> stop() async {
    _running = false;
    for (final adapter in _adapters.values) {
      try {
        await adapter.stop();
        _log.info('Stopped channel ${adapter.type}');
      } catch (e, st) {
        _log.warning('Error stopping channel ${adapter.type}', e, st);
      }
    }
    _pendingQueues.clear();
  }

  /// Send a message to the appropriate channel. Queues if channel is offline.
  Future<void> sendMessage(OutgoingMessage message) async {
    final adapter = _adapters[message.channelType];
    if (adapter == null) {
      _log.warning('No adapter for channel ${message.channelType}, dropping message');
      return;
    }

    if (!adapter.isConnected) {
      _enqueue(message);
      return;
    }

    try {
      await adapter.sendMessage(message);
      await _flushPending(message.channelType);
    } catch (e, st) {
      _log.warning('Send failed for ${message.channelType}, queuing', e, st);
      _enqueue(message);
    }
  }

  void _enqueue(OutgoingMessage message) {
    final queue = _pendingQueues.putIfAbsent(
      message.channelType,
      () => Queue<OutgoingMessage>(),
    );
    if (queue.length >= maxQueueSize) {
      queue.removeFirst();
      _log.warning('Pending queue full for ${message.channelType}, dropped oldest');
    }
    queue.add(message);
  }

  Future<void> _flushPending(String channelType) async {
    final queue = _pendingQueues[channelType];
    if (queue == null || queue.isEmpty) return;

    final adapter = _adapters[channelType];
    if (adapter == null || !adapter.isConnected) return;

    while (queue.isNotEmpty) {
      final msg = queue.removeFirst();
      try {
        await adapter.sendMessage(msg);
      } catch (e, st) {
        _log.warning('Failed to flush pending message', e, st);
        queue.addFirst(msg);
        break;
      }
    }
  }

  Future<void> _handleIncoming(IncomingMessage message) async {
    final handler = agentHandler;
    if (handler == null) {
      _log.fine('No agent handler set, dropping incoming message');
      return;
    }

    var processed = message;

    // Transcribe voice messages before forwarding to the agent.
    if (message.audioBytes != null) {
      processed = await _transcribeVoice(message);
    }

    try {
      await handler(processed);
    } catch (e, st) {
      _log.severe('Agent handler error', e, st);
      // Best-effort: notify the user that something went wrong.
      try {
        await sendMessage(
          OutgoingMessage(
            channelType: processed.channelType,
            chatId: processed.chatId,
            text: 'Sorry, I encountered an error. Please try again.',
          ),
        );
      } catch (sendError) {
        _log.warning('Failed to send error notification', sendError);
      }
    }
  }

  /// Transcribe audio bytes to text via Whisper API and return updated message.
  ///
  /// On failure or missing transcription service, returns the original message
  /// with text set to a fallback notice so the agent still gets something.
  Future<IncomingMessage> _transcribeVoice(IncomingMessage message) async {
    final svc = transcriptionServiceFactory?.call();
    if (svc == null) {
      _log.warning(
        'Voice message received on ${message.channelType} but no transcription '
        'service configured — forwarding as placeholder',
      );
      return message.copyWith(
        text: '[Voice message received — transcription not configured]',
        clearAudio: true,
        channelContext: {
          ...?message.channelContext,
          'isVoiceMessage': true,
          'transcriptionFailed': true,
        },
      );
    }

    try {
      final dir = await getTemporaryDirectory();
      final ext = message.audioFormat ?? 'ogg';
      final tempPath =
          '${dir.path}/ch_voice_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await File(tempPath).writeAsBytes(message.audioBytes as Uint8List);
      final transcript = await svc.transcribe(tempPath);
      await File(tempPath).delete();

      if (transcript == null || transcript.isEmpty) {
        _log.warning('Transcription returned empty for ${message.channelType}');
        return message.copyWith(
          text: '[Voice message — transcription failed]',
          clearAudio: true,
          channelContext: {
            ...?message.channelContext,
            'isVoiceMessage': true,
            'transcriptionFailed': true,
          },
        );
      }

      _log.info('Transcribed voice (${message.channelType}): ${transcript.length} chars');
      return message.copyWith(
        text: transcript,
        clearAudio: true,
        channelContext: {
          ...?message.channelContext,
          'isVoiceMessage': true,
        },
      );
    } catch (e, st) {
      _log.severe('Voice transcription error', e, st);
      return message.copyWith(
        text: '[Voice message — transcription error]',
        clearAudio: true,
        channelContext: {
          ...?message.channelContext,
          'isVoiceMessage': true,
          'transcriptionFailed': true,
        },
      );
    }
  }
}
