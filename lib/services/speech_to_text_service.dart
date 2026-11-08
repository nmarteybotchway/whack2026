import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'duplex_speech_service.dart';

/// Small replaceable wrapper around the device speech recognizer.
class SpeechToTextService {
  SpeechToTextService({SpeechToText? recognizer})
    : _recognizer = recognizer ?? SpeechToText();
  final SpeechToText _recognizer;
  bool _available = false;
  bool duplexEnabled = false;
  bool get supportsDuplex =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final DuplexSpeechService _duplex = DuplexSpeechService();
  StreamSubscription<Map<String, dynamic>>? _duplexSubscription;
  bool _duplexListening = false;
  int _duplexEpoch = 0;
  void Function(String)? _statusCallback;
  void Function(String)? _errorCallback;
  bool get isAvailable => _available;
  bool get isListening => _duplexListening || _recognizer.isListening;

  Future<bool> initialize({void Function(String)? onError}) async {
    if (onError != null) _errorCallback = onError;
    try {
      _available = await _recognizer.initialize(
        onError: (error) => _errorCallback?.call(error.errorMsg),
        onStatus: (status) => _statusCallback?.call(status),
      );
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  Future<bool> listen({
    required void Function(String text, bool finalResult) onResult,
    void Function(String status)? onStatus,
    String locale = 'en-GB',
  }) async {
    if (!_available && !await initialize()) return false;
    _statusCallback = onStatus;
    if (duplexEnabled && supportsDuplex) {
      final epoch = ++_duplexEpoch;
      await _duplexSubscription?.cancel();
      var completed = '';
      _duplexSubscription = _duplex.events.listen((event) {
        if (epoch != _duplexEpoch) return;
        final type = event['type'];
        if (type == 'partial' || type == 'final' || type == 'segment') {
          final text = event['text'] as String? ?? '';
          final cumulative = [
            completed,
            text,
          ].where((part) => part.isNotEmpty).join(' ');
          onResult(cumulative, type == 'final');
          if (type == 'segment') completed = cumulative;
          if (type == 'final') {
            _duplexListening = false;
            onStatus?.call('done');
          }
        } else if (type == 'ready') {
          _duplexListening = true;
          onStatus?.call('listening');
        } else if (type == 'error') {
          _duplexListening = false;
          _errorCallback?.call(
            'Speech recognition: ${event['message'] ?? 'Duplex audio unavailable'}',
          );
          onStatus?.call('done');
        } else if (type == 'status' && event['status'] == 'done') {
          _duplexListening = false;
          onStatus?.call('done');
        }
      });
      try {
        _duplexListening = await _duplex.start(locale: locale);
        return _duplexListening;
      } catch (_) {
        _duplexListening = false;
        _errorCallback?.call(
          'Speech recognition: simultaneous listening is unavailable on this device.',
        );
        return false;
      }
    }
    try {
      await _recognizer.listen(
        listenOptions: SpeechListenOptions(
          localeId: locale,
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 5),
          listenFor: const Duration(minutes: 2),
        ),
        onResult: (result) =>
            onResult(result.recognizedWords, result.finalResult),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    final hadDuplex = _duplexSubscription != null || _duplexListening;
    _duplexEpoch++;
    _duplexListening = false;
    await _duplexSubscription?.cancel();
    _duplexSubscription = null;
    if (hadDuplex) await _duplex.stop();
    try {
      await _recognizer.stop();
    } catch (_) {}
  }

  Future<void> cancel() async {
    await stop();
    try {
      await _recognizer.cancel();
    } catch (_) {}
  }
}
