import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/providers/ideas_provider.dart';

class IdeaFilterState {
  const IdeaFilterState({
    this.statuses = const <IdeaStatus>{},
    this.tags = const <String>{},
    this.keyword = '',
  });

  final Set<IdeaStatus> statuses;
  final Set<String> tags;
  final String keyword;

  IdeaFilterState copyWith({
    Set<IdeaStatus>? statuses,
    Set<String>? tags,
    String? keyword,
  }) {
    return IdeaFilterState(
      statuses: statuses ?? this.statuses,
      tags: tags ?? this.tags,
      keyword: keyword ?? this.keyword,
    );
  }
}

class IdeaFilterNotifier extends Notifier<IdeaFilterState> {
  @override
  IdeaFilterState build() => const IdeaFilterState();

  void setStatuses(Set<IdeaStatus> statuses) {
    state = state.copyWith(statuses: statuses);
  }

  void toggleStatus(IdeaStatus status) {
    final next = Set<IdeaStatus>.from(state.statuses);
    if (!next.add(status)) {
      next.remove(status);
    }
    state = state.copyWith(statuses: next);
  }

  void setTags(Set<String> tags) {
    state = state.copyWith(tags: tags);
  }

  void toggleTag(String tag) {
    final normalized = tag.trim();
    if (normalized.isEmpty) return;

    final next = Set<String>.from(state.tags);
    if (!next.add(normalized)) {
      next.remove(normalized);
    }
    state = state.copyWith(tags: next);
  }

  void setKeyword(String keyword) {
    state = state.copyWith(keyword: keyword.trim());
  }

  void clear() {
    state = const IdeaFilterState();
  }
}

final ideaFilterProvider = NotifierProvider<IdeaFilterNotifier, IdeaFilterState>(
  IdeaFilterNotifier.new,
);

final filteredIdeasProvider = Provider<AsyncValue<List<IdeaSummary>>>((ref) {
  final ideasAsync = ref.watch(ideasProvider);
  final filter = ref.watch(ideaFilterProvider);

  return ideasAsync.whenData((ideas) {
    final keyword = filter.keyword.toLowerCase();

    final filtered = ideas.where((idea) {
      final statusOk =
          filter.statuses.isEmpty || filter.statuses.contains(idea.status);

      final tagsOk = filter.tags.isEmpty ||
          filter.tags.every((filterTag) => idea.tags.contains(filterTag));

      final textOk = keyword.isEmpty ||
          idea.title.toLowerCase().contains(keyword) ||
          (idea.description?.toLowerCase().contains(keyword) ?? false);

      return statusOk && tagsOk && textOk;
    }).toList(growable: false);

    return sortIdeasByUpdatedAtDesc(filtered);
  });
});
