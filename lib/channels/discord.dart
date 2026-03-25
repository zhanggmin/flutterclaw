import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutterclaw/channels/channel_interface.dart';
import 'package:flutterclaw/services/pairing_service.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _gatewayUrl = 'wss://gateway.discord.gg/?v=10&encoding=json';
const _apiBase = 'https://discord.com/api/v10';
const _type = 'discord';

// Gateway opcodes
const _opDispatch = 0;
const _opHeartbeat = 1;
const _opIdentify = 2;
const _opHeartbeatAck = 11;
const _opHello = 10;
const _opResume = 6;
const _opReconnect = 7;
const _opInvalidSession = 9;

/// Discord Gateway + REST adapter.
class DiscordChannelAdapter implements ChannelAdapter {
  DiscordChannelAdapter({
    required this.token,
    this.allowedUserIds = const [],
    this.dmPolicy = 'pairing',
    this.pairingService,
    this.chatCommandHandler,
  }) : _dio = Dio(BaseOptions(
          baseUrl: _apiBase,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Authorization': 'Bot $token',
            'Content-Type': 'application/json',
          },
        ));

  final String token;
  final List<String> allowedUserIds;
  final String dmPolicy;
  final PairingService? pairingService;
  final Future<String?> Function(String sessionKey, String command)? chatCommandHandler;
  final Dio _dio;
  final _log = Logger('DiscordChannelAdapter');

  MessageHandler? _handler;
  bool _running = false;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeatTimer;
  int? _heartbeatIntervalMs;
  int? _lastSequence;
  String? _sessionId;

  static const _maxRetries = 5;

  @override
  String get type => _type;

  @override
  bool get isConnected => _running && _channel != null;

  @override
  Future<void> start(MessageHandler handler) async {
    if (_running) {
      _log.warning('Discord adapter already running');
      return;
    }
    _handler = handler;
    _running = true;
    unawaited(_connect());
  }

  @override
  Future<void> stop() async {
    _running = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _sessionId = null;
    _lastSequence = null;
    _handler = null;
  }

  bool _waitingForHello = true;

  Future<void> _connect({bool resume = false}) async {
    for (var attempt = 0; attempt < _maxRetries && _running; attempt++) {
      try {
        final uri = Uri.parse(_gatewayUrl);
        final channel = WebSocketChannel.connect(uri);
        _channel = channel;
        _waitingForHello = true;

        _sub = channel.stream.listen(
          _onGatewayMessage,
          onError: (e, st) {
            _log.warning('Discord WebSocket error', e, st);
            _scheduleReconnect();
          },
          onDone: () {
            if (_running) _scheduleReconnect();
          },
          cancelOnError: false,
        );
        return;
      } catch (e, st) {
        _log.warning('Discord connect attempt ${attempt + 1} failed', e, st);
        if (attempt < _maxRetries - 1) {
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
  }

  void _handleHello(Map<String, dynamic> map, {bool resume = false}) {
    _heartbeatIntervalMs = (map['d'] as Map<String, dynamic>?)?['heartbeat_interval'] as int?;
    final ch = _channel;
    if (ch == null) return;
    if (resume && _sessionId != null && _lastSequence != null) {
      _send(ch, {
        'op': _opResume,
        'd': {
          'token': token,
          'session_id': _sessionId,
          'seq': _lastSequence,
        },
      });
    } else {
      _send(ch, {
        'op': _opIdentify,
        'd': {
          'token': token,
          'intents': 1 << 9 | 1 << 12 | 1 << 15, // GUILD_MESSAGES, DIRECT_MESSAGES, MESSAGE_CONTENT
          'properties': {'os': 'android', 'browser': 'flutter', 'device': 'flutterclaw'},
        },
      });
    }
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    if (!_running) return;
    unawaited(Future<void>.delayed(const Duration(seconds: 2))
        .then((_) => _connect(resume: _sessionId != null)));
  }

  void _onGatewayMessage(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final op = map['op'] as int? ?? -1;
      final seq = map['s'] as int?;
      if (seq != null) _lastSequence = seq;

      switch (op) {
        case _opDispatch:
          _handleDispatch(map);
          break;
        case _opHeartbeatAck:
          break;
        case _opReconnect:
          _scheduleReconnect();
          break;
        case _opInvalidSession:
          final d = map['d'] as bool?;
          if (d == false) {
            _scheduleReconnect();
          } else {
            _sessionId = null;
            _lastSequence = null;
            _scheduleReconnect();
          }
          break;
        case _opHello:
          if (_waitingForHello) {
            _waitingForHello = false;
            _handleHello(map, resume: _sessionId != null);
          }
          _startHeartbeat();
          break;
        default:
          break;
      }
    } catch (e, st) {
      _log.warning('Discord message parse error', e, st);
    }
  }

  void _handleDispatch(Map<String, dynamic> map) {
    final t = map['t'] as String?;
    final d = map['d'] as Map<String, dynamic>?;
    if (t == null || d == null) return;

    if (t == 'READY') {
      _sessionId = d['session_id'] as String?;
      return;
    }

    if (t == 'MESSAGE_CREATE') {
      _handleMessageCreate(d);
    }
  }

  void _handleMessageCreate(Map<String, dynamic> d) async {
    final author = d['author'] as Map<String, dynamic>?;
    if (author == null) return;

    final authorId = author['id'] as String? ?? '';
    final bot = d['author']?['bot'] == true;
    if (bot) return;

    final messageId = d['id'] as String? ?? '';
    final channelId = d['channel_id'] as String? ?? '';
    final content = d['content'] as String? ?? '';
    final guildId = d['guild_id'] as String?;
    final isGroup = guildId != null && guildId.isNotEmpty;

    final username = author['username'] as String? ?? 'User';
    final discriminator = author['global_name'] as String? ?? author['username'] as String? ?? '';
    final senderName = discriminator.isNotEmpty ? discriminator : username;

    // DM policy check (non-group only)
    if (!isGroup) {
      final allowed = await _checkDmPolicy(authorId, senderName, channelId);
      if (!allowed) return;
    }

    // Slash command handling
    if (content.startsWith('/') && chatCommandHandler != null) {
      final sessionKey = '$_type:$channelId';
      final response = await chatCommandHandler!(sessionKey, content);
      if (response != null) {
        await sendMessage(OutgoingMessage(
          channelType: _type,
          chatId: channelId,
          text: response,
        ));
        return;
      }
    }

    // Check for audio and image attachments
    Uint8List? audioBytes;
    String? audioFormat;
    List<String>? photoUrls;
    final attachments = d['attachments'] as List<dynamic>?;
    if (attachments != null) {
      for (final att in attachments) {
        final a = att as Map<String, dynamic>;
        final mime = a['content_type'] as String? ?? '';
        if (mime.startsWith('audio/') && audioBytes == null) {
          final url = a['url'] as String?;
          if (url != null) {
            try {
              final dlDio = Dio();
              final res = await dlDio.get<List<int>>(
                url,
                options: Options(responseType: ResponseType.bytes),
              );
              if (res.data != null) {
                audioBytes = Uint8List.fromList(res.data!);
                audioFormat = mime.contains('ogg')
                    ? 'ogg'
                    : mime.contains('wav')
                        ? 'wav'
                        : mime.contains('mp3') || mime.contains('mpeg')
                            ? 'mp3'
                            : 'm4a';
              }
            } catch (e) {
              _log.warning('Failed to download Discord audio attachment: $e');
            }
          }
        } else if (mime.startsWith('image/')) {
          final url = a['url'] as String?;
          if (url != null) {
            photoUrls ??= [];
            photoUrls.add(url);
          }
        }
      }
    }

    if (content.isEmpty && audioBytes == null && (photoUrls == null || photoUrls.isEmpty)) return;

    final incoming = IncomingMessage(
      channelType: _type,
      senderId: authorId,
      senderName: senderName,
      chatId: channelId,
      text: content,
      isGroup: isGroup,
      messageId: messageId.isNotEmpty ? messageId : null,
      replyToMessageId: (d['referenced_message'] as Map<String, dynamic>?)?['id'] as String?,
      timestamp: DateTime.now(),
      audioBytes: audioBytes,
      audioFormat: audioFormat,
      photoUrls: photoUrls,
      channelContext: {
        'channel': _type,
        'chat_id': channelId,
        'message_id': messageId,
        'sender_id': authorId,
        'is_group': isGroup.toString(),
      },
    );

    _handler?.call(incoming).catchError((e, st) {
      _log.severe('Handler error processing Discord message', e, st);
    });
  }

  /// Check DM policy. Returns true if the sender is allowed.
  Future<bool> _checkDmPolicy(
    String senderId,
    String senderName,
    String channelId,
  ) async {
    switch (dmPolicy) {
      case 'open':
        return true;

      case 'disabled':
        return false;

      case 'allowlist':
        if (allowedUserIds.isEmpty) return true;
        return allowedUserIds.contains(senderId);

      case 'pairing':
      default:
        // Static allowlist takes priority
        if (allowedUserIds.isNotEmpty && allowedUserIds.contains(senderId)) {
          return true;
        }

        if (pairingService == null) return true;

        final approved = await pairingService!.isApproved(_type, senderId);
        if (approved) return true;

        // Generate pairing code
        final code = await pairingService!.createRequest(
          _type,
          senderId,
          senderName,
        );

        if (code != null) {
          await sendMessage(OutgoingMessage(
            channelType: _type,
            chatId: channelId,
            text: 'Hi! To use this bot, send this pairing code to the owner:\n\n'
                '$code\n\n'
                'The code expires in 1 hour.',
          ));
        }

        return false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    final interval = _heartbeatIntervalMs ?? 40000;
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: interval),
      (_) => _sendHeartbeat(),
    );
  }

  void _sendHeartbeat() {
    final ch = _channel;
    if (ch == null || !_running) return;
    _send(ch, {'op': _opHeartbeat, 'd': _lastSequence});
  }

  void _send(WebSocketChannel channel, Map<String, dynamic> payload) {
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (e, st) {
      _log.warning('Discord send error', e, st);
    }
  }

  @override
  Future<void> sendMessage(OutgoingMessage message) async {
    if (message.channelType != _type) return;
    try {
      // Handle Discord-specific actions
      if (message.action != null) {
        await _handleAction(message);
        return;
      }

      // Send audio as file attachment if provided
      if (message.audioBytes != null) {
        final ext = message.audioMimeType?.contains('ogg') == true ? 'ogg' : 'wav';
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            message.audioBytes!,
            filename: 'voice.$ext',
            contentType: DioMediaType.parse(message.audioMimeType ?? 'audio/wav'),
          ),
          if (message.replyToMessageId != null)
            'payload_json': '{"message_reference":{"message_id":"${message.replyToMessageId}"}}',
        });
        await _dio.post('/channels/${message.chatId}/messages', data: formData);
      }

      // Always send text too
      if (message.text.isNotEmpty) {
        final body = <String, dynamic>{'content': message.text};
        if (message.replyToMessageId != null) {
          body['message_reference'] = {'message_id': message.replyToMessageId};
        }
        await _sendWithRateLimit(message.chatId, body);
      }
    } catch (e, st) {
      _log.severe('Failed to send Discord message', e, st);
      rethrow;
    }
  }

  Future<void> _handleAction(OutgoingMessage message) async {
    final channelId = message.chatId;
    final msgId = message.targetMessageId ?? '';
    switch (message.action) {
      case 'react':
        final encoded = Uri.encodeComponent(message.emoji ?? '');
        await _dio.put('/channels/$channelId/messages/$msgId/reactions/$encoded/@me');
      case 'unreact':
        final encoded = Uri.encodeComponent(message.emoji ?? '');
        await _dio.delete('/channels/$channelId/messages/$msgId/reactions/$encoded/@me');
      case 'edit':
        await _dio.patch('/channels/$channelId/messages/$msgId', data: {'content': message.text});
      case 'delete':
        await _dio.delete('/channels/$channelId/messages/$msgId');
      case 'typing':
        await _dio.post('/channels/$channelId/typing');
      default:
        _log.warning('Unknown Discord action: ${message.action}');
    }
  }

  Future<void> _sendWithRateLimit(String channelId, Map<String, dynamic> body) async {
    const maxAttempts = 5;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        await _dio.post('/channels/$channelId/messages', data: body);
        return;
      } on DioException catch (e) {
        if (e.response?.statusCode == 429) {
          final data = e.response?.data as Map<String, dynamic>?;
          final retryAfter = (data?['retry_after'] as num?)?.toDouble() ?? 1.0;
          _log.info('Discord rate limited, waiting ${retryAfter}s');
          await Future<void>.delayed(Duration(milliseconds: (retryAfter * 1000).round()));
        } else {
          rethrow;
        }
      }
    }
  }
}
