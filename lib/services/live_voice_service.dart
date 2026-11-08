import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'text_to_speech_service.dart';

/// Fast device voice used for live conversation turns.
/// Android uses the local system voice with explicit utterance completion;
/// other platforms fall back to flutter_tts.
class LiveVoiceService extends TextToSpeechService {
  LiveVoiceService({FlutterTts? engine})
    : _fallback = PlatformTextToSpeechService(engine: engine);

  static const MethodChannel _methodChannel = MethodChannel(
    'sentinel/live_voice',
  );
  static const EventChannel _eventChannel = EventChannel(
    'sentinel/live_voice/events',
  );
  final PlatformTextToSpeechService _fallback;
  StreamSubscription<dynamic>? _events;
  final Map<String, void Function()> _startCallbacks = {};
  double _rate = 0.5;
  bool _conversationMode = false;
  int _sequence = 0;
  int _operation = 0;
  bool _disposed = false;
  bool _initialized = false;

  void _ensureEvents() {
    _events ??= _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object _) {},
    );
  }

  bool get _usesAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final token = event['token']?.toString();
    if (token == null) return;
    if (event['type'] == 'started') {
      _startCallbacks[token]?.call();
    } else if (event['type'] == 'completed' || event['type'] == 'error') {
      _startCallbacks.remove(token);
    }
  }

  @override
  Future<void> prepare() async {
    if (!_usesAndroid) return _fallback.prepare();
    if (_disposed) throw StateError('Live voice service has been disposed.');
    _ensureEvents();
    await _methodChannel.invokeMapMethod<String, dynamic>('prepare');
    _initialized = true;
    await _methodChannel.invokeMethod<void>('setConversationMode', {
      'enabled': _conversationMode,
    });
  }

  @override
  Future<void> speak(String text, {String? locale}) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (!_usesAndroid) return _fallback.speak(normalized, locale: locale);
    await _speakAndroid(normalized, locale: locale);
  }

  @override
  Future<void> speakWithProgress(
    String text, {
    String? locale,
    required void Function() onPlaybackStarted,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (!_usesAndroid) {
      return _fallback.speakWithProgress(
        normalized,
        locale: locale,
        onPlaybackStarted: onPlaybackStarted,
      );
    }
    await _speakAndroid(
      normalized,
      locale: locale,
      onPlaybackStarted: onPlaybackStarted,
    );
  }

  Future<void> _speakAndroid(
    String text, {
    String? locale,
    void Function()? onPlaybackStarted,
  }) async {
    if (_disposed) throw StateError('Live voice service has been disposed.');
    final operation = ++_operation;
    _ensureEvents();
    _initialized = true;
    await _methodChannel.invokeMethod<void>('setConversationMode', {
      'enabled': _conversationMode,
    });
    if (_disposed || operation != _operation) return;
    final token =
        'dart-${++_sequence}-${DateTime.now().microsecondsSinceEpoch}';
    if (onPlaybackStarted != null) _startCallbacks[token] = onPlaybackStarted;
    try {
      await _methodChannel.invokeMethod<void>('speak', <String, Object>{
        'text': text,
        'locale': ?locale,
        'rate': _rate,
        'token': token,
      });
    } finally {
      _startCallbacks.remove(token);
    }
  }

  @override
  Future<void> setConversationMode(bool enabled) async {
    _conversationMode = enabled;
    if (_usesAndroid && _initialized) {
      try {
        await _methodChannel.invokeMethod<void>('setConversationMode', {
          'enabled': enabled,
        });
      } on PlatformException {
        // Mode hints are advisory and should not disrupt live conversation.
      }
    }
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    _rate = rate.clamp(0.25, 1.5).toDouble();
    if (!_usesAndroid) return _fallback.setSpeechRate(rate);
    if (_initialized) {
      await _methodChannel.invokeMethod<void>('setSpeechRate', {'rate': _rate});
    }
  }

  @override
  Future<List<Map<String, String>>> getVoices() => _fallback.getVoices();

  @override
  Future<void> stop() async {
    ++_operation;
    _startCallbacks.clear();
    if (_usesAndroid && _initialized) {
      await _methodChannel.invokeMethod<void>('stop');
    } else {
      await _fallback.stop();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_operation;
    _events?.cancel();
    _startCallbacks.clear();
    if (_usesAndroid && _initialized) {
      unawaited(
        _methodChannel.invokeMethod<void>('dispose').catchError((Object _) {}),
      );
    } else {
      _fallback.dispose();
    }
  }
}
