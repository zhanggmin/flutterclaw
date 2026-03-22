// ignore_for_file: unused_import
import "package:flutter/material.dart";
import "package:flutterclaw/ui/theme/tokens.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutterclaw/channels/slack.dart";
import "package:flutterclaw/core/app_providers.dart";
import "package:flutterclaw/l10n/l10n_extension.dart";
import "package:flutterclaw/services/pairing_service.dart";
import "package:flutterclaw/data/models/config.dart";
class SlackConfigScreen extends ConsumerStatefulWidget {
  const SlackConfigScreen({super.key});
  @override
  ConsumerState<SlackConfigScreen> createState() => _SlackConfigScreenState();
}

class _SlackConfigScreenState extends ConsumerState<SlackConfigScreen> {
  late TextEditingController _botTokenCtrl;
  late TextEditingController _appTokenCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final slack = ref.read(configManagerProvider).config.channels.slack;
    _botTokenCtrl = TextEditingController(text: slack.botToken ?? '');
    _appTokenCtrl = TextEditingController(text: slack.appToken ?? '');
  }

  @override
  void dispose() {
    _botTokenCtrl.dispose();
    _appTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final botToken = _botTokenCtrl.text.trim();
    final appToken = _appTokenCtrl.text.trim();
    if (botToken.isEmpty || appToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.bothTokensRequired)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final configManager = ref.read(configManagerProvider);
      final config = configManager.config;
      configManager.update(config.copyWith(
        channels: ChannelsConfig(
          telegram: config.channels.telegram,
          discord: config.channels.discord,
          whatsapp: config.channels.whatsapp,
          slack: SlackConfig(
            enabled: true,
            botToken: botToken,
            appToken: appToken,
            allowFrom: config.channels.slack.allowFrom,
          ),
        ),
      ));
      await configManager.save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.slackSavedRestart),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.slackConfiguration)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.setupTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.slackSetupInstructions,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _botTokenCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.l10n.botTokenXoxb,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _appTokenCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.l10n.appLevelToken,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.vpn_key_outlined),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(context.l10n.saveAndConnect),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Signal Configuration Screen
// ---------------------------------------------------------------------------

