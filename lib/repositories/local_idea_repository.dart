library;

import 'dart:convert';
import 'dart:io';

import 'package:flutterclaw/data/models/config.dart';
import 'package:flutterclaw/repositories/idea_repository.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _log = Logger('flutterclaw.idea_repository');

class IdeaRepositoryException implements Exception {
  final String message;
  final Object? cause;

  IdeaRepositoryException(this.message, {this.cause});

  @override
  String toString() => 'IdeaRepositoryException: $message';
}

class LocalIdeaRepository implements IdeaRepository {
  final ConfigManager configManager;

  bool _loaded = false;
  final List<Map<String, dynamic>> _cache = [];

  LocalIdeaRepository({required this.configManager});

  @override
  Future<List<Map<String, dynamic>>> listIdeas({bool includeArchived = false}) async {
    await _ensureLoaded();
    final rows = includeArchived
        ? _cache
        : _cache.where((idea) => !_isArchived(idea)).toList();
    return rows.map(_cloneMap).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>?> getIdeaById(String id) async {
    await _ensureLoaded();
    final found = _cache.where((idea) => idea['id'] == id).firstOrNull;
    return found == null ? null : _cloneMap(found);
  }

  @override
  Future<void> upsertIdea(Map<String, dynamic> idea) async {
    try {
      await _ensureLoaded();
      final id = (idea['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) {
        throw IdeaRepositoryException('idea.id 不能为空');
      }

      final idx = _cache.indexWhere((row) => row['id'] == id);
      final row = _cloneMap(idea);
      if (idx >= 0) {
        _cache[idx] = row;
      } else {
        _cache.add(row);
      }

      await _flush();
    } catch (e, st) {
      _log.severe('upsertIdea 失败: $e', e, st);
      if (e is IdeaRepositoryException) rethrow;
      throw IdeaRepositoryException('保存想法失败', cause: e);
    }
  }

  @override
  Future<void> deleteIdea(String id) async {
    try {
      await _ensureLoaded();
      _cache.removeWhere((row) => row['id'] == id);
      await _flush();
    } catch (e, st) {
      _log.severe('deleteIdea 失败: $e', e, st);
      if (e is IdeaRepositoryException) rethrow;
      throw IdeaRepositoryException('删除想法失败', cause: e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchIdeas(
    String query, {
    bool includeArchived = false,
  }) async {
    await _ensureLoaded();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return listIdeas(includeArchived: includeArchived);
    }

    final base = includeArchived
        ? _cache
        : _cache.where((idea) => !_isArchived(idea)).toList();

    final result = base.where((idea) {
      final title = (idea['title'] as String? ?? '').toLowerCase();
      final content = (idea['content'] as String? ?? '').toLowerCase();
      final summary = (idea['summary'] as String? ?? '').toLowerCase();
      final tags = ((idea['tags'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString().toLowerCase())
          .join(' ');

      final nextActions = ((idea['nextActions'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((e) => (e['text'] as String? ?? '').toLowerCase())
          .join(' ');

      return title.contains(q) ||
          content.contains(q) ||
          summary.contains(q) ||
          tags.contains(q) ||
          nextActions.contains(q);
    }).map(_cloneMap).toList(growable: false);

    return result;
  }

  @override
  Future<String> getIdeasFilePath() async {
    final ws = await configManager.workspacePath;
    return p.join(ws, 'ideas', 'ideas.json');
  }

  @override
  Future<String> getAttachmentDirectoryPath(String ideaId) async {
    final ws = await configManager.workspacePath;
    return p.join(ws, 'ideas', '$ideaId.attachments');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    try {
      final file = File(await getIdeasFilePath());
      await file.parent.create(recursive: true);

      if (!await file.exists()) {
        _loaded = true;
        _cache.clear();
        await _flush();
        return;
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _loaded = true;
        _cache.clear();
        return;
      }

      final decoded = jsonDecode(raw);
      final List<dynamic> rows = switch (decoded) {
        {'ideas': final List<dynamic> ideas} => ideas,
        List<dynamic> ideas => ideas,
        _ => const [],
      };

      _cache
        ..clear()
        ..addAll(rows.whereType<Map>().map((e) => _cloneMap(e)));
      _loaded = true;
    } catch (e, st) {
      _log.severe('加载 ideas.json 失败: $e', e, st);
      throw IdeaRepositoryException('加载想法数据失败', cause: e);
    }
  }

  Future<void> _flush() async {
    try {
      final file = File(await getIdeasFilePath());
      await file.parent.create(recursive: true);
      final payload = {'ideas': _cache};
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(payload));
    } catch (e, st) {
      _log.severe('写入 ideas.json 失败: $e', e, st);
      throw IdeaRepositoryException('写入想法数据失败', cause: e);
    }
  }

  bool _isArchived(Map<String, dynamic> idea) => idea['archived'] == true;

  Map<String, dynamic> _cloneMap(Map source) =>
      jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
}
