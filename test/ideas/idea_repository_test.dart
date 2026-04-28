import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterclaw/ideas/models/idea_item.dart';
import 'package:flutterclaw/ideas/repositories/idea_repository.dart';

void main() {
  group('IdeaRepository', () {
    late Directory tempDir;
    late IdeaRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('idea-repo-test');
      repository = IdeaRepository('${tempDir.path}/ideas/ideas.json');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('supports CRUD and search/filter/sort', () async {
      final now = DateTime.utc(2026, 4, 1);
      final idea1 = IdeaItem(
        id: '1',
        title: 'Inbox capture flow',
        description: 'Fast add from keyboard',
        status: IdeaStatus.inbox,
        tags: const <String>['mvp', 'capture'],
        createdAt: now,
        updatedAt: now,
        priority: 1,
        sourceType: 'manual',
      );

      final idea2 = IdeaItem(
        id: '2',
        title: 'Incubate with brainstorm notes',
        description: 'Attach quick brainstorming output',
        status: IdeaStatus.incubating,
        tags: const <String>['brainstorm'],
        createdAt: now,
        updatedAt: now.add(const Duration(days: 2)),
        lastBrainstormedAt: now.add(const Duration(days: 1)),
        priority: 3,
        sourceType: 'voice',
      );

      final idea3 = IdeaItem(
        id: '3',
        title: 'Archived experiment',
        description: 'No longer active',
        status: IdeaStatus.archived,
        tags: const <String>['history'],
        createdAt: now,
        updatedAt: now.add(const Duration(days: 1)),
        priority: 2,
        sourceType: 'import',
      );

      await repository.save(idea1);
      await repository.save(idea2);
      await repository.save(idea3);

      final defaultList = await repository.list();
      expect(defaultList.map((idea) => idea.id), orderedEquals(const <String>['2', '3', '1']));

      final incubatingOnly = await repository.list(
        query: const IdeaQuery(status: IdeaStatus.incubating),
      );
      expect(incubatingOnly.map((idea) => idea.id), orderedEquals(const <String>['2']));

      final tagFiltered = await repository.list(
        query: const IdeaQuery(tag: 'capture'),
      );
      expect(tagFiltered.map((idea) => idea.id), orderedEquals(const <String>['1']));

      final keywordSearch = await repository.list(
        query: const IdeaQuery(keyword: 'brainstorm'),
      );
      expect(keywordSearch.map((idea) => idea.id), orderedEquals(const <String>['2']));

      final sortedByPriorityAsc = await repository.list(
        query: const IdeaQuery(
          sort: IdeaSortOption(
            field: IdeaSortField.priority,
            direction: SortDirection.asc,
          ),
        ),
      );
      expect(sortedByPriorityAsc.map((idea) => idea.id), orderedEquals(const <String>['1', '3', '2']));

      final updatedIdea1 = idea1.copyWith(
        description: 'Fast add from keyboard and quick actions',
        updatedAt: now.add(const Duration(days: 3)),
      );
      await repository.save(updatedIdea1);

      final fetched = await repository.getById('1');
      expect(fetched, isNotNull);
      expect(fetched!.description, contains('quick actions'));

      final removed = await repository.delete('3');
      expect(removed, isTrue);
      final afterDelete = await repository.list();
      expect(afterDelete.map((idea) => idea.id), orderedEquals(const <String>['1', '2']));
    });

    test('persists source type field correctly', () async {
      final idea = IdeaItem(
        id: 'source-1',
        title: 'Source field check',
        createdAt: DateTime.utc(2026, 4, 2),
        updatedAt: DateTime.utc(2026, 4, 2),
        sourceType: 'image',
      );

      await repository.save(idea);

      final reloaded = IdeaRepository('${tempDir.path}/ideas/ideas.json');
      final loaded = await reloaded.getById('source-1');

      expect(loaded, isNotNull);
      expect(loaded!.sourceType, equals('image'));
    });
  });
}
