library;

import 'dart:math';

import 'package:flutterclaw/repositories/idea_repository.dart';
import 'package:logging/logging.dart';

final _log = Logger('flutterclaw.idea_service');

class IdeaServiceException implements Exception {
  final String message;
  final Object? cause;

  IdeaServiceException(this.message, {this.cause});

  @override
  String toString() => 'IdeaServiceException: $message';
}

class IdeaService {
  final IdeaRepository repository;

  IdeaService({required this.repository});

  Future<List<Map<String, dynamic>>> listIdeas({bool includeArchived = false}) {
    return repository.listIdeas(includeArchived: includeArchived);
  }

  Future<Map<String, dynamic>?> getIdeaById(String id) {
    return repository.getIdeaById(id);
  }

  Future<Map<String, dynamic>> saveIdea(Map<String, dynamic> idea) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final normalized = <String, dynamic>{
        ...idea,
        'id': (idea['id'] as String?)?.trim().isNotEmpty == true
            ? (idea['id'] as String).trim()
            : _newIdeaId(),
        'title': (idea['title'] as String? ?? '').trim(),
        'content': (idea['content'] as String? ?? '').trim(),
        'summary': (idea['summary'] as String? ?? '').trim(),
        'tags': ((idea['tags'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .toSet()
            .toList(),
        'nextActions': (idea['nextActions'] as List<dynamic>?) ?? const [],
        'sources': (idea['sources'] as List<dynamic>?) ?? const [],
        'archived': idea['archived'] == true,
        'createdAt': idea['createdAt'] as String? ?? now,
        'updatedAt': now,
      };

      await repository.upsertIdea(normalized);
      return normalized;
    } catch (e, st) {
      _log.severe('saveIdea 失败: $e', e, st);
      if (e is IdeaServiceException) rethrow;
      throw IdeaServiceException('保存想法失败', cause: e);
    }
  }

  /// 保存当前 idea，并基于它发散出一个新 idea。
  Future<Map<String, dynamic>> saveAndDiverge({
    required String ideaId,
    required String divergedTitle,
    String divergedContent = '',
    String? sourceNote,
  }) async {
    try {
      final base = await repository.getIdeaById(ideaId);
      if (base == null) {
        throw IdeaServiceException('想法不存在: $ideaId');
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final source = <String, dynamic>{
        'type': 'diverged_from',
        'ideaId': ideaId,
        'note': sourceNote ?? '',
        'createdAt': now,
      };

      final nextSources = [...((base['sources'] as List<dynamic>?) ?? const [])];
      if (sourceNote != null && sourceNote.trim().isNotEmpty) {
        nextSources.add(source);
      }

      await repository.upsertIdea({
        ...base,
        'sources': nextSources,
        'updatedAt': now,
      });

      final child = await saveIdea({
        'title': divergedTitle,
        'content': divergedContent,
        'summary': '',
        'tags': (base['tags'] as List<dynamic>?) ?? const [],
        'sources': [source],
        'parentId': ideaId,
      });

      return child;
    } catch (e, st) {
      _log.severe('saveAndDiverge 失败: $e', e, st);
      if (e is IdeaServiceException) rethrow;
      throw IdeaServiceException('保存并发散失败', cause: e);
    }
  }

  Future<void> archiveIdea(String ideaId) async {
    try {
      final row = await repository.getIdeaById(ideaId);
      if (row == null) throw IdeaServiceException('想法不存在: $ideaId');
      final now = DateTime.now().toUtc().toIso8601String();
      await repository.upsertIdea({
        ...row,
        'archived': true,
        'archivedAt': now,
        'updatedAt': now,
      });
    } catch (e, st) {
      _log.severe('archiveIdea 失败: $e', e, st);
      if (e is IdeaServiceException) rethrow;
      throw IdeaServiceException('归档想法失败', cause: e);
    }
  }

  Future<void> restoreIdea(String ideaId) async {
    try {
      final row = await repository.getIdeaById(ideaId);
      if (row == null) throw IdeaServiceException('想法不存在: $ideaId');
      final now = DateTime.now().toUtc().toIso8601String();
      await repository.upsertIdea({
        ...row,
        'archived': false,
        'archivedAt': null,
        'updatedAt': now,
      });
    } catch (e, st) {
      _log.severe('restoreIdea 失败: $e', e, st);
      if (e is IdeaServiceException) rethrow;
      throw IdeaServiceException('恢复想法失败', cause: e);
    }
  }

  Future<void> appendSource(
    String ideaId,
    Map<String, dynamic> source,
  ) async {
    try {
      final row = await repository.getIdeaById(ideaId);
      if (row == null) throw IdeaServiceException('想法不存在: $ideaId');
      final now = DateTime.now().toUtc().toIso8601String();

      final nextSources = [...((row['sources'] as List<dynamic>?) ?? const [])]
        ..add({
          ...source,
          'createdAt': source['createdAt'] as String? ?? now,
        });

      await repository.upsertIdea({
        ...row,
        'sources': nextSources,
        'updatedAt': now,
      });
    } catch (e, st) {
      _log.severe('appendSource 失败: $e', e, st);
      if (e is IdeaServiceException) rethrow;
      throw IdeaServiceException('追加来源失败', cause: e);
    }
  }

  Future<List<Map<String, dynamic>>> searchIdeas(
    String query, {
    bool includeArchived = false,
  }) {
    return repository.searchIdeas(query, includeArchived: includeArchived);
  }

  Future<String> ideasFilePath() => repository.getIdeasFilePath();

  Future<String> attachmentDirectoryPath(String ideaId) {
    return repository.getAttachmentDirectoryPath(ideaId);
  }

  String _newIdeaId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = Random().nextInt(0xFFFFFF).toRadixString(36).padLeft(4, '0');
    return 'idea_$t$r';
  }
}
