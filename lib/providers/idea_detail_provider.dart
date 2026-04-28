import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/providers/ideas_provider.dart';

final ideaDetailProvider =
    FutureProvider.family<IdeaSummary?, String>((ref, ideaId) async {
  final cached = ref.watch(
    ideasProvider.select((value) {
      final ideas = value.valueOrNull;
      if (ideas == null) return null;
      for (final idea in ideas) {
        if (idea.id == ideaId) return idea;
      }
      return null;
    }),
  );
  if (cached != null) return cached;

  final repository = ref.read(ideasRepositoryProvider);
  return repository.getIdeaById(ideaId);
});
