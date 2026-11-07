import 'package:speech_to_text/speech_to_text.dart';

/// Small replaceable wrapper around the device speech recognizer.
class SpeechToTextService {
  SpeechToTextService({SpeechToText? recognizer})
    : _recognizer = recognizer ?? SpeechToText();
  final SpeechToText _recognizer;
  bool _available = false;
  void Function(String)? _statusCallback;
  bool get isAvailable => _available;
  bool get isListening => _recognizer.isListening;

  Future<bool> initialize({void Function(String)? onError}) async {
    try {
      _available = await _recognizer.initialize(
        onError: (error) => onError?.call(error.errorMsg),
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
    try {
      await _recognizer.listen(
        listenOptions: SpeechListenOptions(
          localeId: locale,
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
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
    try {
      await _recognizer.stop();
    } catch (_) {}
  }

  Future<void> cancel() async {
    try {
      await _recognizer.cancel();
    } catch (_) {}
  }
}
