/// Non-blocking overlay for Gemini Live voice: animated rings and status over the
/// existing chat list. Transcript text streams into [chatProvider] via live agent
/// events; tool pills still arrive from [SessionManager.messageStream]. Session
/// persistence runs on [LiveTurnComplete] (and before tool rows when applicable).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'package:flutterclaw/core/agent/live_agent_loop.dart';
import 'package:flutterclaw/generated/app_localizations.dart';
import 'package:flutterclaw/ui/theme/tokens.dart';
import 'package:just_audio/just_audio.dart';

/// Live call chrome heights — keep in sync with [LiveVoiceOverlay.listTopPaddingWhenLive].
const double _kLiveHeaderHeight = 52;
const double _kLiveHudHeight = 80;

class LiveVoiceOverlay extends ConsumerStatefulWidget {
  const LiveVoiceOverlay({super.key});

  /// Extra top padding for the chat [ListView] so messages sit below the live header + HUD.
  static const double listTopPaddingWhenLive =
      _kLiveHeaderHeight + _kLiveHudHeight;

  @override
  ConsumerState<LiveVoiceOverlay> createState() => _LiveVoiceOverlayState();
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

  // --- Audio (stream-based, no disk I/O) ---

  /// PCM stream source for the current assistant turn. Null when idle.
  _LivePcmStreamSource? _pcmSource;

  /// Total PCM bytes fed to [_pcmSource] this turn (for preroll gate).
  int _pcmFed = 0;

  bool _playerStarted = false;

  /// Serializes [_startStreamPlayback] so [setAudioSource] is never called twice.
  Future<void> _startupFuture = Future.value();

  /// Incremented in [_stopAndClearAudio] so in-flight async steps exit cleanly.
  int _liveAudioGeneration = 0;

  /// True after [play] until local output is fully done (see [_armPlaybackEndListener]).
  bool _awaitingLocalPlaybackEnd = false;
  Timer? _playbackEndDebounce;

  /// Mic is cut for the current assistant audio stream (first [LiveAudioOutput] → playback end).
  bool _micHoldForAssistantPcm = false;

  /// Playback must have reached [PlayerState.playing] before we trust idle/completed as "done"
  /// (iOS often reports idle/!playing briefly right after [play]).
  bool _sawPlayerAudibleThisArm = false;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription? _playerCompleteSub;

  /// Preroll: 1 s of PCM before [play] to avoid immediate underrun.
  static const int _kPrerollBytes = 48000; // 24 kHz × 2 B × 1 s

  /// Dedicated player: avoids audio_service main [AudioPlayer] contention.
  late final AudioPlayer _livePlayer;

