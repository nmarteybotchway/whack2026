import 'dart:async';

import 'package:flutter/services.dart';

/// Android handsfree recognition that streams echo-cancelled PCM to the system
/// recognizer. The Android bridge reports errors instead of silently reopening
/// the default microphone path when external audio injection is unsupported.
class DuplexSpeechService {
  static const MethodChannel _methods = MethodChannel('sentinel/duplex_speech');
  static const EventChannel _eventChannel = EventChannel(
    'sentinel/duplex_speech/events',
  );

  Stream<Map<String, dynamic>> get events => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, dynamic>.from(event as Map));

  Future<bool> start({String locale = 'en-US'}) async {
    try {
      await _methods.invokeMethod<void>('start', <String, Object>{
        'locale': locale,
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _methods.invokeMethod<void>('stop');
    } on MissingPluginException {
      // The service is only registered on Android; tolerate teardown races.
    }
  }
}
