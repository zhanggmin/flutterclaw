import 'dart:convert';
import 'dart:io';

import 'package:flutterclaw/core/agent/session_manager.dart';
import 'package:flutterclaw/core/providers/provider_interface.dart';
import 'package:flutterclaw/data/models/config.dart';

class IdeaRecord {
  final String id;
  final String title;
  final String content;
  final String summary;
  final List<String> tags;
  final String status;
  final List<String> nextActions;
  final List<String> lastInsights;
  final List<String> linkedSessionKeys;
  final DateTime? lastBrainstormedAt;
  final DateTime updatedAt;

  const IdeaRecord({
    required this.id,
    required this.title,
    required this.content,
    this.summary = '',
    this.tags = const [],
    this.status = 'draft',
    this.nextActions = const [],
    this.lastInsights = const [],
    this.linkedSessionKeys = const [],
    this.lastBrainstormedAt,
    required this.updatedAt,
  });

  IdeaRecord copyWith({
    String? title,
    String? content,
    String? summary,
    List<String>? tags,
    String? status,
    List<String>? nextActions,
    List<String>? lastInsights,
    List<String>? linkedSessionKeys,
    DateTime? lastBrainstormedAt,
    bool clearLastBrainstormedAt = false,
    DateTime? updatedAt,
  }) {
    return IdeaRecord(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      nextActions: nextActions ?? this.nextActions,
      lastInsights: lastInsights ?? this.lastInsights,
      linkedSessionKeys: linkedSessionKeys ?? this.linkedSessionKeys,
      lastBrainstormedAt: clearLastBrainstormedAt
          ? null
          : lastBrainstormedAt ?? this.lastBrainstormedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'summary': summary,
        'tags': tags,
        'status': status,
        'nextActions': nextActions,
        'lastInsights': lastInsights,
        'linkedSessionKeys': linkedSessionKeys,
        if (lastBrainstormedAt != null)
          'lastBrainstormedAt': lastBrainstormedAt!.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory IdeaRecord.fromJson(Map<String, dynamic> json) {
    return IdeaRecord(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      status: (json['status'] as String?) ?? 'draft',
      nextActions: (json['nextActions'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      lastInsights: (json['lastInsights'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      linkedSessionKeys:
          (json['linkedSessionKeys'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
      lastBrainstormedAt: json['lastBrainstormedAt'] == null
          ? null
          : DateTime.tryParse(json['lastBrainstormedAt'] as String),
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class BrainstormSessionResult {
  final String sessionKey;
  final bool createdNew;

  const BrainstormSessionResult({
    required this.sessionKey,
    required this.createdNew,
  });
}

class IdeaService {
  final ConfigManager _configManager;
  final SessionManager _sessionManager;

  const IdeaService(this._configManager, this._sessionManager);

  static String sessionKeyForIdea(String ideaId) => 'ideas:$ideaId';

  Future<BrainstormSessionResult> startOrResumeBrainstorm(String ideaId) async {
    final ideas = await _loadIdeas();
    final idea = ideas[ideaId];
    if (idea == null) {
      throw StateError('Idea not found: $ideaId');
    }

    final now = DateTime.now();
    final recentKey = _pickMostRecentLinkedSession(idea.linkedSessionKeys);
    if (recentKey != null) {
      return BrainstormSessionResult(sessionKey: recentKey, createdNew: false);
    }

    final sessionKey = '${sessionKeyForIdea(ideaId)}:${now.millisecondsSinceEpoch}';
    await _sessionManager.getOrCreate(sessionKey, 'webchat', 'idea:$ideaId');

    final injectedContext = _buildInitialIdeaContextMessage(idea);
    await _sessionManager.addMessage(
      sessionKey,
      LlmMessage(role: 'user', content: injectedContext),
    );

    final mergedKeys = [
      ...idea.linkedSessionKeys.where((k) => k.isNotEmpty),
      sessionKey,
    ];
    ideas[ideaId] = idea.copyWith(
      linkedSessionKeys: mergedKeys,
      updatedAt: now,
    );
    await _saveIdeas(ideas);

    return BrainstormSessionResult(sessionKey: sessionKey, createdNew: true);
  }

  Future<void> markBrainstormSucceeded(String ideaId) async {
    final ideas = await _loadIdeas();
    final idea = ideas[ideaId];
    if (idea == null) return;

    final now = DateTime.now();
    ideas[ideaId] = idea.copyWith(
      lastBrainstormedAt: now,
      updatedAt: now,
    );
    await _saveIdeas(ideas);
  }

  Future<void> upsertIdea(IdeaRecord idea) async {
    final ideas = await _loadIdeas();
    ideas[idea.id] = idea.copyWith(updatedAt: DateTime.now());
    await _saveIdeas(ideas);
  }

  String? _pickMostRecentLinkedSession(List<String> keys) {
    SessionMeta? best;
    for (final key in keys) {
      final meta = _sessionManager.getMeta(key);
      if (meta == null) continue;
      if (best == null || meta.lastActivity.isAfter(best.lastActivity)) {
        best = meta;
      }
    }
    return best?.key;
  }

  String _buildInitialIdeaContextMessage(IdeaRecord idea) {
    final tags = idea.tags.isEmpty ? '无' : idea.tags.join(' / ');
    final nextActions =
        idea.nextActions.isEmpty ? '- 无' : idea.nextActions.map((e) => '- $e').join('\n');
    final insights =
        idea.lastInsights.isEmpty ? '- 无' : idea.lastInsights.map((e) => '- $e').join('\n');

    return '''
请基于以下 Idea 继续发散，并给出结构化建议：

- ideaId: ${idea.id}
- title: ${idea.title}
- content: ${idea.content}
- summary: ${idea.summary.isEmpty ? '无' : idea.summary}
- tags: $tags
- status: ${idea.status}

nextActions:
$nextActions

last insights:
$insights
''';
  }

  Future<Map<String, IdeaRecord>> _loadIdeas() async {
    final file = await _ideasStoreFile();
    if (!await file.exists()) return {};

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return {};

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return {};

    final records = <String, IdeaRecord>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        records[entry.key] = IdeaRecord.fromJson(value);
      }
    }
    return records;
  }

  Future<void> _saveIdeas(Map<String, IdeaRecord> ideas) async {
    final file = await _ideasStoreFile();
    await file.parent.create(recursive: true);
    final payload = ideas.map((k, v) => MapEntry(k, v.toJson()));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  Future<File> _ideasStoreFile() async {
    final workspace = await _configManager.workspacePath;
    return File('$workspace/state/ideas.json');
  }
}
