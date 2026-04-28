library;

/// Execution status for an idea's follow-up action.
enum NextActionStatus { pending, inProgress, done, canceled }

extension NextActionStatusJson on NextActionStatus {
  static NextActionStatus fromJsonValue(String? value) {
    switch (value) {
      case 'in_progress':
        return NextActionStatus.inProgress;
      case 'done':
        return NextActionStatus.done;
      case 'canceled':
        return NextActionStatus.canceled;
      case 'pending':
      default:
        return NextActionStatus.pending;
    }
  }

  String toJsonValue() {
    switch (this) {
      case NextActionStatus.pending:
        return 'pending';
      case NextActionStatus.inProgress:
        return 'in_progress';
      case NextActionStatus.done:
        return 'done';
      case NextActionStatus.canceled:
        return 'canceled';
    }
  }
}

class NextAction {
  final String id;
  final String title;
  final String notes;
  final NextActionStatus status;
  final DateTime? dueAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const NextAction({
    required this.id,
    required this.title,
    this.notes = '',
    this.status = NextActionStatus.pending,
    this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  factory NextAction.fromJson(Map<String, dynamic> json) => NextAction(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        status: NextActionStatusJson.fromJsonValue(json['status'] as String?),
        dueAt: json['due_at'] != null
            ? DateTime.parse(json['due_at'] as String)
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : DateTime.now(),
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (notes.isNotEmpty) 'notes': notes,
        'status': status.toJsonValue(),
        if (dueAt != null) 'due_at': dueAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      };

  NextAction copyWith({
    String? id,
    String? title,
    String? notes,
    NextActionStatus? status,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) =>
      NextAction(
        id: id ?? this.id,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      );
}
