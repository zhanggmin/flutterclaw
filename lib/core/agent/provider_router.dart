/// Abstract router for LLM provider selection with failover support.
library;

import 'package:flutterclaw/core/providers/anthropic_provider.dart';
import 'package:flutterclaw/core/providers/bedrock_provider.dart';
import 'package:flutterclaw/core/providers/openai_provider.dart';
import 'package:flutterclaw/core/providers/provider_interface.dart';
import 'package:flutterclaw/data/models/config.dart';
import 'package:logging/logging.dart';

final _log = Logger('flutterclaw.provider_router');

abstract class ProviderRouter {
  Future<LlmResponse> chatCompletion(LlmRequest request);
  Stream<LlmStreamEvent> chatCompletionStream(LlmRequest request);
}

class SimpleProviderRouter implements ProviderRouter {
  final LlmProvider provider;

  SimpleProviderRouter(this.provider);

  @override
  Future<LlmResponse> chatCompletion(LlmRequest request) =>
      provider.chatCompletion(request);

  @override
  Stream<LlmStreamEvent> chatCompletionStream(LlmRequest request) =>
      provider.chatCompletionStream(request);
}

/// Selects the correct [LlmProvider] implementation based on the request's
/// API base URL. Anthropic uses a different API format from all other
/// OpenAI-compatible providers (different endpoint, auth header, body).
LlmProvider _resolveProvider(LlmRequest request) {
  final base = request.apiBase.toLowerCase();
  if (base.contains('anthropic.com')) {
    return AnthropicProvider();
  }
  if (base.contains('bedrock-runtime')) {
    return BedrockProvider();
  }
  return OpenAiProvider();
}

/// Provider router with automatic failover to fallback models.
class FailoverProviderRouter implements ProviderRouter {
  final LlmProvider primary;
  final List<LlmProvider> fallbacks;
  final ConfigManager configManager;

  FailoverProviderRouter({
    required this.primary,
    this.fallbacks = const [],
    required this.configManager,
  });

  @override
  Future<LlmResponse> chatCompletion(LlmRequest request) async {
    try {
      return await _resolveProvider(request).chatCompletion(request);
    } catch (e) {
      _log.warning('Primary model failed: $e, trying fallbacks...');
      return _tryFallbacks(request, e);
    }
  }

  @override
  Stream<LlmStreamEvent> chatCompletionStream(LlmRequest request) {
    return _resolveProvider(request).chatCompletionStream(request);
  }

  Future<LlmResponse> _tryFallbacks(LlmRequest request, Object primaryError) async {
    final config = configManager.config;
    final models = config.modelList;
    if (models.length <= 1) throw primaryError;

    for (var i = 1; i < models.length; i++) {
      final fallbackModel = models[i];
      _log.info('Trying fallback model: ${fallbackModel.modelName}');

      try {
        final fallbackRequest = request.copyWith(
          model: fallbackModel.model,
          apiKey: config.resolveApiKey(fallbackModel),
          apiBase: config.resolveApiBase(fallbackModel),
        );

        return await _resolveProvider(fallbackRequest).chatCompletion(fallbackRequest);
      } catch (e) {
        _log.warning('Fallback ${fallbackModel.modelName} also failed: $e');
      }
    }

    throw primaryError;
  }
}
