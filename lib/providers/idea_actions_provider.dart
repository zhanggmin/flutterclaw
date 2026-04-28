import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/providers/idea_detail_provider.dart';
import 'package:flutterclaw/providers/ideas_provider.dart';
import 'package:flutterclaw/services/analytics_service.dart';

class IdeaActions {
  IdeaActions(this._ref);

  final Ref _ref;

  IdeasRepository get _repository => _ref.read(ideasRepositoryProvider);

  Future<void> _logAction(String name, {Map<String, Object>? parameters}) {
    return _ref
        .read(analyticsServiceProvider)
        .logAction(name: name, parameters: parameters);
  }

  void _invalidateListAndDetail(String ideaId) {
    _ref.invalidate(ideasProvider);
    _ref.invalidate(ideaDetailProvider(ideaId));
  }

  Future<IdeaSummary> create(IdeaDraft draft) async {
    final created = await _repository.createIdea(draft);
    await _logAction(
      'idea_created',
      parameters: {'idea_id': created.id},
    );
    _invalidateListAndDetail(created.id);
    return created;
  }

  Future<IdeaSummary> update(String ideaId, IdeaDraft draft) async {
    final updated = await _repository.updateIdea(ideaId, draft);
    await _logAction('idea_updated', parameters: {'idea_id': ideaId});
    _invalidateListAndDetail(updated.id);
    return updated;
  }

  Future<IdeaSummary> archive(String ideaId) async {
    final archived = await _repository.archiveIdea(ideaId);
    await _logAction('idea_archived', parameters: {'idea_id': ideaId});
    _invalidateListAndDetail(archived.id);
    return archived;
  }

  Future<IdeaSummary> restore(String ideaId) async {
    final restored = await _repository.restoreIdea(ideaId);
    await _logAction('idea_restored', parameters: {'idea_id': ideaId});
    _invalidateListAndDetail(restored.id);
    return restored;
  }

  Future<void> delete(String ideaId) async {
    await _repository.deleteIdea(ideaId);
    await _logAction('idea_deleted', parameters: {'idea_id': ideaId});
    _invalidateListAndDetail(ideaId);
  }

  Future<IdeaSummary> addNextAction(
    String ideaId, {
    required String title,
  }) async {
    final updated = await _repository.addNextAction(ideaId, title: title);
    await _logAction(
      'idea_next_action_added',
      parameters: {'idea_id': ideaId},
    );
    _invalidateListAndDetail(updated.id);
    return updated;
  }

  Future<IdeaSummary> toggleNextAction(
    String ideaId, {
    required String nextActionId,
    required bool done,
  }) async {
    final updated = await _repository.toggleNextAction(
      ideaId,
      nextActionId: nextActionId,
      done: done,
    );
    await _logAction(
      'idea_next_action_toggled',
      parameters: {
        'idea_id': ideaId,
        'next_action_id': nextActionId,
        'done': done,
      },
    );
    _invalidateListAndDetail(updated.id);
    return updated;
  }

  Future<IdeaSummary> linkSession(
    String ideaId, {
    required String sessionId,
  }) async {
    final updated = await _repository.linkSession(ideaId, sessionId: sessionId);
    await _logAction(
      'idea_session_linked',
      parameters: {
        'idea_id': ideaId,
        'session_id': sessionId,
      },
    );
    _invalidateListAndDetail(updated.id);
    return updated;
  }

  Future<IdeaSummary> saveFromChat({
    required String sessionId,
    required IdeaDraft draft,
  }) async {
    final saved = await _repository.saveFromChat(
      sessionId: sessionId,
      draft: draft,
    );
    await _logAction(
      'idea_saved_from_chat',
      parameters: {
        'idea_id': saved.id,
        'session_id': sessionId,
      },
    );
    _invalidateListAndDetail(saved.id);
    return saved;
  }
}

final ideaActionsProvider = Provider<IdeaActions>(IdeaActions.new);
