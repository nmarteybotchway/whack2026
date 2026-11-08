import 'text_to_speech_service.dart';

/// Web stub for the offline Kokoro voice.
///
/// Kokoro runs through native FFI (sherpa_onnx), which ships no web build,
/// and there is no browser system-TTS engine wired up either, so speech is
/// silently unavailable there. The conditional export in
/// [kokoro_tts_factory] selects this implementation when compiling for the
/// web.
class KokoroTtsService extends TextToSpeechService {
  KokoroTtsService({double speed = 1.0});
}
