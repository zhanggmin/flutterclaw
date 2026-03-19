/// Transcription service using the OpenAI Whisper-compatible
/// `/v1/audio/transcriptions` endpoint.
///
/// Works with any OpenAI-compatible provider that exposes the transcription
/// endpoint (OpenAI, Groq, etc.). Falls back to the configured API base from
/// the active model's provider, defaulting to `https://api.openai.com/v1`.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

final _log = Logger('AudioTranscriptionService');

class AudioTranscriptionService {
  final String apiKey;
  final String apiBase;

  /// [apiBase] should be the base URL of the provider, e.g.
  /// `https://api.openai.com/v1` or `https://api.groq.com/openai/v1`.
  const AudioTranscriptionService({
    required this.apiKey,
    this.apiBase = 'https://api.openai.com/v1',
  });

  /// Transcribe a recorded audio file.
  ///
  /// [filePath] — path to the recorded audio file (m4a / wav).
  /// [model]    — Whisper model name (default: `whisper-1`).
  /// [language] — optional BCP-47 language hint (e.g. `'en'`, `'es'`).
  ///
  /// Returns the transcribed text, or null on failure.
  Future<String?> transcribe(
    String filePath, {
    String model = 'whisper-1',
    String? language,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      _log.warning('Audio file not found: $filePath');
      return null;
    }

    final dio = Dio(BaseOptions(
      baseUrl: apiBase,
      headers: {'Authorization': 'Bearer $apiKey'},
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));

    try {
      final fields = <String, dynamic>{
        'file': await MultipartFile.fromFile(
          filePath,
          filename: file.uri.pathSegments.last,
        ),
        'model': model,
        'response_format': 'json',
      };
      final lang = language;
      if (lang != null) fields['language'] = lang;
      final formData = FormData.fromMap(fields);

      final response = await dio.post('/audio/transcriptions', data: formData);

      final text = response.data?['text'] as String?;
      _log.info('Transcription complete: ${text?.length} chars');
      return text?.trim();
    } on DioException catch (e) {
      _log.warning('Transcription failed: ${e.message}');
      return null;
    } catch (e) {
      _log.severe('Transcription error', e);
      return null;
    }
  }
}
