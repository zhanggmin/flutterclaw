import 'dart:io';
import 'package:flutter/services.dart';

/// Dart bridge to the Android floating overlay status chip.
/// No-op on iOS.
class OverlayService {
  static const _channel = MethodChannel('ai.flutterclaw/overlay');

  Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('overlay_check_permission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('overlay_request_permission');
    } catch (_) {}
  }

  Future<void> show(String text) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('overlay_show', {'text': text});
    } catch (_) {}
  }

  Future<void> hide() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('overlay_hide');
    } catch (_) {}
  }
}
