library;

import 'ai_insights.dart';
import 'next_action.dart';

enum IdeaStatus { inbox, incubating, developing, archived }

extension IdeaStatusJson on IdeaStatus {
  static IdeaStatus fromJsonValue(String? value) {
    switch (value) {
      case 'incubating':
        return IdeaStatus.incubating;
      case 'developing':
        return IdeaStatus.developing;
      case 'archived':
        return IdeaStatus.archived;
      case 'inbox':
      default:
        return IdeaStatus.inbox;
    }
  }

  String toJsonValue() {
    switch (this) {
      case IdeaStatus.inbox:
        return 'inbox';
      case IdeaStatus.incubating:
        return 'incubating';
      case IdeaStatus.developing:
        return 'developing';
      case IdeaStatus.archived:
        return 'archived';
    }
  }
}

enum IdeaSourceType { manual, chatMessage, chatSummary, voice, image, link }

extension IdeaSourceTypeJson on IdeaSourceType {
  static IdeaSourceType fromJsonValue(String? value) {
    switch (value) {
      case 'chat_message':
        return IdeaSourceType.chatMessage;
      case 'chat_summary':
        return IdeaSourceType.chatSummary;
      case 'voice':
        return IdeaSourceType.voice;
      case 'image':
        return IdeaSourceType.image;
      case 'link':
        return IdeaSourceType.link;
      case 'manual':
      default:
        return IdeaSourceType.manual;
    }
  }

  String toJsonValue() {
    switch (this) {
      case IdeaSourceType.manual:
        return 'manual';
      case IdeaSourceType.chatMessage:
        return 'chat_message';
      case IdeaSourceType.chatSummary:
        return 'chat_summary';
      case IdeaSourceType.voice:
        return 'voice';
      case IdeaSourceType.image:
        return 'image';
      case IdeaSourceType.link:
        return 'link';
    }
  }
}

class Idea {
  final String id;
  final String title;
  final String content;
  final String summary;
  final List<String> tags;
  final IdeaStatus status;
  final IdeaSourceType sourceType;
  final String sourceRef;
  final List<String> linkedSessionKeys;
  final List<NextAction> nextActions;
  final AiInsights? aiInsights;
  final int priority;
  final DateTime? lastBrainstormedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  const Idea({
    required this.id,
    required this.title,
    this.content = '',
    this.summary = '',
    this.tags = const [],
    this.status = IdeaStatus.inbox,
    this.sourceType = IdeaSourceType.manual,
    this.sourceRef = '',
    this.linkedSessionKeys = const [],
    this.nextActions = const [],
    this.aiInsights,
    this.priority = 0,
    this.lastBrainstormedAt,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  factory Idea.fromJson(Map<String, dynamic> json) => Idea(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        status: IdeaStatusJson.fromJsonValue(json['status'] as String?),
        sourceType:
            IdeaSourceTypeJson.fromJsonValue(json['source_type'] as String?),
        sourceRef: json['source_ref'] as String? ?? '',
        linkedSessionKeys:
            (json['linked_session_keys'] as List<dynamic>? ?? const [])
                .map((e) => e.toString())
                .toList(),
        nextActions: (json['next_actions'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NextAction.fromJson)
            .toList(),
        aiInsights: json['ai_insights'] is Map<String, dynamic>
            ? AiInsights.fromJson(json['ai_insights'] as Map<String, dynamic>)
            : null,
        priority: json['priority'] as int? ?? 0,
        lastBrainstormedAt: json['last_brainstormed_at'] != null
            ? DateTime.parse(json['last_brainstormed_at'] as String)
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : DateTime.now(),
        archivedAt: json['archived_at'] != null
            ? DateTime.parse(json['archived_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (content.isNotEmpty) 'content': content,
        if (summary.isNotEmpty) 'summary': summary,
        'tags': tags,
        'status': status.toJsonValue(),
        'source_type': sourceType.toJsonValue(),
        if (sourceRef.isNotEmpty) 'source_ref': sourceRef,
        'linked_session_keys': linkedSessionKeys,
        'next_actions': nextActions.map((e) => e.toJson()).toList(),
        if (aiInsights != null) 'ai_insights': aiInsights!.toJson(),
        'priority': priority,
        if (lastBrainstormedAt != null)
          'last_brainstormed_at': lastBrainstormedAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (archivedAt != null) 'archived_at': archivedAt!.toIso8601String(),
      };

  Idea copyWith({
    String? id,
    String? title,
    String? content,
    String? summary,
    List<String>? tags,
    IdeaStatus? status,
    IdeaSourceType? sourceType,
    String? sourceRef,
    List<String>? linkedSessionKeys,
    List<NextAction>? nextActions,
    AiInsights? aiInsights,
    bool clearAiInsights = false,
    int? priority,
    DateTime? lastBrainstormedAt,
    bool clearLastBrainstormedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) =>
      Idea(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        summary: summary ?? this.summary,
        tags: tags ?? this.tags,
        status: status ?? this.status,
        sourceType: sourceType ?? this.sourceType,
        sourceRef: sourceRef ?? this.sourceRef,
        linkedSessionKeys: linkedSessionKeys ?? this.linkedSessionKeys,
        nextActions: nextActions ?? this.nextActions,
        aiInsights: clearAiInsights ? null : (aiInsights ?? this.aiInsights),
        priority: priority ?? this.priority,
        lastBrainstormedAt: clearLastBrainstormedAt
            ? null
            : (lastBrainstormedAt ?? this.lastBrainstormedAt),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      );

  /// ideas.json 顶层结构建议：直接使用 `List<Map<String, dynamic>>`（JSON 数组）。
  static List<Idea> listFromJson(dynamic raw) {
    final list = raw is List<dynamic> ? raw : const <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Idea.fromJson)
        .toList();
  }

  static List<Map<String, dynamic>> listToJson(List<Idea> ideas) =>
      ideas.map((idea) => idea.toJson()).toList();
}
