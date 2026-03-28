/// PDF analysis tool for FlutterClaw.
///
/// Mirrors OpenClaw's pdf-tool.ts with three analysis paths:
///   1. Anthropic native  — sends base64 PDF as a document block (most accurate).
///   2. Google/Gemini native — sends base64 PDF as inline_data.
///   3. Extraction fallback — renders pages to JPEG images for any vision model.
///
/// Limits: 10 PDFs max, 10 MB each, 20 pages max.
library;

import 'package:dio/dio.dart';
import 'package:flutterclaw/data/models/config.dart';
import 'package:flutterclaw/services/pdf_service.dart';
import 'package:flutterclaw/services/ssrf_guard.dart';
import 'package:logging/logging.dart';

import 'registry.dart';

final _log = Logger('flutterclaw.pdf_tool');

class PdfTool extends Tool {
  final ConfigManager configManager;
  final PdfService _pdfService = PdfService();

  PdfTool({required this.configManager});

  @override
  String get name => 'pdf';

  @override
  String get description =>
      'Analyze one or more PDF documents. '
      'Supports native PDF analysis for Anthropic and Google models, '
      'with page-image extraction fallback for other providers. '
      'Use "pdf" for a single path/URL, or "pdfs" for multiple (up to 10). '
      'Optionally specify "pages" (e.g. "1-5" or "1,3,5-7") to limit which pages are processed. '
      'Provide a "prompt" describing what to analyze.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'pdf': {
            'type': 'string',
            'description': 'Single PDF file path or URL.',
          },
          'pdfs': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Multiple PDF file paths or URLs (up to 10).',
          },
          'prompt': {
            'type': 'string',
            'description': 'What to analyze or extract from the PDF(s). '
                'Defaults to "Analyze this PDF document."',
          },
          'pages': {
            'type': 'string',
            'description':
                'Page range to process, e.g. "1-5" or "1,3,5-7". '
                'Defaults to all pages (up to 20).',
          },
          'model': {
            'type': 'string',
            'description': 'Override the model used for PDF analysis.',
          },
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    // ── Collect PDF sources ──────────────────────────────────────────────────
    final sources = <String>[];
    final single = args['pdf'] as String?;
    if (single != null && single.trim().isNotEmpty) sources.add(single.trim());

    final multi = args['pdfs'];
    if (multi is List) {
      for (final v in multi) {
        final s = (v as String?)?.trim();
        if (s != null && s.isNotEmpty && !sources.contains(s)) sources.add(s);
      }
    }

    if (sources.isEmpty) return ToolResult.error('pdf is required: provide a file path or URL.');
    if (sources.length > PdfService.maxPdfs) {
      return ToolResult.error(
        'Too many PDFs: ${sources.length} provided, maximum is ${PdfService.maxPdfs}.',
      );
    }

    // Validate URLs for SSRF
    for (final src in sources) {
      if (src.startsWith('http://') || src.startsWith('https://')) {
        final err = validateFetchUrl(src);
        if (err != null) return ToolResult.error(err);
      }
    }

    final prompt = (args['prompt'] as String?)?.trim().isNotEmpty == true
        ? args['prompt'] as String
        : 'Analyze this PDF document.';
    final pagesStr = args['pages'] as String?;
    final pageRange = (pagesStr != null && pagesStr.trim().isNotEmpty)
        ? parsePdfPageRange(pagesStr.trim())
        : null;

    // ── Load PDFs ────────────────────────────────────────────────────────────
    final loaded = <PdfLoadResult>[];
    for (final src in sources) {
      final result = await _pdfService.loadPdf(src);
      if (result == null) {
        return ToolResult.error('Failed to load PDF: $src');
      }
      loaded.add(result);
    }

    // ── Determine provider ────────────────────────────────────────────────────
    final modelOverride = (args['model'] as String?)?.trim();
    final modelName = (modelOverride?.isNotEmpty == true)
        ? modelOverride!
        : configManager.config.agents.defaults.modelName;

    final model = configManager.config.getModel(modelName);
    final provider = model?.vendor ?? _inferProvider(modelName);

    _log.info(
      'PDF analysis: ${loaded.length} file(s), provider=$provider, '
      'model=$modelName, pages=$pageRange',
    );

    // ── Analysis paths ────────────────────────────────────────────────────────
    try {
      if (PdfService.supportsNativePdf(provider)) {
        return await _analyzeNative(
          provider: provider,
          model: model,
          modelName: modelName,
          loaded: loaded,
          prompt: prompt,
        );
      }
      return await _analyzeWithExtraction(
        model: model,
        modelName: modelName,
        loaded: loaded,
        prompt: prompt,
        pageRange: pageRange,
      );
    } catch (e) {
      _log.warning('PDF analysis failed: $e');
      return ToolResult.error('PDF analysis failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Path 1 & 2: native provider analysis
  // ---------------------------------------------------------------------------

  Future<ToolResult> _analyzeNative({
    required String provider,
    required ModelEntry? model,
    required String modelName,
    required List<PdfLoadResult> loaded,
    required String prompt,
  }) async {
    final credential = _resolveCredential(provider);
    if (credential == null) {
      // Fall back to extraction
      return _analyzeWithExtraction(
        model: model,
        modelName: modelName,
        loaded: loaded,
        prompt: prompt,
        pageRange: null,
      );
    }

    final apiBase = credential.apiBase ??
        (provider == 'anthropic'
            ? 'https://api.anthropic.com'
            : 'https://generativelanguage.googleapis.com');
    final apiKey = credential.apiKey;

    if (provider == 'anthropic') {
      return await _callAnthropic(
        apiKey: apiKey,
        apiBase: apiBase,
        modelId: model?.modelId ?? 'claude-opus-4-6',
        loaded: loaded,
        prompt: prompt,
      );
    }

    // Google/Gemini
    return await _callGemini(
      apiKey: apiKey,
      apiBase: apiBase,
      modelId: model?.modelId ?? 'gemini-2.0-flash',
      loaded: loaded,
      prompt: prompt,
    );
  }

  Future<ToolResult> _callAnthropic({
    required String apiKey,
    required String apiBase,
    required String modelId,
    required List<PdfLoadResult> loaded,
    required String prompt,
  }) async {
    final dio = Dio();
    final content = PdfService.buildAnthropicPdfBlocks(loaded, prompt);
    final response = await dio.post<Map<String, dynamic>>(
      '$apiBase/v1/messages',
      data: {
        'model': modelId,
        'max_tokens': 4096,
        'messages': [
          {'role': 'user', 'content': content},
        ],
      },
      options: Options(
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'anthropic-beta': 'pdfs-2024-09-25',
          'content-type': 'application/json',
        },
        validateStatus: (s) => s != null && s < 500,
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Anthropic API error ${response.statusCode}: ${response.data}');
    }
    final text = _extractAnthropicText(response.data!);
    return ToolResult.success('[Analyzed via Anthropic native PDF]\n\n$text');
  }

  Future<ToolResult> _callGemini({
    required String apiKey,
    required String apiBase,
    required String modelId,
    required List<PdfLoadResult> loaded,
    required String prompt,
  }) async {
    final dio = Dio();
    final parts = PdfService.buildGeminiPdfBlocks(loaded, prompt);
    final response = await dio.post<Map<String, dynamic>>(
      '$apiBase/v1beta/models/$modelId:generateContent?key=$apiKey',
      data: {
        'contents': [
          {'parts': parts},
        ],
      },
      options: Options(
        validateStatus: (s) => s != null && s < 500,
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Gemini API error ${response.statusCode}: ${response.data}');
    }
    final text = _extractGeminiText(response.data!);
    return ToolResult.success('[Analyzed via Gemini native PDF]\n\n$text');
  }

  // ---------------------------------------------------------------------------
  // Path 3: extraction fallback (any vision model)
  // ---------------------------------------------------------------------------

  Future<ToolResult> _analyzeWithExtraction({
    required ModelEntry? model,
    required String modelName,
    required List<PdfLoadResult> loaded,
    required String prompt,
    required List<int>? pageRange,
  }) async {
    final extractions = <PdfExtraction>[];
    for (final pdf in loaded) {
      final extraction = await _pdfService.extractContent(pdf, pageRange: pageRange);
      extractions.add(extraction);
    }

    final hasImages = extractions.any((e) => e.pageImages.isNotEmpty);
    final hasText = extractions.any((e) => e.text.isNotEmpty);

    if (!hasImages && !hasText) {
      return ToolResult.error('Could not extract any content from the PDF(s).');
    }

    // If no images, just return the extracted text directly
    if (!hasImages) {
      final combined = extractions.map((e) => e.text).join('\n\n---\n\n');
      return ToolResult.success('[Extracted text from PDF]\n\n$combined');
    }

    // Use the current model's API to analyze the extracted images
    final provider = model?.vendor ?? _inferProvider(modelName);
    final credential = _resolveCredential(provider);
    if (credential == null) {
      // No credential — return plain text if available
      if (hasText) {
        final combined = extractions.map((e) => e.text).join('\n\n---\n\n');
        return ToolResult.success(
          '[PDF text extraction (no vision model available)]\n\n$combined',
        );
      }
      return ToolResult.error(
        'No API credentials found for provider "$provider". '
        'Configure credentials in Settings → Providers to analyze this PDF.',
      );
    }

    final blocks = PdfService.buildExtractionBlocks(extractions, prompt);
    final apiBase = credential.apiBase ?? _defaultApiBase(provider);

    // Send to OpenAI-compatible endpoint (works for OpenAI, OpenRouter, etc.)
    final dio = Dio();
    final contentParts = blocks.map((b) {
      if (b['type'] == 'image') {
        return {
          'type': 'image_url',
          'image_url': {
            'url': 'data:${b['mimeType']};base64,${b['data']}',
          },
        };
      }
      return {'type': 'text', 'text': b['text'] ?? b.toString()};
    }).toList();

    final response = await dio.post<Map<String, dynamic>>(
      '$apiBase/chat/completions',
      data: {
        'model': model?.modelId ?? modelName,
        'max_tokens': 4096,
        'messages': [
          {'role': 'user', 'content': contentParts},
        ],
      },
      options: Options(
        headers: {'Authorization': 'Bearer ${credential.apiKey}'},
        validateStatus: (s) => s != null && s < 500,
        receiveTimeout: const Duration(seconds: 120),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('API error ${response.statusCode}: ${response.data}');
    }
    final text = _extractOpenAiText(response.data!);
    return ToolResult.success('[PDF analyzed via page images]\n\n$text');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  ProviderCredential? _resolveCredential(String provider) {
    return configManager.config.providerCredentials[provider];
  }

  String _inferProvider(String modelName) {
    final lower = modelName.toLowerCase();
    if (lower.contains('claude')) return 'anthropic';
    if (lower.contains('gemini')) return 'google';
    if (lower.startsWith('gpt') || lower.startsWith('o1') || lower.startsWith('o3')) {
      return 'openai';
    }
    if (lower.contains('/')) return lower.split('/').first;
    return 'openai';
  }

  String _defaultApiBase(String provider) {
    return switch (provider) {
      'anthropic' => 'https://api.anthropic.com',
      'google' => 'https://generativelanguage.googleapis.com',
      'openrouter' => 'https://openrouter.ai/api/v1',
      _ => 'https://api.openai.com/v1',
    };
  }

  String _extractAnthropicText(Map<String, dynamic> data) {
    final content = data['content'] as List<dynamic>?;
    if (content == null) return data.toString();
    return content
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join('\n');
  }

  String _extractGeminiText(Map<String, dynamic> data) {
    try {
      final candidates = data['candidates'] as List<dynamic>;
      final parts = (candidates.first as Map)['content']['parts'] as List<dynamic>;
      return parts
          .whereType<Map>()
          .where((p) => p.containsKey('text'))
          .map((p) => p['text'] as String? ?? '')
          .join('\n');
    } catch (_) {
      return data.toString();
    }
  }

  String _extractOpenAiText(Map<String, dynamic> data) {
    try {
      final choices = data['choices'] as List<dynamic>;
      return (choices.first as Map)['message']['content'] as String? ?? '';
    } catch (_) {
      return data.toString();
    }
  }
}
