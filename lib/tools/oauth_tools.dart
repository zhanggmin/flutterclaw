/// OAuth tools for FlutterClaw agents.
///
/// Provides `oauth_authorize` to initiate an OAuth flow and
/// `oauth_token` to retrieve/inspect stored tokens.
library;

import 'dart:convert';

import '../services/oauth_service.dart';
import 'registry.dart';

/// Start an OAuth 2.0 Authorization Code flow with PKCE.
class OAuthAuthorizeTool extends Tool {
  final List<OAuthConnection> Function() _connectionsGetter;
  final OAuthService _service;

  OAuthAuthorizeTool(this._connectionsGetter, this._service);

  @override
  String get name => 'oauth_authorize';

  @override
  String get description =>
      'Start an OAuth 2.0 authorization flow for a configured connection. '
      'Opens an in-app browser for the user to sign in. '
      'Uses PKCE (Proof Key for Code Exchange) for security.\n\n'
      'After authorization, the access token is stored securely and can be '
      'retrieved with oauth_token for use in http_request headers.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'connection_id': {
            'type': 'string',
            'description':
                'OAuth connection ID to authorize. '
                'Use oauth_token with action "list" to see available connections.',
          },
        },
        'required': ['connection_id'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final connId = (args['connection_id'] as String?)?.trim() ?? '';
    if (connId.isEmpty) return ToolResult.error('"connection_id" is required.');

    final connections = _connectionsGetter();
    if (connections.isEmpty) {
      return ToolResult.error(
        'No OAuth connections configured. '
        'Add one in Settings → OAuth first.',
      );
    }

    final conn = connections.where((c) => c.id == connId).firstOrNull;
    if (conn == null) {
      return ToolResult.error(
        'OAuth connection "$connId" not found. '
        'Available: ${connections.map((c) => '${c.id} (${c.label})').join(", ")}',
      );
    }

    try {
      final tokenData = await _service.authorize(conn);
      final accessToken = tokenData['access_token'] as String? ?? '';
      final expiresIn = tokenData['expires_in'];
      final scope = tokenData['scope'] ?? conn.scopes;
      return ToolResult.success(
        'OAuth authorization successful for "${conn.label}".\n'
        'Access token: ${accessToken.substring(0, 10)}...(${accessToken.length} chars)\n'
        'Expires in: $expiresIn seconds\n'
        'Scopes: $scope\n\n'
        'Use oauth_token to retrieve the full token for http_request headers.',
      );
    } catch (e) {
      return ToolResult.error('OAuth authorization failed: $e');
    }
  }
}

/// Retrieve, inspect, or revoke stored OAuth tokens.
class OAuthTokenTool extends Tool {
  final List<OAuthConnection> Function() _connectionsGetter;
  final OAuthService _service;

  OAuthTokenTool(this._connectionsGetter, this._service);

  @override
  String get name => 'oauth_token';

  @override
  String get description =>
      'Manage OAuth tokens. Actions:\n'
      '- **get**: Retrieve the access token for a connection (auto-refreshes if expired).\n'
      '- **list**: List all configured OAuth connections and their auth status.\n'
      '- **revoke**: Delete stored tokens for a connection.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['get', 'list', 'revoke'],
            'description': 'Action to perform. Default: "get".',
          },
          'connection_id': {
            'type': 'string',
            'description':
                'OAuth connection ID. Required for "get" and "revoke".',
          },
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final action = (args['action'] as String?) ?? 'get';
    final connId = args['connection_id'] as String?;

    final connections = _connectionsGetter();

    switch (action) {
      case 'list':
        if (connections.isEmpty) {
          return ToolResult.success('No OAuth connections configured.');
        }
        final items = <Map<String, dynamic>>[];
        for (final conn in connections) {
          final token = await _service.getAccessToken(conn);
          items.add({
            'id': conn.id,
            'label': conn.label,
            'scopes': conn.scopes,
            'authenticated': token != null,
          });
        }
        return ToolResult.success(
          const JsonEncoder.withIndent('  ').convert(items),
        );

      case 'get':
        if (connId == null || connId.isEmpty) {
          return ToolResult.error('"connection_id" required for "get" action.');
        }
        final conn = connections.where((c) => c.id == connId).firstOrNull;
        if (conn == null) {
          return ToolResult.error('OAuth connection "$connId" not found.');
        }
        final token = await _service.getAccessToken(conn);
        if (token == null) {
          return ToolResult.error(
            'No valid token for "$connId". '
            'Run oauth_authorize first.',
          );
        }
        return ToolResult.success(
          'Bearer $token\n\n'
          'Use this as the Authorization header value in http_request.',
        );

      case 'revoke':
        if (connId == null || connId.isEmpty) {
          return ToolResult.error(
            '"connection_id" required for "revoke" action.',
          );
        }
        await _service.revokeToken(connId);
        return ToolResult.success('Tokens revoked for "$connId".');

      default:
        return ToolResult.error('Unknown action "$action".');
    }
  }
}
