import 'package:flutter_tts/flutter_tts.dart';

/// App-facing wrapper for the platform's configured text-to-speech engine.
///
/// On Android this uses the device's selected TTS engine and installed voices.
/// The wrapper keeps call sites independent of the underlying engine, so a
/// local neural backend can be added later without changing UI code.
class TextToSpeechService {
  TextToSpeechService({FlutterTts? engine}) : _engine = engine ?? FlutterTts();

  final FlutterTts _engine;
  Future<void>? _configuration;

  Future<void> _configure() =>
      _configuration ??= _engine.awaitSpeakCompletion(true).then((_) {});

  /// Speaks [text], optionally using a locale such as `en-GB` or `en-US`.
  ///
  /// The returned future completes after speech playback. Empty input is
  /// ignored. The selected system voice is used unless [locale] is provided.
  Future<void> speak(String text, {String? locale}) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return;

    await _configure();
    if (locale != null) await _engine.setLanguage(locale);
    await _engine.speak(normalizedText);
  }

  /// Stops the current utterance and clears queued speech.
  Future<void> stop() async {
    await _engine.stop();
  }

  /// Sets speech speed. A value of `1.0` is the platform's normal rate.
  Future<void> setSpeechRate(double rate) async {
    await _configure();
    await _engine.setSpeechRate(rate);
  }

  /// Sets voice pitch. A value of `1.0` is the platform's normal pitch.
  Future<void> setPitch(double pitch) async {
    await _configure();
    await _engine.setPitch(pitch);
  }
}
