/// Cross-platform voice recording service using the `record` package.
///
/// Records audio to a temporary file (AAC/m4a on iOS, AAC on Android) and
/// returns the file path when stopped. The caller is responsible for deleting
/// the file after use.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:logging/logging.dart';

final _log = Logger('VoiceRecordingService');

class VoiceRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  bool get isRecording => _recording;

  /// Start recording. Returns false if microphone permission is denied.
  Future<bool> start() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _log.warning('Microphone permission denied');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000, // Whisper prefers 16 kHz
        ),
        path: path,
      );
      _recording = true;
      _log.info('Recording started: $path');
      return true;
    } catch (e) {
      _log.severe('Failed to start recording', e);
      return false;
    }
  }

  /// Stop recording and return the path to the recorded file, or null on error.
  Future<String?> stop() async {
    if (!_recording) return null;
    try {
      final path = await _recorder.stop();
      _recording = false;
      _log.info('Recording stopped: $path');
      return path;
    } catch (e) {
      _log.severe('Failed to stop recording', e);
      _recording = false;
      return null;
    }
  }

  /// Cancel recording without saving.
  Future<void> cancel() async {
    if (!_recording) return;
    try {
      await _recorder.cancel();
    } catch (_) {}
    _recording = false;
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }

  /// Delete the recorded file after it has been transcribed/used.
  static Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
