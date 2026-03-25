/// Settings screen for managing MCP (Model Context Protocol) server connections.
///
/// Users can add/edit/delete servers and toggle them on/off.
/// Tools discovered from enabled servers are registered into the ToolRegistry.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'package:flutterclaw/data/models/mcp_server_config.dart';
import 'package:flutterclaw/ui/theme/tokens.dart';

class McpServersScreen extends ConsumerWidget {
  const McpServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configManager = ref.watch(configManagerProvider);
    final servers = configManager.config.mcpServers;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(context, ref, null),
          ),
        ],
      ),
      body: servers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.extension_outlined,
                        size: 56, color: colors.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      'No MCP servers configured',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add MCP servers to give your agent access to tools '
                      'from GitHub, Notion, Slack, databases, and more.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add MCP Server'),
                      onPressed: () => _openEditor(context, ref, null),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: servers.length,
              separatorBuilder: (context, i) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final server = servers[index];
                return _McpServerTile(
                  server: server,
                  onEdit: () => _openEditor(context, ref, server),
                  onToggle: (enabled) =>
                      _toggleServer(context, ref, server, enabled),
                  onDelete: () => _deleteServer(context, ref, server),
                );
              },
            ),
    );
  }

  void _openEditor(
      BuildContext context, WidgetRef ref, McpServerEntry? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _McpServerEditorScreen(existing: existing),
      ),
    ).then((_) {
      // Reconnect any newly added/modified servers if still mounted
    });
  }

  Future<void> _toggleServer(
    BuildContext context,
    WidgetRef ref,
    McpServerEntry server,
    bool enabled,
  ) async {
    final configManager = ref.read(configManagerProvider);
    final updated = server.copyWith(enabled: enabled);
    final newList = configManager.config.mcpServers
        .map((s) => s.id == server.id ? updated : s)
        .toList();
    configManager.update(configManager.config.copyWith(mcpServers: newList));
    await configManager.save();

    final mcpManager = ref.read(mcpClientManagerProvider);
    if (enabled) {
      await mcpManager.connectServer(updated);
    } else {
      await mcpManager.disconnectServer(server.id);
    }
  }

  Future<void> _deleteServer(
    BuildContext context,
    WidgetRef ref,
    McpServerEntry server,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove MCP Server'),
        content: Text(
            'Remove "${server.name}"? Its tools will no longer be available.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;

    final configManager = ref.read(configManagerProvider);
    final newList =
        configManager.config.mcpServers.where((s) => s.id != server.id).toList();
    configManager.update(configManager.config.copyWith(mcpServers: newList));
    await configManager.save();

    await ref.read(mcpClientManagerProvider).disconnectServer(server.id);
  }
}

// ─── Server tile ──────────────────────────────────────────────────────────────

class _McpServerTile extends ConsumerWidget {
  const _McpServerTile({
    required this.server,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final McpServerEntry server;
  final VoidCallback onEdit;
  final void Function(bool) onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mcpManager = ref.watch(mcpClientManagerProvider);
    final status = mcpManager.getStatus(server.id);
    final toolCount = mcpManager.getDiscoveredTools(server.id).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _statusColor(status, colors).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSM),
                ),
                child: Icon(
                  _transportIcon(server.transportType),
                  size: 20,
                  color: _statusColor(status, colors),
                ),
              ),
              const SizedBox(width: 12),
              // Name + info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(server, status, toolCount),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle
              Switch(
                value: server.enabled,
                onChanged: onToggle,
              ),
              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(McpConnectionStatus status, ColorScheme colors) {
    return switch (status) {
      McpConnectionStatus.connected => Colors.green,
      McpConnectionStatus.connecting => Colors.orange,
      McpConnectionStatus.error => colors.error,
      McpConnectionStatus.disconnected => colors.onSurfaceVariant,
    };
  }

  IconData _transportIcon(McpTransportType type) {
    return switch (type) {
      McpTransportType.stdio => Icons.terminal,
      McpTransportType.sse || McpTransportType.http => Icons.cloud_outlined,
    };
  }

  String _subtitle(
      McpServerEntry server, McpConnectionStatus status, int toolCount) {
    final transport = switch (server.transportType) {
      McpTransportType.http => 'HTTP',
      McpTransportType.sse => 'SSE',
      McpTransportType.stdio => 'stdio',
    };
    final statusStr = switch (status) {
      McpConnectionStatus.connected =>
        toolCount > 0 ? '$toolCount tools' : 'Connected',
      McpConnectionStatus.connecting => 'Connecting...',
      McpConnectionStatus.error => 'Connection error',
      McpConnectionStatus.disconnected => 'Disconnected',
    };
    return '$transport · $statusStr';
  }
}

