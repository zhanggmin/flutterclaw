/// Embedded WebSocket gateway implementing OpenClaw protocol.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutterclaw/core/agent/agent_loop.dart';
import 'package:flutterclaw/core/agent/session_manager.dart';
import 'package:flutterclaw/core/gateway/protocol.dart';
import 'package:flutterclaw/data/models/config.dart';
import 'package:flutterclaw/tools/registry.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final _log = Logger('flutterclaw.gateway_server');
const _uuid = Uuid();

/// Represents a connected client (operator or node).
class _Client {
  final WebSocketChannel channel;
  String? role;
  String? deviceId;
  bool connected = false;

  _Client(this.channel);
}

/// Embedded WebSocket gateway server.
class GatewayServer {
  final ConfigManager configManager;
  final AgentLoop agentLoop;
  final SessionManager sessionManager;
  final ToolRegistry toolRegistry;

  HttpServer? _server;
  final List<_Client> _clients = [];
  String _state = 'idle';
  String? _currentSessionKey;

  GatewayServer({
    required this.configManager,
    required this.agentLoop,
    required this.sessionManager,
    required this.toolRegistry,
  });

  /// Start the gateway server.
  Future<void> start() async {
    if (_server != null) {
      _log.warning('Gateway already started');
      return;
    }

    final config = configManager.config.gateway;
    final host = config.host;
    final port = config.port;

    final handler = webSocketHandler(_onConnection);

    try {
      _server = await shelf_io
          .serve(handler, host, port)
          .timeout(const Duration(seconds: 5));
      _log.info('Gateway server listening on ws://$host:${_server!.port}');
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 48 || e.osError?.errorCode == 98) {
        // Port already in use (macOS: 48, Linux: 98)
        throw SocketException('Port $port is already in use');
      }
      rethrow;
    } on TimeoutException {
      throw Exception('Gateway server startup timed out after 5 seconds');
    }
  }

  /// Stop the gateway server.
  Future<void> stop() async {
    _state = 'stopping';
    for (final client in List<_Client>.from(_clients)) {
      client.channel.sink.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    _state = 'idle';
    _log.info('Gateway server stopped');
  }

  /// Number of currently connected WebSocket clients.
  int get connectionCount => _clients.length;

  /// Check if the gateway server is healthy and responsive.
  bool isHealthy() {
    // Check if server exists and is not null
    if (_server == null) {
      _log.fine('Health check: server is null');
      return false;
    }

    // Check if server port is still valid (indicates server is bound)
    try {
      final port = _server!.port;
      if (port <= 0) {
        _log.warning('Health check: invalid port $port');
        return false;
      }
    } catch (e) {
      _log.warning('Health check: error accessing server port: $e');
      return false;
    }

    // Server appears healthy
    return true;
  }

  /// Broadcast an event to all connected clients.
  void broadcast(ProtocolFrame event) {
    final json = event.toJsonString();
    for (final client in _clients) {
      if (client.connected) {
        try {
          client.channel.sink.add(json);
        } catch (e) {
          _log.warning('Broadcast to client failed: $e');
        }
      }
    }
  }

  void _onConnection(WebSocketChannel webSocket, String? protocol) {
    final client = _Client(webSocket);
    _clients.add(client);

    webSocket.stream.listen(
      (message) => _handleMessage(client, message),
      onError: (e) => _log.warning('WebSocket error: $e'),
      onDone: () => _clients.remove(client),
      cancelOnError: false,
    );

    // Send connect challenge
    final nonce = _uuid.v4();
    final challenge = ProtocolFrame(
      type: 'event',
      event: 'connect.challenge',
      payload: ConnectChallenge(nonce: nonce, ts: DateTime.now().millisecondsSinceEpoch).toJson(),
    );
    client.channel.sink.add(challenge.toJsonString());
  }

  void _handleMessage(_Client client, dynamic message) {
    if (message is! String) return;
    final frame = ProtocolFrame.tryParse(message);
    if (frame == null) return;

    if (frame.type == 'req' && frame.method != null) {
      _handleRequest(client, frame);
    }
  }

  Future<void> _handleRequest(_Client client, ProtocolFrame req) async {
    final id = req.id ?? _uuid.v4();
    final method = req.method!;
    final params = req.params ?? {};

    try {
      final payload = await handleMethod(method, params);
      _sendResponse(client, id, true, payload);
    } catch (e) {
      _log.warning('Method $method failed: $e');
      _sendResponse(client, id, false, null, error: {'message': '$e'});
    }
  }

  void _sendResponse(
    _Client client,
    String id,
    bool ok,
    dynamic payload, {
    Map<String, dynamic>? error,
  }) {
    final res = ProtocolFrame(
      type: 'res',
      id: id,
      ok: ok,
      payload: payload,
      error: error,
    );
    client.channel.sink.add(res.toJsonString());
  }

  /// Handle a protocol method. Returns payload or throws.
  Future<dynamic> handleMethod(String method, Map<String, dynamic> params) async {
    switch (method) {
      case 'connect':
        return _handleConnect(params);
      case 'chat.send':
        return _handleChatSend(params);
      case 'status':
        return _handleStatus();
      case 'sessions.list':
        return _handleSessionsList();
      case 'sessions.history':
        return _handleSessionsHistory(params);
      case 'tools.catalog':
        return _handleToolsCatalog();
      case 'agents.list':
        return _handleAgentsList();
      case 'agents.send':
        return _handleAgentSend(params);
      case 'agents.messages':
        return _handleAgentMessages(params);
      default:
        throw UnimplementedError('Method $method');
    }
  }

  Future<Map<String, dynamic>> _handleConnect(Map<String, dynamic> params) async {
    // Token authentication: if a token is configured, reject clients that
    // don't supply the correct bearer token. Empty token = open access
    // (safe only when bound to loopback 127.0.0.1).
    final requiredToken = configManager.config.gateway.token;
    if (requiredToken.isNotEmpty) {
      final clientToken = params['token'] as String? ?? '';
      if (clientToken != requiredToken) {
        throw Exception('Unauthorized: invalid or missing gateway token');
      }
    }

    return {
      'type': 'hello-ok',
      'protocol': 3,
      'policy': {'tickIntervalMs': 15000},
    };
  }

  Future<Map<String, dynamic>> _handleChatSend(Map<String, dynamic> params) async {
    final chatParams = ChatSendParams.fromJson(params);
    final sessionKey = chatParams.sessionKey ??
        '${chatParams.channelType}:${chatParams.chatId}';

    _state = 'busy';
    _currentSessionKey = sessionKey;

    try {
      await agentLoop.processMessage(
        sessionKey,
        chatParams.text,
        channelType: chatParams.channelType,
        chatId: chatParams.chatId,
      );

      return ChatSendResult(
        messageId: _uuid.v4(),
        sessionKey: sessionKey,
      ).toJson();
    } finally {
      _state = 'idle';
      _currentSessionKey = null;
    }
  }

  Map<String, dynamic> _handleStatus() {
    return StatusResult(
      state: _state,
      currentSessionKey: _currentSessionKey,
      activeConnections: _clients.length,
    ).toJson();
  }

  Future<List<Map<String, dynamic>>> _handleSessionsList() async {
    final sessions = sessionManager.listActiveSessions();
    return sessions
        .map((s) => SessionSummary(
              key: s.key,
              channelType: s.channelType,
              chatId: s.chatId,
              messageCount: s.messageCount,
              totalTokens: s.totalTokens,
              lastActivity: s.lastActivity,
              modelOverride: s.modelOverride,
            ).toJson())
        .toList();
  }

  Future<List<Map<String, dynamic>>> _handleSessionsHistory(
    Map<String, dynamic> params,
  ) async {
    final p = SessionsHistoryParams.fromJson(params);
    final history = sessionManager.getHistory(p.sessionKey, limit: p.limit);
    return history.map((m) => m.toJson()).toList();
  }

  Map<String, dynamic> _handleToolsCatalog() {
    final defs = toolRegistry.getDefinitions();
    final tools = defs
        .map((d) => ToolCatalogEntry(
              name: d['name'] as String,
              description: d['description'] as String,
              parameters: d['parameters'] as Map<String, dynamic>,
              source: 'core',
            ))
        .toList();
    return ToolsCatalogResult(tools: tools).toJson();
  }

  /// List all available agents.
  Future<Map<String, dynamic>> _handleAgentsList() async {
    final config = configManager.config;
    final agents = config.agentProfiles;
    final activeAgentId = config.activeAgentId;

    return {
      'agents': agents.map((agent) {
        return {
          'id': agent.id,
          'name': agent.name,
          'emoji': agent.emoji,
          'model': agent.modelName,
          'status': agent.id == activeAgentId ? 'active' : 'idle',
          'vibe': agent.vibe,
        };
      }).toList(),
    };
  }

  /// Send a message from one agent to another.
  Future<Map<String, dynamic>> _handleAgentSend(Map<String, dynamic> params) async {
    final sourceAgentId = params['source_agent_id'] as String?;
    final targetAgentId = params['target_agent_id'] as String?;
    final message = params['message'] as String?;

    if (sourceAgentId == null || sourceAgentId.isEmpty) {
      throw ArgumentError('source_agent_id is required');
    }
    if (targetAgentId == null || targetAgentId.isEmpty) {
      throw ArgumentError('target_agent_id is required');
    }
    if (message == null || message.isEmpty) {
      throw ArgumentError('message is required');
    }

    // Get agent names
    final config = configManager.config;
    final sourceAgent = config.agentProfiles
        .where((a) => a.id == sourceAgentId)
        .firstOrNull;
    final targetAgent = config.agentProfiles
        .where((a) => a.id == targetAgentId)
        .firstOrNull;

    if (targetAgent == null) {
      throw ArgumentError('Target agent not found: $targetAgentId');
    }

    // Send message via session manager
    await sessionManager.sendAgentMessage(
      sourceAgentId: sourceAgentId,
      targetAgentId: targetAgentId,
      message: message,
      sourceAgentName: sourceAgent?.name,
    );

    final sessionKey = 'agent:$sourceAgentId:$targetAgentId';

    return {
      'success': true,
      'message_sent': true,
      'session_key': sessionKey,
      'from': {
        'id': sourceAgentId,
        'name': sourceAgent?.name ?? sourceAgentId,
      },
      'to': {
        'id': targetAgentId,
        'name': targetAgent.name,
      },
    };
  }

  /// Get messages sent to a specific agent.
  Future<Map<String, dynamic>> _handleAgentMessages(Map<String, dynamic> params) async {
    final agentId = params['agent_id'] as String?;

    if (agentId == null || agentId.isEmpty) {
      // Default to active agent if not specified
      final config = configManager.config;
      final activeAgent = config.activeAgent;
      if (activeAgent == null) {
        throw ArgumentError('No active agent and agent_id not specified');
      }
      final messages = await sessionManager.getAgentMessages(activeAgent.id);
      return {
        'messages': messages,
        'count': messages.length,
      };
    }

    final messages = await sessionManager.getAgentMessages(agentId);
    return {
      'messages': messages,
      'count': messages.length,
    };
  }
}
