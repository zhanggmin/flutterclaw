/// Full-screen overlay for Gemini Live real-time voice conversation.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'package:flutterclaw/core/agent/live_agent_loop.dart';
import 'package:flutterclaw/services/audio_player_service.dart';
import 'package:flutterclaw/ui/theme/tokens.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class LiveVoiceOverlay extends ConsumerStatefulWidget {
  const LiveVoiceOverlay({super.key});

  @override
  ConsumerState<LiveVoiceOverlay> createState() => _LiveVoiceOverlayState();
}

class _TranscriptEntry {
  final String role; // 'user' | 'model'
  final StringBuffer buffer = StringBuffer();
  bool finalized = false;

  _TranscriptEntry(this.role);

  String get text => buffer.toString();
}

class _LiveVoiceOverlayState extends ConsumerState<LiveVoiceOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _ring1Controller;
  late final AnimationController _ring2Controller;
  late final AnimationController _ring3Controller;

  StreamSubscription? _eventSub;

  bool _modelSpeaking = false;
  bool _isConnecting = true;
  String? _activeTool;

  // Transcript
  final List<_TranscriptEntry> _transcript = [];
  final ScrollController _scrollController = ScrollController();

  // --- Audio ---
  final List<int> _pcmBuffer = [];

  /// Gapless playlist — segments are appended while the player is running.
  /// Null means the player is idle and the next segment must create a new source.
  ConcatenatingAudioSource? _livePlaylist;

  /// Resets [_livePlaylist] when the player finishes naturally.
  StreamSubscription? _playerCompleteSub;

  /// Bytes queued into [_livePlaylist] since the last [needsNew] reset.
  /// play() is deferred until this exceeds [_kStartThreshold] to avoid
  /// buffer-underrun glitches at the beginning of each turn.
  int _prerollBytes = 0;
  bool _playerStarted = false;

  /// Flush to WAV every ~0.25 s: 24 kHz × 2 B × 0.25 s = 12 000 B.
  static const int _kFlushBytes = 12000;

  /// Minimum bytes buffered before starting the player (1 s of 24 kHz audio).
  static const int _kStartThreshold = 48000;
  final List<String> _tempFiles = [];

  @override
  void initState() {
    super.initState();

    _ring1Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _ring2Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _ring2Controller.repeat(reverse: true);
    });

    _ring3Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _ring3Controller.repeat(reverse: true);
    });

    _subscribeToEvents();
  }

  void _subscribeToEvents() {
    final notifier = ref.read(liveSessionProvider.notifier);
    _eventSub = notifier.agentEvents.listen((event) {
      if (!mounted) return;
      switch (event) {
        case LiveAudioOutput(:final pcmData):
          _pcmBuffer.addAll(pcmData);
          if (!_modelSpeaking) {
            setState(() {
              _modelSpeaking = true;
              _isConnecting = false;
            });
          }
          if (_pcmBuffer.length >= _kFlushBytes) _flushSegment();

        case LiveUserTranscript(:final text):
          setState(() {
            _isConnecting = false;
            final last = _transcript.isNotEmpty ? _transcript.last : null;
            if (last != null && last.role == 'user' && !last.finalized) {
              last.buffer.write(text);
            } else {
              _transcript.add(_TranscriptEntry('user')..buffer.write(text));
              if (_transcript.length > 20) _transcript.removeAt(0);
            }
          });
          _autoScroll();

        case LiveModelTranscript(:final text):
          setState(() {
            _isConnecting = false;
            final last = _transcript.isNotEmpty ? _transcript.last : null;
            if (last != null && last.role == 'model' && !last.finalized) {
              last.buffer.write(text);
            } else {
              _transcript.add(_TranscriptEntry('model')..buffer.write(text));
              if (_transcript.length > 20) _transcript.removeAt(0);
            }
          });
          _autoScroll();

        case LiveToolStarted(:final name):
          setState(() => _activeTool = name);

        case LiveToolCompleted(:final name):
          if (_activeTool == name) setState(() => _activeTool = null);

        case LiveTurnComplete():
          _flushSegment();
          setState(() {
            _modelSpeaking = false;
            for (final e in _transcript) {
              e.finalized = true;
            }
          });
          _autoScroll();

        case LiveInterrupted():
          _stopAndClearAudio();
          setState(() => _modelSpeaking = false);

        case LiveAgentError(:final message):
          setState(() {
            _transcript.add(
              _TranscriptEntry('model')
                ..buffer.write('⚠ $message')
                ..finalized = true,
            );
          });
          _autoScroll();

        case LiveSessionDisconnected():
          _stopAndClearAudio();

        case LiveSessionReady():
          setState(() => _isConnecting = false);
      }
    });
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Audio helpers ---

  void _flushSegment() {
    if (_pcmBuffer.isEmpty) return;
    final pcm = Uint8List.fromList(_pcmBuffer);
    _pcmBuffer.clear();
    _writeAndQueueWav(pcm);
  }

  /// Write [pcm] as a WAV segment and append it to the gapless playlist.
  ///
  /// The first segment initialises the [ConcatenatingAudioSource] and starts
  /// the player; subsequent segments are appended while playback is already
  /// running, so there is no gap between chunks.
  Future<void> _writeAndQueueWav(Uint8List pcm) async {
    final player = audioHandler?.player;
    if (player == null) return;

    // All synchronous decisions happen before any await to prevent races.
    final needsNew = _livePlaylist == null;
    if (needsNew) {
      _livePlaylist = ConcatenatingAudioSource(children: []);
      _prerollBytes = 0;
      _playerStarted = false;
    }
    final playlist = _livePlaylist!;

    try {
      final wav = _buildWav(pcm);
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/live_${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(wav);
      _tempFiles.add(path);

      await playlist.add(AudioSource.file(path));
      _prerollBytes += pcm.length;

      // Defer play() until we have at least _kStartThreshold bytes buffered so
      // the player never underruns at the start of a turn (avoids initial stutter).
      final shouldStart = !_playerStarted && _prerollBytes >= _kStartThreshold;
      if (shouldStart) _playerStarted = true; // guard against concurrent starts

      if (shouldStart) {
        await player.setAudioSource(playlist);
        await player.play();
        // Watch for natural completion so the next turn gets a fresh playlist.
        _playerCompleteSub?.cancel();
        _playerCompleteSub = player.processingStateStream
            .where((s) => s == ProcessingState.completed)
            .first
            .asStream()
            .listen((_) {
          _livePlaylist = null;
          if (mounted) {
            ref.read(liveSessionProvider.notifier).onPlaybackComplete();
          }
        });
      }
    } catch (e) {
      debugPrint('[LiveAudio] write error: $e');
      if (needsNew) _livePlaylist = null;
    }
  }

  void _stopAndClearAudio() {
    _playerCompleteSub?.cancel();
    _playerCompleteSub = null;
    _pcmBuffer.clear();
    _livePlaylist = null;
    _prerollBytes = 0;
    _playerStarted = false;
    for (final f in List.of(_tempFiles)) {
      File(f).delete().ignore();
    }
    _tempFiles.clear();
    audioHandler?.stop();
  }

  Future<void> _endSession() async {
    _stopAndClearAudio();
    ref.read(liveSessionProvider.notifier).stopSession();
  }

  @override
  void dispose() {
    _ring1Controller.dispose();
    _ring2Controller.dispose();
    _ring3Controller.dispose();
    _scrollController.dispose();
    _eventSub?.cancel();
    _playerCompleteSub?.cancel();
    for (final f in _tempFiles) {
      File(f).delete().ignore();
    }
    super.dispose();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agent = ref.watch(activeAgentProvider);

    return Positioned.fill(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 0,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(theme, agent),
              Expanded(child: _buildVisualization(theme, agent)),
              _buildTranscript(theme),
              _buildFooter(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, dynamic agent) {
    final agentName =
        (agent != null && (agent.name as String).isNotEmpty) ? agent.name as String : 'Live';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spacingMD,
        vertical: AppTokens.spacingSM,
      ),
      child: Row(
        children: [
          Text(
            agentName,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: AppTokens.spacingSM),
          _LiveBadge(theme: theme),
          const Spacer(),
          IconButton(
            onPressed: _endSession,
            iconSize: 20,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.call_end),
            tooltip: 'End conversation',
          ),
        ],
      ),
    );
  }

  Widget _buildVisualization(ThemeData theme, dynamic agent) {
    final agentEmoji =
        (agent != null && (agent.emoji as String).isNotEmpty) ? agent.emoji as String : '🎙';

    final Color ringColor;
    final double minScale;
    final double maxScale;
    final double minOpacity;
    final double maxOpacity;
    final Duration pulseDuration;

    if (_isConnecting) {
      ringColor = theme.colorScheme.outline;
      minScale = 0.95; maxScale = 1.05;
      minOpacity = 0.1; maxOpacity = 0.3;
      pulseDuration = const Duration(milliseconds: 1200);
    } else if (_modelSpeaking) {
      ringColor = theme.colorScheme.tertiary;
      minScale = 0.80; maxScale = 1.20;
      minOpacity = 0.3; maxOpacity = 0.7;
      pulseDuration = const Duration(milliseconds: 700);
    } else {
      ringColor = theme.colorScheme.primary;
      minScale = 0.95; maxScale = 1.05;
      minOpacity = 0.15; maxOpacity = 0.35;
      pulseDuration = const Duration(milliseconds: 1400);
    }

    if (_ring1Controller.duration != pulseDuration) {
      _ring1Controller.duration = pulseDuration;
      _ring2Controller.duration = pulseDuration;
      _ring3Controller.duration = pulseDuration;
    }

    final statusText = _isConnecting
        ? 'Connecting…'
        : _modelSpeaking
            ? 'Speaking…'
            : 'Listening…';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _AnimatedRing(
                  controller: _ring3Controller,
                  size: 140,
                  color: ringColor,
                  minScale: minScale, maxScale: maxScale,
                  minOpacity: minOpacity * 0.6, maxOpacity: maxOpacity * 0.6,
                ),
                _AnimatedRing(
                  controller: _ring2Controller,
                  size: 110,
                  color: ringColor,
                  minScale: minScale, maxScale: maxScale,
                  minOpacity: minOpacity * 0.8, maxOpacity: maxOpacity * 0.8,
                ),
                _AnimatedRing(
                  controller: _ring1Controller,
                  size: 80,
                  color: ringColor,
                  minScale: minScale, maxScale: maxScale,
                  minOpacity: minOpacity, maxOpacity: maxOpacity,
                ),
                // Center circle
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ringColor.withValues(alpha: 0.15),
                    border: Border.all(
                      color: ringColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(agentEmoji,
                        style: const TextStyle(fontSize: 26)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spacingMD),
          Text(
            statusText,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_activeTool != null) ...[
            const SizedBox(height: AppTokens.spacingSM),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spacingMD, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spacingXS),
                  Text(
                    _activeTool!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTranscript(ThemeData theme) {
    if (_transcript.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spacingMD, vertical: AppTokens.spacingSM),
        shrinkWrap: true,
        itemCount: _transcript.length,
        itemBuilder: (context, i) =>
            _TranscriptBubble(entry: _transcript[i], theme: theme),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spacingXL,
        AppTokens.spacingMD,
        AppTokens.spacingXL,
        AppTokens.spacingXL,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _endSession,
          icon: const Icon(Icons.call_end),
          label: const Text('End call'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            padding:
                const EdgeInsets.symmetric(vertical: AppTokens.spacingMD),
          ),
        ),
      ),
    );
  }

  static Uint8List _buildWav(Uint8List pcm,
      {int sampleRate = 24000, int channels = 1, int bitsPerSample = 16}) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcm.length;
    final header = ByteData(44);
    void s(int o, int v) => header.setUint8(o, v);
    void u16(int o, int v) => header.setUint16(o, v, Endian.little);
    void u32(int o, int v) => header.setUint32(o, v, Endian.little);
    s(0, 0x52); s(1, 0x49); s(2, 0x46); s(3, 0x46);
    u32(4, 36 + dataSize);
    s(8, 0x57); s(9, 0x41); s(10, 0x56); s(11, 0x45);
    s(12, 0x66); s(13, 0x6D); s(14, 0x74); s(15, 0x20);
    u32(16, 16); u16(20, 1); u16(22, channels);
    u32(24, sampleRate); u32(28, byteRate); u16(32, blockAlign);
    u16(34, bitsPerSample);
    s(36, 0x64); s(37, 0x61); s(38, 0x74); s(39, 0x61);
    u32(40, dataSize);
    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcm);
    return wav;
  }
}

