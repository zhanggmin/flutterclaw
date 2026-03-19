// ignore_for_file: unused_import
import "package:flutter/material.dart";
import "package:flutterclaw/ui/theme/tokens.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutterclaw/channels/signal.dart";
import "package:flutterclaw/core/app_providers.dart";
import "package:flutterclaw/l10n/l10n_extension.dart";
import "package:flutterclaw/services/pairing_service.dart";
import "package:flutterclaw/data/models/config.dart";
class SignalConfigScreen extends ConsumerStatefulWidget {
  const SignalConfigScreen({super.key});
  @override
  ConsumerState<SignalConfigScreen> createState() => _SignalConfigScreenState();
}

class _SignalConfigScreenState extends ConsumerState<SignalConfigScreen> {
  late TextEditingController _apiUrlCtrl;
  late TextEditingController _accountCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final signal = ref.read(configManagerProvider).config.channels.signal;
    _apiUrlCtrl  = TextEditingController(text: signal.apiUrl ?? '');
    _accountCtrl = TextEditingController(text: signal.account ?? '');
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final apiUrl  = _apiUrlCtrl.text.trim();
    final account = _accountCtrl.text.trim();
    if (apiUrl.isEmpty || account.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API URL and phone number are required')),
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
          discord:  config.channels.discord,
          whatsapp: config.channels.whatsapp,
          slack:    config.channels.slack,
          signal: SignalConfig(
            enabled:   true,
            apiUrl:    apiUrl,
            account:   account,
            allowFrom: config.channels.signal.allowFrom,
          ),
        ),
      ));
      await configManager.save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signal saved — restart gateway to connect')),
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
      appBar: AppBar(title: const Text('Signal Configuration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Requirements', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Requires signal-cli-rest-api running on a server:\n\n'
                    '  docker run -p 8080:8080 \\\n'
                    '    -v /data:/home/.local/share/signal-cli \\\n'
                    '    bbernhard/signal-cli-rest-api\n\n'
                    'Register/link your Signal number via the REST API, '
                    'then enter the URL and your phone number below.',
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
            controller: _apiUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'signal-cli-rest-api URL',
              border: OutlineInputBorder(),
              hintText: 'http://192.168.1.100:8080',
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _accountCtrl,
            decoration: const InputDecoration(
              labelText: 'Your Signal phone number',
              border: OutlineInputBorder(),
              hintText: '+12025551234',
              prefixIcon: Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
