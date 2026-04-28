library;

import 'dart:convert';
import 'dart:io';

import 'package:flutterclaw/ideas/models/idea_item.dart';

class IdeaQuery {
  const IdeaQuery({
    this.status,
    this.tag,
    this.keyword,
    this.sort = const IdeaSortOption(),
  });

  final IdeaStatus? status;
  final String? tag;
  final String? keyword;
  final IdeaSortOption sort;
}

class IdeaRepository {
  IdeaRepository(this._filePath);

  final String _filePath;
  final List<IdeaItem> _ideas = <IdeaItem>[];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final file = File(_filePath);
    if (!await file.exists()) return;

    final raw = await file.readAsString();
    final list = jsonDecode(raw) as List<dynamic>;
    _ideas
      ..clear()
      ..addAll(
        list
            .map((value) => IdeaItem.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );
  }

  Future<List<IdeaItem>> list({IdeaQuery query = const IdeaQuery()}) async {
    await load();

    final filtered = _ideas.where((idea) {
      if (query.status != null && idea.status != query.status) {
        return false;
      }
      if (query.tag != null &&
          query.tag!.isNotEmpty &&
          !idea.tags.contains(query.tag)) {
        return false;
      }
      if (query.keyword != null && query.keyword!.trim().isNotEmpty) {
        final needle = query.keyword!.toLowerCase();
        final text =
            '${idea.title}\n${idea.description}\n${idea.tags.join(' ')}'
                .toLowerCase();
        if (!text.contains(needle)) return false;
      }
      return true;
    }).toList(growable: false);

    filtered.sort((a, b) => _sortCompare(a, b, query.sort));
    return filtered;
  }

  Future<IdeaItem?> getById(String id) async {
    await load();
    for (final idea in _ideas) {
      if (idea.id == id) return idea;
    }
    return null;
  }

  Future<void> save(IdeaItem idea) async {
    await load();

    final index = _ideas.indexWhere((item) => item.id == idea.id);
    if (index == -1) {
      _ideas.add(idea);
    } else {
      _ideas[index] = idea;
    }

    await _persist();
  }

  Future<bool> delete(String id) async {
    await load();
    final before = _ideas.length;
    _ideas.removeWhere((item) => item.id == id);
    if (_ideas.length == before) return false;
    await _persist();
    return true;
  }

  int _sortCompare(IdeaItem a, IdeaItem b, IdeaSortOption sort) {
    late final int result;
    switch (sort.field) {
      case IdeaSortField.updatedAt:
        result = a.updatedAt.compareTo(b.updatedAt);
        break;
      case IdeaSortField.lastBrainstormedAt:
        final aValue =
            a.lastBrainstormedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bValue =
            b.lastBrainstormedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        result = aValue.compareTo(bValue);
        break;
      case IdeaSortField.priority:
        result = (a.priority ?? 0).compareTo(b.priority ?? 0);
        break;
    }

    return sort.direction == SortDirection.asc ? result : -result;
  }

  Future<void> _persist() async {
    final file = File(_filePath);
    await file.parent.create(recursive: true);

    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(
        _ideas.map((idea) => idea.toJson()).toList(growable: false),
      ),
    );
  }
}
