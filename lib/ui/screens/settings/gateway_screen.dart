import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'package:flutterclaw/data/models/config.dart';
import 'package:flutterclaw/l10n/l10n_extension.dart';

/// Gateway & Heartbeat settings sub-screen.
class GatewayScreen extends ConsumerStatefulWidget {
  const GatewayScreen({super.key});

  @override
  ConsumerState<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends ConsumerState<GatewayScreen> {
  @override
  Widget build(BuildContext context) {
    final configManager = ref.watch(configManagerProvider);
    final config = configManager.config;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.gateway)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Gateway
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: Text(context.l10n.host),
                  trailing: Text(
                    config.gateway.host,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.numbers),
                  title: Text(context.l10n.port),
                  trailing: Text(
                    '${config.gateway.port}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.play_circle_outline),
                  title: Text(context.l10n.autoStart),
                  subtitle: Text(context.l10n.startGatewayWhenLaunches),
                  value: config.gateway.autoStart,
                  onChanged: (val) async {
                    configManager.update(config.copyWith(
                      gateway: GatewayConfig(
                        host: config.gateway.host,
                        port: config.gateway.port,
                        autoStart: val,
                        token: config.gateway.token,
                      ),
                    ));
                    await configManager.save();
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Access token'),
                  subtitle: Text(
                    config.gateway.token.isEmpty
                        ? 'Not set — open access (loopback only)'
                        : '••••••••',
                    style: TextStyle(
                      color: config.gateway.token.isEmpty
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editToken(context, config, configManager),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Heartbeat
          Text(
            context.l10n.heartbeat,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.favorite_outline),
                  title: Text(context.l10n.enabled),
                  subtitle: Text(context.l10n.periodicAgentTasks),
                  value: config.heartbeat.enabled,
                  onChanged: (val) async {
                    configManager.update(config.copyWith(
                      heartbeat: HeartbeatConfig(
                        enabled: val,
                        interval: config.heartbeat.interval,
                      ),
                    ));
                    await configManager.save();
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer),
                  title: Text(context.l10n.interval),
                  trailing:
                      Text(context.l10n.intervalMinutes(config.heartbeat.interval)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editToken(
    BuildContext context,
    FlutterClawConfig config,
    dynamic configManager,
  ) async {
    final controller = TextEditingController(text: config.gateway.token);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gateway access token'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Token',
            hintText: 'Leave empty to disable auth',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    configManager.update(config.copyWith(
      gateway: GatewayConfig(
        host: config.gateway.host,
        port: config.gateway.port,
        autoStart: config.gateway.autoStart,
        token: result,
      ),
    ));
    await configManager.save();
    if (mounted) setState(() {});
  }
}
