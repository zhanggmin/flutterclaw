// ignore_for_file: unused_import
import "dart:async";
import "package:flutter/material.dart";
import "package:flutterclaw/ui/theme/tokens.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutterclaw/channels/telegram.dart";
import "package:flutterclaw/channels/channel_interface.dart";
import "package:flutterclaw/core/app_providers.dart";
import "package:flutterclaw/l10n/l10n_extension.dart";
import "package:flutterclaw/services/pairing_service.dart";
import "package:flutterclaw/data/models/config.dart";
import "package:flutterclaw/ui/widgets/security_method_card.dart";
class TelegramConfigScreen extends ConsumerStatefulWidget {
  const TelegramConfigScreen({super.key});
  @override
  ConsumerState<TelegramConfigScreen> createState() =>
      _TelegramConfigScreenState();
}

class _TelegramConfigScreenState extends ConsumerState<TelegramConfigScreen> {
  late TextEditingController _tokenCtl;
  late String _dmPolicy;

  /// id → display name
  Map<String, String> _approvedDevices = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configManagerProvider).config.channels.telegram;
    _tokenCtl = TextEditingController(text: config.token ?? '');
    _dmPolicy = config.dmPolicy;
    _loadApprovedDevices();
  }

  @override
  void dispose() {
    _tokenCtl.dispose();
    super.dispose();
  }

  Future<void> _loadApprovedDevices() async {
    final pairingService = ref.read(pairingServiceProvider);
    final map = await pairingService.getApproved('telegram');
    if (mounted) setState(() => _approvedDevices = map);
  }

  Future<void> _removeDevice(String deviceId) async {
    setState(() => _approvedDevices.remove(deviceId));

    final pairingService = ref.read(pairingServiceProvider);
    pairingService.removeApproved('telegram', deviceId);
  }

  Future<void> _addDevice() async {
    final deviceId = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add Device'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'User ID',
              hintText: 'Enter Telegram user ID',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (deviceId != null &&
        deviceId.isNotEmpty &&
        !_approvedDevices.containsKey(deviceId)) {
      setState(() => _approvedDevices[deviceId] = '');
      final pairingService = ref.read(pairingServiceProvider);
      await pairingService.addApproved('telegram', deviceId, '');
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    try {
      final configManager = ref.read(configManagerProvider);
      final token = _tokenCtl.text.trim();

      configManager.update(
        configManager.config.copyWith(
          channels: ChannelsConfig(
            telegram: TelegramConfig(
              enabled: token.isNotEmpty,
              token: token.isNotEmpty ? token : null,
              allowFrom: _dmPolicy == 'allowlist'
                  ? _approvedDevices.keys.toList()
                  : [],
              dmPolicy: _dmPolicy,
            ),
            discord: configManager.config.channels.discord,
          ),
        ),
      );
      await configManager.save();

      if (token.isNotEmpty) {
        final router = ref.read(channelRouterProvider);
        final pairingService = ref.read(pairingServiceProvider);
        final cmdHandler = ref.read(chatCommandHandlerProvider);
        router.unregisterAdapter('telegram');

        final adapter = TelegramChannelAdapter(
          token: token,
          allowedUserIds: _dmPolicy == 'allowlist'
              ? _approvedDevices.keys.toList()
              : [],
          dmPolicy: _dmPolicy,
          pairingService: pairingService,
          chatCommandHandler: (sessionKey, command) async {
            final result = await cmdHandler.handle(sessionKey, command);
            return result.handled ? result.response : null;
          },
        );

        router.registerAdapter(adapter);
        final agentLoop = ref.read(agentLoopProvider);

        await adapter.start((msg) async {
          final response = await agentLoop.processMessage(
            msg.sessionKey,
            msg.text,
            channelType: msg.channelType,
            chatId: msg.chatId,
            contentBlocks: msg.contentBlocks,
          );
          await adapter.sendMessage(
            OutgoingMessage(
              channelType: msg.channelType,
              chatId: msg.chatId,
              text: response.content,
            ),
          );
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Telegram configuration saved')),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Telegram Configuration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Bot Token Section
          Text('Bot Token', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenCtl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Bot Token',
              border: const OutlineInputBorder(),
              hintText: 'Get from @BotFather',
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Paste',
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) _tokenCtl.text = data!.text!;
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Security Method Section
          Text('Security Method', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          SecurityMethodCard(
            title: 'Pairing (Recommended)',
            description:
                'New users get a pairing code. You approve or reject them.',
            icon: Icons.link,
            isSelected: _dmPolicy == 'pairing',
            onTap: () => setState(() => _dmPolicy = 'pairing'),
            color: Colors.blue,
          ),

          SecurityMethodCard(
            title: 'Allowlist',
            description: 'Only specific user IDs can access the bot.',
            icon: Icons.list_alt,
            isSelected: _dmPolicy == 'allowlist',
            onTap: () => setState(() => _dmPolicy = 'allowlist'),
            color: Colors.green,
          ),

          SecurityMethodCard(
            title: 'Open',
            description:
                'Anyone can use the bot immediately (not recommended).',
            icon: Icons.public,
            isSelected: _dmPolicy == 'open',
            onTap: () => setState(() => _dmPolicy = 'open'),
            color: Colors.orange,
          ),

          SecurityMethodCard(
            title: 'Disabled',
            description:
                'No DMs allowed. Bot will not respond to any messages.',
            icon: Icons.block,
            isSelected: _dmPolicy == 'disabled',
            onTap: () => setState(() => _dmPolicy = 'disabled'),
            color: Colors.red,
          ),

          const SizedBox(height: 24),

          // Devices Section (shown for pairing or allowlist)
          if (_dmPolicy == 'pairing' || _dmPolicy == 'allowlist') ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dmPolicy == 'pairing'
                        ? 'Approved Devices'
                        : 'Allowed User IDs',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_dmPolicy == 'allowlist')
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add device',
                    onPressed: _addDevice,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (_approvedDevices.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        _dmPolicy == 'pairing'
                            ? Icons.link_off
                            : Icons.info_outline,
                        size: 40,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _dmPolicy == 'pairing'
                            ? 'No approved devices yet'
                            : 'No allowed users configured',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dmPolicy == 'pairing'
                            ? 'Devices will appear here after you approve their pairing requests'
                            : 'Add user IDs to allow them to use the bot',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._approvedDevices.entries.map(
                (entry) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      child: Icon(Icons.person, color: colors.primary),
                    ),
                    title: Text(
                      entry.value.isNotEmpty ? entry.value : entry.key,
                    ),
                    subtitle: Text(
                      entry.value.isNotEmpty
                          ? 'ID: ${entry.key}'
                          : (_dmPolicy == 'pairing'
                                ? 'Approved device'
                                : 'Allowed user'),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Remove',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Remove device?'),
                            content: Text(
                              'Remove access for ${entry.value.isNotEmpty ? entry.value : entry.key}?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await _removeDevice(entry.key);
                        }
                      },
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 24),
          ],

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isLoading ? 'Saving...' : 'Save & Connect'),
            ),
          ),

          const SizedBox(height: 16),

          // Help Card
          Card(
            color: colors.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, size: 20, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'How to get your bot token',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Open Telegram and search for @BotFather\n'
                    '2. Send /newbot and follow the instructions\n'
                    '3. Copy the token and paste it above',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

