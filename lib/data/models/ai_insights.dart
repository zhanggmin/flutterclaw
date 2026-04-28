library;

class AiInsights {
  final String summary;
  final List<String> suggestedTags;
  final List<String> keyQuestions;
  final List<String> opportunities;
  final List<String> risks;
  final DateTime? generatedAt;

  const AiInsights({
    this.summary = '',
    this.suggestedTags = const [],
    this.keyQuestions = const [],
    this.opportunities = const [],
    this.risks = const [],
    this.generatedAt,
  });

  factory AiInsights.fromJson(Map<String, dynamic> json) => AiInsights(
        summary: json['summary'] as String? ?? '',
        suggestedTags: (json['suggested_tags'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        keyQuestions: (json['key_questions'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        opportunities: (json['opportunities'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        risks: (json['risks'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        generatedAt: json['generated_at'] != null
            ? DateTime.parse(json['generated_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (summary.isNotEmpty) 'summary': summary,
        if (suggestedTags.isNotEmpty) 'suggested_tags': suggestedTags,
        if (keyQuestions.isNotEmpty) 'key_questions': keyQuestions,
        if (opportunities.isNotEmpty) 'opportunities': opportunities,
        if (risks.isNotEmpty) 'risks': risks,
        if (generatedAt != null) 'generated_at': generatedAt!.toIso8601String(),
      };

  AiInsights copyWith({
    String? summary,
    List<String>? suggestedTags,
    List<String>? keyQuestions,
    List<String>? opportunities,
    List<String>? risks,
    DateTime? generatedAt,
    bool clearGeneratedAt = false,
  }) =>
      AiInsights(
        summary: summary ?? this.summary,
        suggestedTags: suggestedTags ?? this.suggestedTags,
        keyQuestions: keyQuestions ?? this.keyQuestions,
        opportunities: opportunities ?? this.opportunities,
        risks: risks ?? this.risks,
        generatedAt: clearGeneratedAt
            ? null
            : (generatedAt ?? this.generatedAt),
      );
}
