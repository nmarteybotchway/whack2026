import 'package:flutter_tts/flutter_tts.dart';

/// App-facing wrapper for text-to-speech playback.
///
/// The base class keeps call sites independent of the underlying engine.
/// [KokoroTtsService] provides the default offline neural voice; this file
/// also holds [PlatformTextToSpeechService], which delegates to the device's
/// system TTS engine (flutter_tts) and is used as a fallback.
abstract class TextToSpeechService {
  const TextToSpeechService();

  /// Speaks [text], optionally using a locale such as `en-GB` or `en-US`.
  ///
  /// The returned future completes after speech playback. Empty input is
  /// ignored.
  Future<void> speak(String text, {String? locale}) async {}

  Future<List<Map<String, String>>> getVoices() async => const [];

  Future<void> setVoice(String name, String locale) async {}

  /// Stops the current utterance and clears queued speech.
  Future<void> stop() async {}

  /// Sets speech speed. A value of `1.0` is the platform's normal rate.
  Future<void> setSpeechRate(double rate) async {}

  /// Sets voice pitch. A value of `1.0` is the platform's normal pitch.
  Future<void> setPitch(double pitch) async {}

  /// Releases engine resources. Safe to call multiple times.
  void dispose() {}
}

/// Text-to-speech backed by the device's installed system engine.
class PlatformTextToSpeechService extends TextToSpeechService {
  PlatformTextToSpeechService({FlutterTts? engine}) : _providedEngine = engine;

  final FlutterTts? _providedEngine;
  FlutterTts? _engineInstance;
  FlutterTts get _engine =>
      _providedEngine ?? (_engineInstance ??= FlutterTts());
  bool get _hasEngine => _providedEngine != null || _engineInstance != null;
  Future<void>? _configuration;

  Future<void> _configure() =>
      _configuration ??= _engine.awaitSpeakCompletion(true).then((_) {});

  @override
  Future<void> speak(String text, {String? locale}) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return;

    await _configure();
    if (locale != null) await _engine.setLanguage(locale);
    await _engine.speak(normalizedText);
  }

  @override
  Future<List<Map<String, String>>> getVoices() async {
    final voices = await _engine.getVoices;
    if (voices is! List) return const [];
    return voices
        .whereType<Map>()
        .map((voice) => voice.map((key, value) => MapEntry('$key', '$value')))
        .toList();
  }

  @override
  Future<void> setVoice(String name, String locale) async {
    if (name.isEmpty) return;
    await _configure();
    await _engine.setVoice({'name': name, 'locale': locale});
  }

  @override
  Future<void> stop() async {
    if (!_hasEngine) return;
    await _engine.stop();
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _configure();
    await _engine.setSpeechRate(rate);
  }

  @override
  Future<void> setPitch(double pitch) async {
    await _configure();
    await _engine.setPitch(pitch);
  }
}
