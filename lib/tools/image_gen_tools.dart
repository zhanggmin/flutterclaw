/// Image generation tool via the OpenAI-compatible images/generations endpoint.
///
/// Works with any provider that supports the DALL-E / OpenAI image API:
/// OpenAI (DALL-E 3), Together AI, etc.
///
/// Returns the generated image URL so the LLM can embed it as markdown
/// `![description](url)` which MarkdownBody renders inline in the chat.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutterclaw/data/models/config.dart';
import 'package:flutterclaw/tools/registry.dart';

class ImageGenTool extends Tool {
  final ConfigManager configManager;

  ImageGenTool({required this.configManager});

  @override
  String get name => 'image_generate';

  @override
  String get description =>
      'Generate an image from a text prompt using DALL-E or a compatible model. '
      'Returns the image URL — embed it in your response as markdown ![alt](url) '
      'so the user can see it inline.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'prompt': {
            'type': 'string',
            'description': 'Detailed description of the image to generate.',
          },
          'size': {
            'type': 'string',
            'enum': ['1024x1024', '1024x1792', '1792x1024', '512x512'],
            'description': 'Image dimensions. Default: 1024x1024.',
          },
          'quality': {
            'type': 'string',
            'enum': ['standard', 'hd'],
            'description': 'Image quality. hd takes longer. Default: standard.',
          },
          'model': {
            'type': 'string',
            'description': 'Model override. Default: dall-e-3.',
          },
        },
        'required': ['prompt'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final prompt = args['prompt'] as String? ?? '';
    final size = args['size'] as String? ?? '1024x1024';
    final quality = args['quality'] as String? ?? 'standard';
    final model = args['model'] as String? ?? 'dall-e-3';

    if (prompt.trim().isEmpty) {
      return ToolResult.error('prompt is required');
    }

    final config = configManager.config;
    final modelName =
        config.activeAgent?.modelName ?? config.agents.defaults.modelName;
    final entry = config.getModel(modelName);

    String apiKey = '';
    String apiBase = 'https://api.openai.com/v1';

    if (entry != null) {
      apiKey = config.resolveApiKey(entry);
      final base = config.resolveApiBase(entry);
      if (!base.contains('anthropic.com')) apiBase = base;
    }

    if (apiKey.isEmpty) {
      return ToolResult.error(
          'No API key configured. Set up an OpenAI (or compatible) provider.');
    }

    try {
      final normalised = apiBase.endsWith('/') ? apiBase : '$apiBase/';
      final dio = Dio(BaseOptions(
        baseUrl: normalised,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
      ));

      final response = await dio.post('/images/generations', data: {
        'prompt': prompt,
        'model': model,
        'n': 1,
        'size': size,
        'quality': quality,
        'response_format': 'url',
      });

      if ((response.statusCode ?? 0) >= 400) {
        String msg = 'HTTP ${response.statusCode}';
        if (response.data is Map) {
          final err = (response.data as Map)['error'];
          if (err is Map && err['message'] != null) msg = '${err['message']}';
        }
        return ToolResult.error('Image generation failed: $msg');
      }

      final data = response.data?['data'] as List?;
      final url = data?.isNotEmpty == true ? data![0]['url'] as String? : null;

      if (url == null || url.isEmpty) {
        return ToolResult.error('API returned no image URL');
      }

      return ToolResult.success(
        jsonEncode({'url': url, 'prompt': prompt}),
      );
    } on DioException catch (e) {
      return ToolResult.error('Image generation failed: ${e.message}');
    } catch (e) {
      return ToolResult.error('Image generation error: $e');
    }
  }
}
