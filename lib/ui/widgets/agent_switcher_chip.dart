import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/core/agent/session_manager.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'package:flutterclaw/data/models/agent_profile.dart';
import 'package:flutterclaw/l10n/l10n_extension.dart';
import 'package:flutterclaw/ui/widgets/channel_brand_icon.dart';

class SessionSwitcherChip extends ConsumerWidget {
  const SessionSwitcherChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeKey = ref.watch(activeSessionKeyProvider);
    final sessionsAsync = ref.watch(activeSessionsProvider);
    final agents = ref.watch(agentProfilesProvider);
    final activeAgent = ref.watch(activeAgentProvider);
    final configManager = ref.read(configManagerProvider);
    final sessionManager = ref.read(sessionManagerProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final sessions = sessionsAsync.asData?.value ?? [];
    final activeSession =
        sessions.where((s) => s.key == activeKey).firstOrNull;

    final isLive = activeSession != null &&
        DateTime.now().difference(activeSession.lastActivity).inSeconds < 60;

    String resolveModel(SessionMeta s) =>
        resolveSessionModelName(s.key, configManager, sessionManager);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _showSessionPicker(
              context, ref, sessions, agents, activeAgent, activeKey,
              resolveModel),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChannelBrandIcon(
                  channelType: activeKey.split(':').first,
                  size: 18,
                  iconColor: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    _sessionLabel(context, activeKey, activeSession, agents, activeAgent),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLive) ...[
                  const SizedBox(width: 6),
                  _LiveDot(color: colors.primary),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.unfold_more,
                  size: 16,
                  color: colors.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSessionPicker(
    BuildContext context,
    WidgetRef ref,
    List<SessionMeta> sessions,
    List<AgentProfile> agents,
    AgentProfile? activeAgent,
    String activeKey,
    String Function(SessionMeta) resolveModel,
  ) {
    // Filter out inter-agent communication sessions; sort by lastActivity desc.
    final visible = sessions
        .where((s) => !s.key.startsWith('agent:'))
        .toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.l10n.sessions,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.l10n.noActiveSessions,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                  final session = visible[index];
                  final isActive = session.key == activeKey;
                  final label =
                      _sessionLabel(context, session.key, session, agents, activeAgent);
                  final channel = session.key.split(':').first;
                  final model = resolveModel(session);
                  final subtitle = _sessionSubtitle(context, session, model);
                  final scheme = Theme.of(context).colorScheme;

                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isActive
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: ChannelBrandIcon(
                          channelType: channel,
                          size: 22,
                          iconColor: isActive
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    title: Text(
                      label,
                      style:
                          Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight:
                                    isActive ? FontWeight.w600 : null,
                              ),
                    ),
                    subtitle: Text(subtitle),
                    trailing: isActive
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (!isActive) {
                        await ref
                            .read(chatProvider.notifier)
                            .switchToSession(session.key);
                      }
                    },
                  );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static String _sessionLabel(
    BuildContext context,
    String key,
    SessionMeta? meta,
    List<AgentProfile> agents,
    AgentProfile? activeAgent,
  ) {
    final l10n = context.l10n;
    final parts = key.split(':');
    final channelType = parts.isNotEmpty ? parts[0] : key;
    final chatId = parts.length > 1 ? parts.sublist(1).join(':') : '';

    // Resolve which agent name to show.
    // webchat sessions encode the agentId in chatId; others use the active agent.
    final AgentProfile? agent = channelType == 'webchat'
        ? agents.where((a) => a.id == chatId).firstOrNull
        : activeAgent;
    final agentName = agent?.name ?? '';

    final channelLabel = switch (channelType) {
      'webchat' => l10n.channelApp,
      'telegram' => l10n.telegram,
      'discord' => l10n.discord,
      'heartbeat' => l10n.channelHeartbeat,
      'cron' => l10n.channelCron,
      'subagent' => l10n.channelSubagent,
      'system' => l10n.channelSystem,
      _ => channelType,
    };

    return agentName.isNotEmpty ? '$agentName · $channelLabel' : channelLabel;
  }

  static String _sessionSubtitle(BuildContext context, SessionMeta meta, String modelName) {
    final l10n = context.l10n;
    final diff = DateTime.now().difference(meta.lastActivity);
    String ago;
    if (diff.inSeconds < 60) {
      ago = l10n.secondsAgo(diff.inSeconds);
    } else if (diff.inMinutes < 60) {
      ago = l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      ago = l10n.hoursAgo(diff.inHours);
    } else {
      ago = l10n.daysAgo(diff.inDays);
    }
    return '$modelName · ${meta.messageCount} ${l10n.messagesAbbrev} · $ago';
  }
}

class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color
              .withValues(alpha: 0.4 + _controller.value * 0.6),
        ),
      ),
    );
  }
}
