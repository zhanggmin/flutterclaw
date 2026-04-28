library;

import 'dart:convert';
import 'dart:io';

import 'package:flutterclaw/data/models/config.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

final _log = Logger('flutterclaw.idea_service');
const _uuid = Uuid();

enum IdeaSourceType { chatMessage, chatSummary }

class IdeaItem {
  final String id;
  String title;
  String body;
  String summary;
  List<String> tags;
  List<String> nextActions;
  DateTime createdAt;
  DateTime updatedAt;

  IdeaItem({
    String? id,
    required this.title,
    required this.body,
    this.summary = '',
    this.tags = const [],
    this.nextActions = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        if (summary.isNotEmpty) 'summary': summary,
        if (tags.isNotEmpty) 'tags': tags,
        if (nextActions.isNotEmpty) 'nextActions': nextActions,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory IdeaItem.fromJson(Map<String, dynamic> json) => IdeaItem(
        id: json['id'] as String?,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
        nextActions:
            (json['nextActions'] as List<dynamic>? ?? []).cast<String>(),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
      );
}

typedef IdeaLlmCall = Future<String?> Function(String systemPrompt, String userPrompt);

class IdeaService {
  final ConfigManager configManager;
  final IdeaLlmCall? llmCall;
  final List<IdeaItem> _items = [];
  bool _loaded = false;

  IdeaService({required this.configManager, this.llmCall});

  List<IdeaItem> get items => List.unmodifiable(_items);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _ideasFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(
          decoded.map((e) => IdeaItem.fromJson(e as Map<String, dynamic>)),
        );
      _items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      _log.warning('Failed to load ideas: $e');
    }
  }

  Future<IdeaItem> saveFromChat({
    required String content,
    required IdeaSourceType sourceType,
    required String sourceRef,
    bool append = false,
    String? existingIdeaId,
    bool organizeWithAi = false,
  }) async {
    await load();
    final now = DateTime.now();
    final sourceLabel = sourceType == IdeaSourceType.chatMessage ? 'chat_message' : 'chat_summary';
    final normalizedContent = content.trim();
    final section = '[来源] $sourceLabel\n[sourceRef] $sourceRef\n\n$normalizedContent';

    if (append && existingIdeaId != null) {
      final target = _items.where((i) => i.id == existingIdeaId).firstOrNull;
      if (target != null) {
        target.body = '${target.body.trim()}\n\n---\n\n$section';
        target.updatedAt = now;
        if (organizeWithAi) {
          await _organizeInto(target);
          target.updatedAt = DateTime.now();
        }
        await _save();
        return target;
      }
    }

    final item = IdeaItem(
      title: _defaultTitle(normalizedContent, sourceType),
      body: section,
      createdAt: now,
      updatedAt: now,
    );
    if (organizeWithAi) {
      await _organizeInto(item);
      item.updatedAt = DateTime.now();
    }
    _items.insert(0, item);
    await _save();
    return item;
  }

  String _defaultTitle(String content, IdeaSourceType type) {
    final prefix = type == IdeaSourceType.chatMessage ? '聊天灵感' : '会话总结';
    final firstLine = content.split('\n').first.trim();
    if (firstLine.isEmpty) return prefix;
    return '$prefix - ${firstLine.length > 24 ? '${firstLine.substring(0, 24)}…' : firstLine}';
  }

  Future<void> _organizeInto(IdeaItem item) async {
    final call = llmCall;
    if (call == null) return;
    try {
      final result = await call(
        '你是知识整理助手。请把输入内容整理为 JSON，字段: title(string), summary(string), tags(string[]), nextActions(string[])。仅返回 JSON。',
        item.body,
      );
      if (result == null || result.trim().isEmpty) return;
      final start = result.indexOf('{');
      final end = result.lastIndexOf('}');
      if (start < 0 || end <= start) return;
      final obj = jsonDecode(result.substring(start, end + 1)) as Map<String, dynamic>;
      item.title = (obj['title'] as String?)?.trim().isNotEmpty == true
          ? (obj['title'] as String).trim()
          : item.title;
      item.summary = (obj['summary'] as String?)?.trim() ?? item.summary;
      item.tags = (obj['tags'] as List<dynamic>? ?? []).map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
      item.nextActions = (obj['nextActions'] as List<dynamic>? ?? [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      _log.warning('AI organize failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final file = await _ideasFile();
      await file.parent.create(recursive: true);
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_items.map((e) => e.toJson()).toList()));
    } catch (e) {
      _log.warning('Failed to save ideas: $e');
    }
  }

  Future<File> _ideasFile() async {
    final ws = await configManager.workspacePath;
    return File('$ws/ideas/items.json');
  }
}
