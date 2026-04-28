library;

enum IdeaStatus { inbox, incubating, developing, archived }

enum IdeaSortField { updatedAt, lastBrainstormedAt, priority }

enum SortDirection { asc, desc }

class IdeaSortOption {
  const IdeaSortOption({
    this.field = IdeaSortField.updatedAt,
    this.direction = SortDirection.desc,
  });

  final IdeaSortField field;
  final SortDirection direction;
}

class IdeaItem {
  const IdeaItem({
    required this.id,
    required this.title,
    this.description = '',
    this.status = IdeaStatus.inbox,
    this.tags = const <String>[],
    required this.createdAt,
    required this.updatedAt,
    this.lastBrainstormedAt,
    this.priority,
    this.sourceType = 'manual',
  });

  final String id;
  final String title;
  final String description;
  final IdeaStatus status;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastBrainstormedAt;
  final int? priority;
  final String sourceType;

  IdeaItem copyWith({
    String? title,
    String? description,
    IdeaStatus? status,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastBrainstormedAt,
    int? priority,
    String? sourceType,
  }) {
    return IdeaItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastBrainstormedAt: lastBrainstormedAt ?? this.lastBrainstormedAt,
      priority: priority ?? this.priority,
      sourceType: sourceType ?? this.sourceType,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
        'tags': tags,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (lastBrainstormedAt != null)
          'last_brainstormed_at': lastBrainstormedAt!.toIso8601String(),
        if (priority != null) 'priority': priority,
        'source_type': sourceType,
      };

  factory IdeaItem.fromJson(Map<String, dynamic> json) {
    return IdeaItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: IdeaStatus.values.firstWhere(
        (value) => value.name == (json['status'] as String? ?? 'inbox'),
        orElse: () => IdeaStatus.inbox,
      ),
      tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(growable: false),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastBrainstormedAt: json['last_brainstormed_at'] == null
          ? null
          : DateTime.parse(json['last_brainstormed_at'] as String),
      priority: json['priority'] as int?,
      sourceType: json['source_type'] as String? ?? 'manual',
    );
  }
}
