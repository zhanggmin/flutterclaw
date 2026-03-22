// ignore_for_file: unused_import
import "package:flutter/material.dart";
import "package:flutterclaw/ui/theme/tokens.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutterclaw/channels/discord.dart";
import "package:flutterclaw/channels/channel_interface.dart";
import "package:flutterclaw/core/app_providers.dart";
import "package:flutterclaw/l10n/l10n_extension.dart";
import "package:flutterclaw/services/pairing_service.dart";
import "package:flutterclaw/data/models/config.dart";
import "package:flutterclaw/ui/widgets/security_method_card.dart";
class DiscordConfigScreen extends ConsumerStatefulWidget {
  const DiscordConfigScreen({super.key});
  @override
  ConsumerState<DiscordConfigScreen> createState() =>
      _DiscordConfigScreenState();
}

class _DiscordConfigScreenState extends ConsumerState<DiscordConfigScreen> {
  late TextEditingController _tokenCtl;
  late String _dmPolicy;

  /// id → display name
  Map<String, String> _approvedDevices = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configManagerProvider).config.channels.discord;
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
    final map = await pairingService.getApproved('discord');
    if (mounted) setState(() => _approvedDevices = map);
  }

  Future<void> _removeDevice(String deviceId) async {
    setState(() => _approvedDevices.remove(deviceId));
    final pairingService = ref.read(pairingServiceProvider);
    pairingService.removeApproved('discord', deviceId);
  }

  Future<void> _addDevice() async {
    final deviceId = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(context.l10n.addDevice),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: context.l10n.userIdLabel,
              hintText: context.l10n.enterDiscordUserId,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(context.l10n.add),
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
      await pairingService.addApproved('discord', deviceId, '');
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
            telegram: configManager.config.channels.telegram,
            discord: DiscordConfig(
              enabled: token.isNotEmpty,
              token: token.isNotEmpty ? token : null,
              allowFrom: _dmPolicy == 'allowlist'
                  ? _approvedDevices.keys.toList()
                  : [],
              dmPolicy: _dmPolicy,
            ),
          ),
        ),
      );
      await configManager.save();

      if (token.isNotEmpty) {
        final router = ref.read(channelRouterProvider);
        final pairingService = ref.read(pairingServiceProvider);
        final cmdHandler = ref.read(chatCommandHandlerProvider);
        router.unregisterAdapter('discord');

        final adapter = DiscordChannelAdapter(
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
          SnackBar(content: Text(context.l10n.discordConfigSaved)),
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
      appBar: AppBar(title: Text(context.l10n.discordConfiguration)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Bot Token Section
          Text(context.l10n.botToken, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenCtl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.l10n.botToken,
              border: const OutlineInputBorder(),
              hintText: context.l10n.fromDiscordDevPortal,
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                tooltip: context.l10n.paste,
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) _tokenCtl.text = data!.text!;
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Security Method Section
          Text(context.l10n.securityMethod, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          SecurityMethodCard(
            title: context.l10n.pairingRecommended,
            description: context.l10n.pairingDescription,
            icon: Icons.link,
            isSelected: _dmPolicy == 'pairing',
            onTap: () => setState(() => _dmPolicy = 'pairing'),
            color: Colors.blue,
          ),

          SecurityMethodCard(
            title: context.l10n.allowlistTitle,
            description: context.l10n.allowlistDescription,
            icon: Icons.list_alt,
            isSelected: _dmPolicy == 'allowlist',
            onTap: () => setState(() => _dmPolicy = 'allowlist'),
            color: Colors.green,
          ),

          SecurityMethodCard(
            title: context.l10n.openAccess,
            description: context.l10n.openAccessDescription,
            icon: Icons.public,
            isSelected: _dmPolicy == 'open',
            onTap: () => setState(() => _dmPolicy = 'open'),
            color: Colors.orange,
          ),

          SecurityMethodCard(
            title: context.l10n.disabledAccess,
            description: context.l10n.disabledAccessDescription,
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
                        ? context.l10n.approvedDevices
                        : context.l10n.allowedUserIdsTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_dmPolicy == 'allowlist')
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    tooltip: context.l10n.addDeviceTooltip,
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
                            ? context.l10n.noApprovedDevicesYet
                            : context.l10n.noAllowedUsersConfigured,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dmPolicy == 'pairing'
                            ? context.l10n.devicesAppearAfterApproval
                            : context.l10n.addUserIdsHint,
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
                          ? context.l10n.idPrefix(entry.key)
                          : (_dmPolicy == 'pairing'
                                ? context.l10n.approvedDevice
                                : context.l10n.allowedUser),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: context.l10n.remove,
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(context.l10n.removeDevice),
                            content: Text(
                              context.l10n.removeAccessFor(entry.value.isNotEmpty ? entry.value : entry.key),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(context.l10n.cancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(context.l10n.remove),
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
              label: Text(_isLoading ? context.l10n.saving : context.l10n.saveAndConnect),
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
                        context.l10n.howToGetBotToken,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.discordTokenInstructions,
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

// ---------------------------------------------------------------------------
// WhatsApp Configuration Screen
// ---------------------------------------------------------------------------