// ─── Add / Edit screen ────────────────────────────────────────────────────────

class _McpServerEditorScreen extends ConsumerStatefulWidget {
  const _McpServerEditorScreen({this.existing});

  final McpServerEntry? existing;

  @override
  ConsumerState<_McpServerEditorScreen> createState() =>
      _McpServerEditorScreenState();
}

class _McpServerEditorScreenState
    extends ConsumerState<_McpServerEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _commandCtrl = TextEditingController();
  final _argsCtrl = TextEditingController();
  final _envCtrl = TextEditingController();

  late McpTransportType _transportType;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _transportType = e.transportType;
      _urlCtrl.text = e.baseUrl ?? '';
      _tokenCtrl.text = e.bearerToken ?? '';
      _commandCtrl.text = e.command ?? '';
      _argsCtrl.text = (e.args ?? []).join(' ');
      _envCtrl.text = (e.env ?? {}).entries.map((kv) => '${kv.key}=${kv.value}').join('\n');
    } else {
      _transportType = McpTransportType.http;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    _commandCtrl.dispose();
    _argsCtrl.dispose();
    _envCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit MCP Server' : 'Add MCP Server'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Name
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Server name',
                hintText: 'e.g. GitHub, Notion, My DB',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),

            // Transport type
            Text('Transport', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<McpTransportType>(
              segments: [
                const ButtonSegment(
                    value: McpTransportType.http,
                    label: Text('HTTP'),
                    icon: Icon(Icons.cloud_outlined)),
                const ButtonSegment(
                    value: McpTransportType.sse,
                    label: Text('SSE'),
                    icon: Icon(Icons.stream)),
                ButtonSegment(
                    value: McpTransportType.stdio,
                    label: const Text('stdio'),
                    icon: const Icon(Icons.terminal),
                    enabled: !Platform.isIOS),
              ],
              selected: {_transportType},
              onSelectionChanged: (s) =>
                  setState(() => _transportType = s.first),
            ),

            if (_transportType == McpTransportType.stdio && Platform.isIOS)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'stdio is not available on iOS. Use HTTP or SSE instead.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.error),
                ),
              ),

            const SizedBox(height: 16),

            // HTTP / SSE fields
            if (_transportType == McpTransportType.http ||
                _transportType == McpTransportType.sse) ...[
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://mcp.example.com/mcp',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'URL is required';
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme) return 'Enter a valid URL';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bearer token (optional)',
                  hintText: 'Leave blank if no auth required',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],

            // Stdio fields
            if (_transportType == McpTransportType.stdio) ...[
              TextFormField(
                controller: _commandCtrl,
                decoration: const InputDecoration(
                  labelText: 'Command',
                  hintText: 'e.g. npx or python3',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Command is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _argsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Arguments (space-separated)',
                  hintText: 'e.g. -y @modelcontextprotocol/server-github',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _envCtrl,
                decoration: const InputDecoration(
                  labelText: 'Environment variables (KEY=VALUE, one per line)',
                  hintText: 'GITHUB_TOKEN=ghp_...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                keyboardType: TextInputType.multiline,
              ),
            ],

            const SizedBox(height: 24),

            // Test connection button
            OutlinedButton.icon(
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.electrical_services_outlined),
              label: const Text('Test Connection'),
              onPressed: _testing ? null : _testConnection,
            ),

            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testResult!.startsWith('OK')
                      ? Colors.green.withValues(alpha: 0.1)
                      : colors.errorContainer,
                  borderRadius: BorderRadius.circular(AppTokens.radiusSM),
                ),
                child: Text(
                  _testResult!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _testResult!.startsWith('OK')
                        ? Colors.green.shade700
                        : colors.onErrorContainer,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            FilledButton(
              onPressed: _save,
              child: Text(isEdit ? 'Save changes' : 'Add server'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final entry = _buildEntry(
      existing: widget.existing,
      name: _nameCtrl.text.trim(),
      transportType: _transportType,
    );

    try {
      // Use a temporary manager just for the test
      final mcpManager = ref.read(mcpClientManagerProvider);
      // Temporarily connect and discover tools
      await mcpManager.connectServer(entry);
      final tools = mcpManager.getDiscoveredTools(entry.id);
      if (tools.isNotEmpty) {
        setState(() => _testResult = 'OK — ${tools.length} tools discovered');
      } else {
        final status = mcpManager.getStatus(entry.id);
        if (status == McpConnectionStatus.connected) {
          setState(() => _testResult = 'OK — Connected (0 tools)');
        } else {
          setState(() => _testResult = 'Connection failed. Check server URL/token.');
        }
      }
    } catch (e) {
      setState(() => _testResult = 'Error: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final entry = _buildEntry(
      existing: widget.existing,
      name: _nameCtrl.text.trim(),
      transportType: _transportType,
    );

    final configManager = ref.read(configManagerProvider);
    final existing = widget.existing;
    List<McpServerEntry> newList;

    if (existing != null) {
      newList = configManager.config.mcpServers
          .map((s) => s.id == existing.id ? entry : s)
          .toList();
    } else {
      newList = [...configManager.config.mcpServers, entry];
    }

    configManager.update(configManager.config.copyWith(mcpServers: newList));
    await configManager.save();

    // Connect the (new/updated) server in the background
    final mcpManager = ref.read(mcpClientManagerProvider);
    if (existing != null && existing.id != entry.id) {
      await mcpManager.disconnectServer(existing.id);
    }
    if (entry.enabled) {
      unawaited(mcpManager.connectServer(entry));
    }

    if (mounted) Navigator.pop(context);
  }

  McpServerEntry _buildEntry({
    required McpServerEntry? existing,
    required String name,
    required McpTransportType transportType,
  }) {
    Map<String, String>? parseEnv(String raw) {
      final lines = raw.trim().split('\n').where((l) => l.contains('=')).toList();
      if (lines.isEmpty) return null;
      return Map.fromEntries(lines.map((l) {
        final idx = l.indexOf('=');
        return MapEntry(l.substring(0, idx).trim(), l.substring(idx + 1).trim());
      }));
    }

    List<String>? parseArgs(String raw) {
      final parts = raw.trim().split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      return parts.isEmpty ? null : parts;
    }

    if (transportType == McpTransportType.stdio) {
      return McpServerEntry(
        id: existing?.id ?? McpServerEntry.newStdio(
          name: name,
          command: _commandCtrl.text.trim(),
        ).id,
        name: name,
        enabled: existing?.enabled ?? true,
        transportType: transportType,
        command: _commandCtrl.text.trim(),
        args: parseArgs(_argsCtrl.text),
        env: parseEnv(_envCtrl.text),
      );
    } else {
      return McpServerEntry(
        id: existing?.id ?? McpServerEntry.newHttp(
          name: name,
          baseUrl: _urlCtrl.text.trim(),
        ).id,
        name: name,
        enabled: existing?.enabled ?? true,
        transportType: transportType,
        baseUrl: _urlCtrl.text.trim(),
        bearerToken: _tokenCtrl.text.trim().isEmpty
            ? null
            : _tokenCtrl.text.trim(),
      );
    }
  }
}
