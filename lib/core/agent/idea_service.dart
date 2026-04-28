import 'dart:convert';

import '../providers/provider_interface.dart';
import '../providers/provider_router.dart';
import 'idea_prompts.dart';

class IdeaService {
  IdeaService({
    required ProviderRouter providerRouter,
    required String modelName,
  }) : _providerRouter = providerRouter,
       _modelName = modelName;

  final ProviderRouter _providerRouter;
  final String _modelName;

  Future<String> generateTitle(String ideaText) async {
    final content = await _complete(IdeaPrompts.generateTitle(ideaText));
    return _readString(content, key: 'title', fallback: _firstSentence(ideaText));
  }

  Future<String> generateSummary(String ideaText) async {
    final content = await _complete(IdeaPrompts.generateSummary(ideaText));
    return _readString(content, key: 'summary', fallback: content.trim());
  }

  Future<List<String>> recommendTags(String ideaText) async {
    final content = await _complete(IdeaPrompts.recommendTags(ideaText));
    final decoded = _tryDecode(content);

    final parsed = switch (decoded) {
      {'tags': final List<dynamic> tags} => _normalizeStringList(tags),
      {'tags': final dynamic tags} => _splitText(tags?.toString() ?? content),
      final List<dynamic> tags => _normalizeStringList(tags),
      _ => _splitText(content),
    };

    return parsed.take(6).toList();
  }

  Future<List<String>> extractNextActions(String ideaText) async {
    final content = await _complete(IdeaPrompts.extractNextActions(ideaText));
    final decoded = _tryDecode(content);

    final parsed = switch (decoded) {
      {'next_actions': final List<dynamic> actions} => _normalizeStringList(actions),
      {'next_actions': final dynamic actions} => _splitText(actions?.toString() ?? content),
      final List<dynamic> actions => _normalizeStringList(actions),
      _ => _splitText(content),
    };

    final clamped = parsed.where((e) => e.isNotEmpty).take(3).toList();
    if (clamped.isNotEmpty) return clamped;
    return ['明确目标用户并定义最小可行版本（MVP）'];
  }

  Future<String> brainstormIdea(String ideaText) async {
    final content = await _complete(IdeaPrompts.brainstormIdea(ideaText));
    return _readString(content, key: 'brainstorm', fallback: content.trim());
  }

  Future<String> _complete(String prompt) async {
    final response = await _providerRouter.chatCompletion(
      _modelName,
      messages: [
        const LlmMessage(
          role: 'system',
          content: 'You are a precise idea refinement assistant. Always prefer valid JSON output.',
        ),
        LlmMessage(role: 'user', content: prompt),
      ],
      temperature: 0.3,
      maxTokens: 600,
    );

    return response?.content?.trim() ?? '';
  }

  dynamic _tryDecode(String content) {
    try {
      return jsonDecode(content);
    } catch (_) {
      final match = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(content);
      if (match == null) return null;
      try {
        return jsonDecode(match.group(1)!);
      } catch (_) {
        return null;
      }
    }
  }

  String _readString(String content, {required String key, required String fallback}) {
    final decoded = _tryDecode(content);
    if (decoded is Map<String, dynamic>) {
      final value = decoded[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback.trim();
  }

  List<String> _normalizeStringList(List<dynamic> values) {
    return values
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _splitText(String text) {
    return text
        .split(RegExp(r'[\n,，、;；|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _firstSentence(String text) {
    final sentence = text.split(RegExp(r'[。.!?\n]')).first.trim();
    if (sentence.isEmpty) return '新想法';
    return sentence.length <= 20 ? sentence : sentence.substring(0, 20);
  }
}
