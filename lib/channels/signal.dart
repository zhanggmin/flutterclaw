/// Signal channel adapter via signal-cli JSON-RPC.
///
/// Signal cannot be embedded directly in a mobile app — it requires a
/// registered device with the Signal servers. This adapter connects to a
/// running signal-cli instance exposed over HTTP JSON-RPC:
///   https://github.com/bbernhard/signal-cli-rest-api
///
/// Setup:
/// 1. Run signal-cli-rest-api on a server or local machine:
///      docker run --name signal-api -p 8080:8080 \
///        -v /path/data:/home/.local/share/signal-cli \
///        bbernhard/signal-cli-rest-api
/// 2. Register/link a Signal account via the REST API docs (once).
/// 3. In FlutterClaw channels settings: enter the API URL and your phone number.
///
/// Receiving: GET /v1/receive/{account} (long-poll, returns JSON array).
/// Sending:   POST /v1/send (sends message to recipient).
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'channel_interface.dart';

const _type = 'signal';
final _log = Logger('SignalChannelAdapter');

class SignalChannelAdapter implements ChannelAdapter {
  SignalChannelAdapter({
    required this.apiUrl,
    required this.account,
    this.allowedNumbers = const [],
    this.chatCommandHandler,
  }) : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 60),
        ));

  /// Base URL of the signal-cli-rest-api instance, e.g. http://192.168.1.100:8080
  final String apiUrl;

  /// Registered Signal phone number (e.g. +12025551234)
  final String account;

  /// Whitelist of phone numbers allowed to message the bot (empty = all).
  final List<String> allowedNumbers;

  final Dio _dio;
  final Future<String?> Function(String sessionKey, String command)?
      chatCommandHandler;

  MessageHandler? _handler;
  bool _running = false;
  Timer? _reconnectTimer;

  @override
  String get type => _type;

  @override
  bool get isConnected => _running;

  @override
  Future<void> start(MessageHandler handler) async {
    if (_running) return;
    _handler = handler;
    _running = true;
    _log.info('Signal adapter started for account $account');
    _pollLoop();
  }

  @override
  Future<void> stop() async {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _handler = null;
  }

  // -----------------------------------------------------------------------
  // Long-poll receive loop
  // -----------------------------------------------------------------------

  void _pollLoop() {
    if (!_running) return;
    _receive().then((_) {
      if (_running) _pollLoop();
    }).catchError((e) {
      _log.warning('Signal receive error: $e — retrying in 10s');
      if (_running) {
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(const Duration(seconds: 10), _pollLoop);
      }
    });
  }

  Future<void> _receive() async {
    final url = '${_baseUrl()}/v1/receive/$account';
    final response = await _dio.get(
      url,
      options: Options(
        receiveTimeout: const Duration(seconds: 60),
        validateStatus: (_) => true,
      ),
    );

    if ((response.statusCode ?? 0) != 200) return;

    final messages = response.data as List? ?? [];
    for (final raw in messages) {
      _processMessage(raw as Map<String, dynamic>? ?? {});
    }
  }

  void _processMessage(Map<String, dynamic> raw) {
    final envelope = raw['envelope'] as Map<String, dynamic>? ?? {};
    final dataMessage = envelope['dataMessage'] as Map<String, dynamic>?;
    if (dataMessage == null) return; // ignore receipts, typing indicators

    final sender = envelope['source'] as String? ?? '';
    if (sender.isEmpty || sender == account) return; // ignore own messages

    if (allowedNumbers.isNotEmpty && !allowedNumbers.contains(sender)) {
      _log.fine('Signal: ignoring message from unlisted number $sender');
      return;
    }

    final text = dataMessage['message'] as String? ?? '';
    if (text.isEmpty) return;

    final timestamp = envelope['timestamp'] as int? ?? 0;
    final sessionKey = '$_type:$sender';

    // Slash command handling
    if (text.startsWith('/') && chatCommandHandler != null) {
      chatCommandHandler!(sessionKey, text.split(' ').first).then((resp) {
        if (resp != null) {
          sendMessage(OutgoingMessage(
            channelType: _type,
            chatId: sender,
            text: resp,
          ));
        }
      });
      return;
    }

    final incoming = IncomingMessage(
      channelType: _type,
      senderId: sender,
      senderName: sender,
      chatId: sender,
      text: text,
      timestamp: timestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : DateTime.now(),
    );

    _handler?.call(incoming).catchError((e) {
      _log.warning('Handler error for Signal message: $e');
    });
  }

  // -----------------------------------------------------------------------
  // Send
  // -----------------------------------------------------------------------

  @override
  Future<void> sendMessage(OutgoingMessage message) async {
    if (message.channelType != _type) return;
    try {
      await _dio.post(
        '${_baseUrl()}/v1/send',
        data: jsonEncode({
          'message': message.text,
          'number': account,
          'recipients': [message.chatId],
        }),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (_) => true,
        ),
      );
    } catch (e) {
      _log.warning('Signal send error: $e');
    }
  }

  String _baseUrl() {
    final url = apiUrl.trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}
