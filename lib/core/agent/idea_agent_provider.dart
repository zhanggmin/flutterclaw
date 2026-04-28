import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/analytics_service.dart';
import '../app_providers.dart';
import 'idea_service.dart';

class IdeaDraft {
  const IdeaDraft({
    required this.id,
    required this.rawText,
    this.title,
    this.summary,
    this.tags = const [],
    this.nextActions = const [],
    this.brainstorm,
  });

  final String id;
  final String rawText;
  final String? title;
  final String? summary;
  final List<String> tags;
  final List<String> nextActions;
  final String? brainstorm;

  IdeaDraft copyWith({
    String? title,
    String? summary,
    List<String>? tags,
    List<String>? nextActions,
    String? brainstorm,
  }) {
    return IdeaDraft(
      id: id,
      rawText: rawText,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      nextActions: nextActions ?? this.nextActions,
      brainstorm: brainstorm ?? this.brainstorm,
    );
  }
}

typedef IdeaDraftWriter = Future<void> Function(IdeaDraft updated);

final ideaServiceProvider = Provider<IdeaService>((ref) {
  final router = ref.watch(providerRouterProvider);
  return IdeaService(providerRouter: router, modelName: 'openai/gpt-4.1-mini');
});

class IdeaAgentController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// 手动触发 AI 整理（MVP：不做后台自动整理）。
  Future<IdeaDraft> runManualOrganize(
    IdeaDraft draft, {
    required IdeaDraftWriter writer,
  }) async {
    state = const AsyncLoading();
    try {
      final svc = ref.read(ideaServiceProvider);
      final analytics = ref.read(analyticsServiceProvider);

      final title = await svc.generateTitle(draft.rawText);
      final summary = await svc.generateSummary(draft.rawText);
      final tags = await svc.recommendTags(draft.rawText);
      final nextActions = await svc.extractNextActions(draft.rawText);
      final brainstorm = await svc.brainstormIdea(draft.rawText);

      final updated = draft.copyWith(
        title: title,
        summary: summary,
        tags: tags,
        nextActions: nextActions,
        brainstorm: brainstorm,
      );

      await writer(updated);

      await analytics.logAction(
        name: 'idea_agent_summarized',
        parameters: {
          'idea_id': draft.id,
          'tags_count': tags.length,
        },
      );

      for (final action in nextActions) {
        await analytics.logAction(
          name: 'idea_next_action_created',
          parameters: {
            'idea_id': draft.id,
            'action': action,
          },
        );
      }

      state = const AsyncData(null);
      return updated;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final ideaAgentControllerProvider =
    AsyncNotifierProvider<IdeaAgentController, void>(IdeaAgentController.new);
