import 'package:flutter_test/flutter_test.dart';
import 'package:flutterclaw/ideas/models/idea_item.dart';

void main() {
  test('idea model supports serialization and deserialization', () {
    final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final updatedAt = DateTime.utc(2026, 1, 3, 4, 5, 6);
    final brainstormedAt = DateTime.utc(2026, 1, 4, 5, 6, 7);

    final idea = IdeaItem(
      id: 'idea-1',
      title: 'Build ideas inbox',
      description: 'Capture and triage incoming ideas quickly.',
      status: IdeaStatus.incubating,
      tags: const <String>['product', 'mvp'],
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastBrainstormedAt: brainstormedAt,
      priority: 2,
      sourceType: 'voice',
    );

    final json = idea.toJson();
    final restored = IdeaItem.fromJson(json);

    expect(restored.id, idea.id);
    expect(restored.title, idea.title);
    expect(restored.description, idea.description);
    expect(restored.status, idea.status);
    expect(restored.tags, idea.tags);
    expect(restored.createdAt, idea.createdAt);
    expect(restored.updatedAt, idea.updatedAt);
    expect(restored.lastBrainstormedAt, idea.lastBrainstormedAt);
    expect(restored.priority, idea.priority);
    expect(restored.sourceType, idea.sourceType);
  });
}
