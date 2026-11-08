library;

/// Platform selector for the offline Kokoro TTS service.
///
/// Exposes [KokoroTtsService] everywhere: native targets get the real
/// offline engine, and every other target (the web build, where sherpa_onnx
/// has no FFI libraries) gets a silent no-op stub with the same API.
export 'kokoro_tts_stub.dart' if (dart.library.io) 'kokoro_tts_service.dart';