// --- Subwidgets ---

class _LiveBadge extends StatelessWidget {
  final ThemeData theme;
  const _LiveBadge({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(
          color: Colors.deepPurple.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.spatial_audio, size: 10, color: Colors.deepPurple.shade300),
          const SizedBox(width: 3),
          Text(
            'LIVE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.deepPurple.shade300,
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedRing extends AnimatedWidget {
  final double size;
  final Color color;
  final double minScale;
  final double maxScale;
  final double minOpacity;
  final double maxOpacity;

  const _AnimatedRing({
    required AnimationController controller,
    required this.size,
    required this.color,
    required this.minScale,
    required this.maxScale,
    required this.minOpacity,
    required this.maxOpacity,
  }) : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as AnimationController).value;
    final scale = minScale + (maxScale - minScale) * t;
    final opacity = minOpacity + (maxOpacity - minOpacity) * t;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }
}

class _TranscriptBubble extends StatelessWidget {
  final _TranscriptEntry entry;
  final ThemeData theme;
  const _TranscriptBubble({required this.entry, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isUser = entry.role == 'user';
    final bubbleColor = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.secondaryContainer;
    final textColor = isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSecondaryContainer;

    const radius = Radius.circular(12);
    const smallRadius = Radius.circular(4);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spacingXS),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spacingSM, vertical: 6),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: isUser ? radius : smallRadius,
                  topRight: isUser ? smallRadius : radius,
                  bottomLeft: radius,
                  bottomRight: radius,
                ),
              ),
              child: Text(
                entry.text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
