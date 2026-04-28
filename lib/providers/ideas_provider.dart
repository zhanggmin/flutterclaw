import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight idea status used by provider-layer filtering/actions.
enum IdeaStatus { active, inProgress, completed, archived }

class IdeaNextAction {
  const IdeaNextAction({
    required this.id,
    required this.title,
    required this.done,
  });

  final String id;
  final String title;
  final bool done;

  IdeaNextAction copyWith({
    String? id,
    String? title,
    bool? done,
  }) {
    return IdeaNextAction(
      id: id ?? this.id,
      title: title ?? this.title,
      done: done ?? this.done,
    );
  }
}

class IdeaSummary {
  const IdeaSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.tags = const <String>[],
    this.nextActions = const <IdeaNextAction>[],
    this.linkedSessionIds = const <String>[],
    this.archived = false,
  });

  final String id;
  final String title;
  final String? description;
  final IdeaStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;
  final List<IdeaNextAction> nextActions;
  final List<String> linkedSessionIds;
  final bool archived;

  IdeaSummary copyWith({
    String? id,
    String? title,
    String? description,
    IdeaStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    List<IdeaNextAction>? nextActions,
    List<String>? linkedSessionIds,
    bool? archived,
  }) {
    return IdeaSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      nextActions: nextActions ?? this.nextActions,
      linkedSessionIds: linkedSessionIds ?? this.linkedSessionIds,
      archived: archived ?? this.archived,
    );
  }
}

/// Payload object for create/update/save style mutations.
typedef IdeaDraft = Map<String, dynamic>;

abstract class IdeasRepository {
  Future<List<IdeaSummary>> listIdeas();

  Future<IdeaSummary?> getIdeaById(String ideaId);

  Future<IdeaSummary> createIdea(IdeaDraft draft);

  Future<IdeaSummary> updateIdea(String ideaId, IdeaDraft draft);

  Future<IdeaSummary> archiveIdea(String ideaId);

  Future<IdeaSummary> restoreIdea(String ideaId);

  Future<void> deleteIdea(String ideaId);

  Future<IdeaSummary> addNextAction(
    String ideaId, {
    required String title,
  });

  Future<IdeaSummary> toggleNextAction(
    String ideaId, {
    required String nextActionId,
    required bool done,
  });

  Future<IdeaSummary> linkSession(
    String ideaId, {
    required String sessionId,
  });

  Future<IdeaSummary> saveFromChat({
    required String sessionId,
    required IdeaDraft draft,
  });
}

final ideasRepositoryProvider = Provider<IdeasRepository>((_) {
  throw UnimplementedError(
    'ideasRepositoryProvider must be overridden with a concrete implementation.',
  );
});

List<IdeaSummary> sortIdeasByUpdatedAtDesc(List<IdeaSummary> ideas) {
  final sorted = List<IdeaSummary>.from(ideas);
  sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return sorted;
}

class IdeasNotifier extends AsyncNotifier<List<IdeaSummary>> {
  @override
  Future<List<IdeaSummary>> build() async {
    final repository = ref.read(ideasRepositoryProvider);
    final ideas = await repository.listIdeas();
    return sortIdeasByUpdatedAtDesc(ideas);
  }

  Future<void> refreshIdeas() async {
    state = const AsyncLoading<List<IdeaSummary>>();
    state = await AsyncValue.guard(build);
  }
}

final ideasProvider = AsyncNotifierProvider<IdeasNotifier, List<IdeaSummary>>(
  IdeasNotifier.new,
);