  @override
  void initState() {
    super.initState();

    // Do not let just_audio reconfigure the session: [LiveSessionNotifier]
    // already sets playAndRecord + voiceChat for AEC; a second activation
    // fight breaks echo cancellation and can leak speaker audio to the mic path.
    _livePlayer = AudioPlayer(
      handleAudioSessionActivation: false,
      audioLoadConfiguration: AudioLoadConfiguration(
        darwinLoadControl: DarwinLoadControl(
          automaticallyWaitsToMinimizeStalling: false,
          preferredForwardBufferDuration: Duration(seconds: 2),
        ),
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: Duration(milliseconds: 2000),
          maxBufferDuration: Duration(seconds: 10),
          bufferForPlaybackDuration: Duration(milliseconds: 250),
          bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 500),
        ),
      ),
    );

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
    _eventSub = notifier.agentEvents.listen(
      (event) {
        if (!mounted) return;
        switch (event) {
          case LiveAudioOutput(:final pcmData):
            // Cut mic as soon as assistant PCM arrives — during preroll the speaker
            // is still silent locally but the server is already in "model speaking";
            // sending mic here triggers spurious LiveInterrupted / cut-off.
            if (!_micHoldForAssistantPcm && mounted) {
              _micHoldForAssistantPcm = true;
              ref.read(liveSessionProvider.notifier).setLivePlaybackSuppressMic(true);
            }
            if (!_modelSpeaking) {
              setState(() {
                _modelSpeaking = true;
                _isConnecting = false;
              });
            }
            _feedPcm(pcmData);

          case LiveUserTranscript():
            setState(() => _isConnecting = false);

          case LiveModelTranscript():
            setState(() => _isConnecting = false);

          case LiveToolStarted(:final name):
            setState(() => _activeTool = name);

          case LiveToolCompleted(:final name):
            if (_activeTool == name) setState(() => _activeTool = null);

          case LiveTurnComplete():
            if (_pcmSource == null && !_playerStarted) {
              // No audio this turn (or already cleared by LiveInterrupted).
              if (_micHoldForAssistantPcm) {
                _micHoldForAssistantPcm = false;
                ref.read(liveSessionProvider.notifier).setLivePlaybackSuppressMic(false);
              }
              if (_modelSpeaking) setState(() => _modelSpeaking = false);
              return;
            }
            // Close the stream → player plays remaining buffered data → completed.
            _pcmSource?.close();
            // Short response below preroll threshold: start playback now.
            if (!_playerStarted && _pcmFed > 0) {
              _playerStarted = true;
              final gen = _liveAudioGeneration;
              _startupFuture = _startupFuture.then((_) => _startStreamPlayback(gen));
            }
            setState(() => _modelSpeaking = false);

          case LiveInterrupted():
            _stopAndClearAudio();
            setState(() => _modelSpeaking = false);

          case LiveAgentError(:final message):
            final messenger = ScaffoldMessenger.maybeOf(context);
            messenger?.showSnackBar(SnackBar(content: Text(message)));

          case LiveSessionDisconnected():
            _stopAndClearAudio();

          case LiveSessionReady():
            setState(() => _isConnecting = false);
        }
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('[LiveAudio] agent event stream error: $error');
        if (mounted) _stopAndClearAudio();
      },
    );
  }

  // --- Audio helpers ---

  /// Feed raw PCM into the stream source; start playback once preroll is met.
  void _feedPcm(Uint8List pcm) {
    _pcmSource ??= _LivePcmStreamSource();
    _pcmSource!.feed(pcm);
    _pcmFed += pcm.length;

    if (!_playerStarted && _pcmFed >= _kPrerollBytes) {
      _playerStarted = true;
      final gen = _liveAudioGeneration;
      _startupFuture = _startupFuture.then((_) => _startStreamPlayback(gen));
    }
  }

  Future<void> _startStreamPlayback(int gen) async {
    if (gen != _liveAudioGeneration) return;
    final src = _pcmSource;
    if (src == null) return;
    try {
      await _livePlayer.setAudioSource(src);
      if (gen != _liveAudioGeneration) return;
      await _livePlayer.play();
      if (mounted) {
        ref.read(liveSessionProvider.notifier).setLivePlaybackSuppressMic(true);
      }
      _armPlaybackEndListener(gen);
    } catch (e) {
      debugPrint('[LiveAudio] stream start error: $e');
      _playerStarted = false;
      if (mounted) {
        ref.read(liveSessionProvider.notifier).setLivePlaybackSuppressMic(false);
      }
    }
  }

  /// Unsuppress mic after playback ends. Uses [completed] or [idle+!playing]
  /// — guarded by [_sawPlayerAudibleThisArm] to ignore iOS false idles right
  /// after [setAudioSource].
  void _armPlaybackEndListener(int gen) {
    _playerCompleteSub?.cancel();
    _playerStateSub?.cancel();
    _playbackEndDebounce?.cancel();
    _awaitingLocalPlaybackEnd = true;
    _sawPlayerAudibleThisArm = false;
    _playerStateSub = _livePlayer.playerStateStream.listen((ps) {
      if (!mounted || gen != _liveAudioGeneration) return;
      if (ps.playing) _sawPlayerAudibleThisArm = true;
    });
    _playerCompleteSub = _livePlayer.processingStateStream.listen((state) {
      if (!mounted || gen != _liveAudioGeneration || !_awaitingLocalPlaybackEnd) {
        return;
      }
      if (!_sawPlayerAudibleThisArm) return;
      final likelyDone = state == ProcessingState.completed ||
          (state == ProcessingState.idle && !_livePlayer.playing);
      if (!likelyDone) return;
      _playbackEndDebounce?.cancel();
      _playbackEndDebounce = Timer(const Duration(milliseconds: 180), () {
        _playbackEndDebounce = null;
        if (!mounted || gen != _liveAudioGeneration || !_awaitingLocalPlaybackEnd) {
          return;
        }
        _awaitingLocalPlaybackEnd = false;
        _playerStarted = false;
        _micHoldForAssistantPcm = false;
        _pcmSource = null;
        _pcmFed = 0;
        _playerStateSub?.cancel();
        _playerStateSub = null;
        ref
            .read(liveSessionProvider.notifier)
            .scheduleMicUnsuppressAfterLocalPlayback();
      });
    });
  }

  void _stopAndClearAudio() {
    _liveAudioGeneration++;
    _startupFuture = Future.value();
    _playbackEndDebounce?.cancel();
    _playbackEndDebounce = null;
    _awaitingLocalPlaybackEnd = false;
    _micHoldForAssistantPcm = false;
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _playerCompleteSub?.cancel();
    _playerCompleteSub = null;
    _pcmSource?.close();
    _pcmSource = null;
    _pcmFed = 0;
    _playerStarted = false;
    unawaited(_livePlayer.stop().catchError((_) {}));
    if (mounted) {
      ref.read(liveSessionProvider.notifier).setLivePlaybackSuppressMic(false);
    }
  }

  Future<void> _endSession() async {
    _stopAndClearAudio();
    await ref.read(liveSessionProvider.notifier).stopSession();
    if (mounted) {
      await ref.read(chatProvider.notifier).reloadHistory();
    }
  }

  @override
  void dispose() {
    _liveAudioGeneration++;
    _startupFuture = Future.value();
    _ring1Controller.dispose();
    _ring2Controller.dispose();
    _ring3Controller.dispose();
    _eventSub?.cancel();
    _playbackEndDebounce?.cancel();
    _playerStateSub?.cancel();
    _playerCompleteSub?.cancel();
    _pcmSource?.close();
    unawaited(_livePlayer.dispose().catchError((_) {}));
    super.dispose();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agent = ref.watch(activeAgentProvider);
    final topBarColor = theme.colorScheme.surface.withValues(alpha: 0.97);

    // Only top chrome: chat list scrolls in the clear area below (with matching padding).
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: topBarColor,
        elevation: 2,
        shadowColor: Colors.black26,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _kLiveHeaderHeight,
              child: _buildHeader(theme, agent),
            ),
            SizedBox(
              height: _kLiveHudHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spacingMD,
                  0,
                  AppTokens.spacingMD,
                  AppTokens.spacingSM,
                ),
                child: _buildCompactHud(theme, agent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, dynamic agent) {
    final agentName =
        (agent != null && (agent.name as String).isNotEmpty) ? agent.name as String : 'Live';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spacingMD),
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

  /// Compact row: small rings + status; fits in [_hudHeight] so it never overlaps bubbles.
  Widget _buildCompactHud(ThemeData theme, dynamic agent) {
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
      minScale = 0.95;
      maxScale = 1.05;
      minOpacity = 0.12;
      maxOpacity = 0.32;
      pulseDuration = const Duration(milliseconds: 1200);
    } else if (_modelSpeaking) {
      ringColor = theme.colorScheme.tertiary;
      minScale = 0.88;
      maxScale = 1.12;
      minOpacity = 0.28;
      maxOpacity = 0.65;
      pulseDuration = const Duration(milliseconds: 700);
    } else {
      ringColor = theme.colorScheme.primary;
      minScale = 0.95;
      maxScale = 1.05;
      minOpacity = 0.18;
      maxOpacity = 0.38;
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              _AnimatedRing(
                controller: _ring3Controller,
                size: 56,
                color: ringColor,
                minScale: minScale,
                maxScale: maxScale,
                minOpacity: minOpacity * 0.6,
                maxOpacity: maxOpacity * 0.6,
              ),
              _AnimatedRing(
                controller: _ring2Controller,
                size: 44,
                color: ringColor,
                minScale: minScale,
                maxScale: maxScale,
                minOpacity: minOpacity * 0.85,
                maxOpacity: maxOpacity * 0.85,
              ),
              _AnimatedRing(
                controller: _ring1Controller,
                size: 32,
                color: ringColor,
                minScale: minScale,
                maxScale: maxScale,
                minOpacity: minOpacity,
                maxOpacity: maxOpacity,
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ringColor.withValues(alpha: 0.18),
                  border: Border.all(
                    color: ringColor.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    agentEmoji,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppTokens.spacingSM),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_modelSpeaking && !_isConnecting) ...[
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context)!.liveVoiceBargeInHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    height: 1.15,
                  ),
                ),
              ],
              if (_activeTool != null) ...[
                const SizedBox(height: 4),
                Text(
                  _activeTool!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Streaming audio source
// ---------------------------------------------------------------------------

/// Delivers PCM audio as a single continuous WAV byte stream to just_audio,
/// eliminating all file I/O and [ConcatenatingAudioSource] segment transitions.
///
/// One instance is created per assistant turn. [feed] is called for every
/// [LiveAudioOutput] chunk; [close] is called on [LiveTurnComplete] or barge-in.
///
/// Range requests (e.g. AVFoundation header sniff) are served from [_buf],
/// which accumulates the complete turn for the lifetime of the source.
class _LivePcmStreamSource extends StreamAudioSource {
  /// Cumulative bytes: WAV header + all PCM fed so far.
  final _buf = <int>[];

  /// Broadcast stream for live delivery of future PCM chunks.
  final _liveStream = StreamController<Uint8List>.broadcast();

  bool _closed = false;

  _LivePcmStreamSource() {
    // WAV header is always the first bytes served.
    _buf.addAll(_streamingWavHeader());
  }

  /// Feed raw 16-bit LE 24 kHz mono PCM samples from Gemini.
  void feed(Uint8List pcm) {
    if (_closed) return;
    _buf.addAll(pcm);
    _liveStream.add(pcm);
  }

  /// Signal end of turn — closes the stream so the player can finish naturally.
  void close() {
    if (_closed) return;
    _closed = true;
    _liveStream.close();
  }

  /// Total bytes buffered (WAV header + PCM). Used for preroll gating.
  int get bytesFed => _buf.length;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;

    // Subscribe to future bytes BEFORE taking the snapshot so that any PCM
    // arriving between snapshot and subscription is not lost.
    // This is safe because Dart's event loop is single-threaded: no interleaving
    // can occur between these two synchronous operations.
    final ctrl = StreamController<Uint8List>();
    StreamSubscription<Uint8List>? liveSub;

    if (!_closed) {
      liveSub = _liveStream.stream.listen(
        ctrl.add,
        onDone: () { if (!ctrl.isClosed) ctrl.close(); },
        onError: ctrl.addError,
      );
      ctrl.onCancel = () => liveSub?.cancel();
    }

    // Replay everything already buffered from `from` onward.
    if (from < _buf.length) {
      ctrl.add(Uint8List.fromList(_buf.sublist(from)));
    }

    if (_closed) ctrl.close();

    return StreamAudioResponse(
      sourceLength: null,
      contentLength: null,
      offset: from,
      stream: ctrl.stream,
      contentType: 'audio/wav',
    );
  }

  /// 44-byte WAV header with 0xFFFFFFFF (unknown) sizes — standard for streaming WAV.
  static Uint8List _streamingWavHeader({
    int sr = 24000, int ch = 1, int bps = 16,
  }) {
    final b = ByteData(44);
    void s(int o, int v) => b.setUint8(o, v);
    void u16(int o, int v) => b.setUint16(o, v, Endian.little);
    void u32(int o, int v) => b.setUint32(o, v, Endian.little);
    s(0, 0x52); s(1, 0x49); s(2, 0x46); s(3, 0x46); // RIFF
    u32(4, 0xFFFFFFFF);                               // file size: unknown
    s(8, 0x57); s(9, 0x41); s(10, 0x56); s(11, 0x45); // WAVE
    s(12, 0x66); s(13, 0x6D); s(14, 0x74); s(15, 0x20); // fmt
    u32(16, 16); u16(20, 1); u16(22, ch);
    u32(24, sr); u32(28, sr * ch * (bps ~/ 8));
    u16(32, ch * (bps ~/ 8)); u16(34, bps);
    s(36, 0x64); s(37, 0x61); s(38, 0x74); s(39, 0x61); // data
    u32(40, 0xFFFFFFFF);                              // data size: unknown
    return b.buffer.asUint8List();
  }
}

// ---------------------------------------------------------------------------
// Subwidgets
// ---------------------------------------------------------------------------

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
