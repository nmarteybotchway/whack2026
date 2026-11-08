import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:piper_phonemize/piper_phonemize.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'text_to_speech_service.dart';
import 'speech_chunks.dart';

/// Offline neural text-to-speech backed by the bundled Kokoro-82M model.
///
/// The model ships in the app bundle (`assets/tts/`), is extracted to the
/// app-support directory on first use, and runs fully offline. Text is
/// phonemized on the main isolate (where the espeak-ng data is initialized)
/// and synthesized on a background isolate; each sentence's audio is queued
/// for playback as it arrives, so long replies start speaking before
/// synthesis finishes. Playback uses [AudioPlayer] with 16-bit WAV.
class KokoroTtsService extends TextToSpeechService {
  KokoroTtsService({this._speed = 1.0});

  /// Default speaker: af_bella (sid 1), a clear, expressive female voice.
  static const int _defaultSid = 1;

  /// Kokoro v0.19 outputs 24 kHz mono float PCM.
  static const int _sampleRate = 24000;

  /// CPU threads for synthesis. Measured on a Snapdragon 8 Gen 3 at 6
  /// threads: real-time factor ~0.5-0.7 for full sentences, ~1.0 for short
  /// opening phrases. Beyond 6, work spills onto the efficiency cores.
  static const int _numThreads = 6;

  /// Speaker ID map for kokoro-en-v0_19 (11 built-in voices).
  static const Map<String, int> voiceIds = {
    'af': 0,
    'af_bella': 1,
    'af_nicole': 2,
    'af_sarah': 3,
    'af_sky': 4,
    'am_adam': 5,
    'am_michael': 6,
    'bf_emma': 7,
    'bf_isabella': 8,
    'bm_george': 9,
    'bm_lewis': 10,
  };

  /// Locale reported for each built-in voice, so the settings page can map a
  /// voice choice back to a matching locale.
  static const Map<String, String> voiceLocales = {
    'af': 'en-US',
    'af_bella': 'en-US',
    'af_nicole': 'en-US',
    'af_sarah': 'en-US',
    'af_sky': 'en-US',
    'am_adam': 'en-US',
    'am_michael': 'en-US',
    'bf_emma': 'en-GB',
    'bf_isabella': 'en-GB',
    'bm_george': 'en-GB',
    'bm_lewis': 'en-GB',
  };

  bool _conversationMode = false;

  @override
  void setConversationMode(bool enabled) {
    _conversationMode = enabled;
  }

  int _sid = _defaultSid;
  Object? _initError;

  /// Synthesis speed multiplier (kokoro: 1.0 normal, lower is slower).
  double _speed;

  final Completer<void> _ready = Completer<void>();
  AudioPlayer? _player;
  StreamSubscription<void>? _playbackSubscription;
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _mainPort;
  int _generation = 0;
  int _playedUpTo = 0;
  bool _disposed = false;
  bool _draining = false;
  Completer<void>? _sentenceDone;
  Completer<void>? _utteranceDone;
  int _utteranceGeneration = -1;
  int _pendingSentences = 0;
  final List<(Float32List, int)> _playQueue = [];

  /// Completes once the model is extracted and the worker engine is loaded.
  Future<void> get ready => _ready.future;

  /// True once initialization finished successfully.
  bool get isAvailable =>
      _ready.isCompleted && _initError == null && !_disposed;

  Future<void>? _workerInitialization;
  void Function()? _playbackStarted;

  @override
  Future<void> prepare() => _ensureWorker();

  // ── Initialization ──────────────────────────────────────────────────────

  Future<void> _ensureWorker() => _workerInitialization ??= _initializeWorker();

  Future<void> _initializeWorker() async {
    unawaited(_ready.future.catchError((Object _) {}));
    if (_initError != null) {
      throw StateError('Kokoro TTS initialization failed: $_initError');
    }
    if (_isolate != null) return;
    try {
      await _startWorker();
      if (!_ready.isCompleted) _ready.complete();
    } catch (e) {
      _initError = e;
      if (!_ready.isCompleted) _ready.completeError(e);
      rethrow;
    }
  }

  Future<void> _startWorker() async {
    // The phonemizer needs espeak-ng data extracted from the piper_phonemize
    // package assets, plus its own FFI bindings on this isolate.
    await initBindingsAsync();
    final dataDir = await extractEspeakNgData();
    if (PiperPhonemize.initialize(dataDir) < 0) {
      throw StateError('Failed to initialize the phonemizer');
    }

    final supportDir = (await getApplicationSupportDirectory()).path;
    final modelPath = await _copyAsset(
      'assets/tts/model.onnx',
      p.join(supportDir, 'tts', 'model.onnx'),
    );
    final voicesPath = await _copyAsset(
      'assets/tts/voices.bin',
      p.join(supportDir, 'tts', 'voices.bin'),
    );
    final tokensPath = await _copyAsset(
      'assets/tts/tokens.txt',
      p.join(supportDir, 'tts', 'tokens.txt'),
    );

    if (_disposed) throw StateError('Voice engine was disposed.');
    final mainPort = ReceivePort();
    _mainPort = mainPort;
    final readyCompleter = Completer<void>();
    mainPort.listen((message) => _handleWorkerMessage(message, readyCompleter));
    _isolate = await Isolate.spawn(_workerEntry, (
      mainPort.sendPort,
      [modelPath, voicesPath, tokensPath],
    ));
    await readyCompleter.future.timeout(const Duration(minutes: 2));
  }

  void _handleWorkerMessage(dynamic message, Completer<void> readyCompleter) {
    if (message is SendPort) {
      _workerPort = message;
      return;
    }
    if (message is! Map) return;
    switch (message['event']) {
      case 'ready':
        if (!readyCompleter.isCompleted) readyCompleter.complete();
      case 'audio':
        final generation = message['generation'] as int;
        if (generation == _generation && !_disposed) {
          _pendingSentences--;
          _playQueue.add((
            message['samples'] as Float32List,
            (message['sampleRate'] as int?) ?? _sampleRate,
          ));
          unawaited(_drainQueue());
        }
      case 'error':
        final generation = message['generation'] as int?;
        if (generation == null) {
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(StateError('${message['error']}'));
          }
        } else if (generation == _generation) {
          _failUtterance(
            generation,
            StateError('Speech synthesis failed.'),
            StackTrace.current,
          );
        }
    }
  }

  // ── Worker isolate ──────────────────────────────────────────────────────

  static void _workerEntry((SendPort, List<String>) setup) {
    final (mainPort, paths) = setup;
    // IMPORTANT: sherpa-onnx must be initialized in every isolate.
    sherpa_onnx.initBindings();
    final port = ReceivePort();
    mainPort.send(port.sendPort);

    sherpa_onnx.OfflineTts? tts;
    int activeGeneration = -1;
    try {
      tts = sherpa_onnx.OfflineTts(
        sherpa_onnx.OfflineTtsConfig(
          model: sherpa_onnx.OfflineTtsModelConfig(
            kokoro: sherpa_onnx.OfflineTtsKokoroModelConfig(
              model: paths[0],
              voices: paths[1],
              tokens: paths[2],
            ),
            numThreads: _numThreads,
          ),
          maxNumSentences: 1,
        ),
      );
      mainPort.send({'event': 'ready'});
    } catch (e) {
      mainPort.send({'event': 'error', 'error': '$e'});
      port.listen((_) {});
      return;
    }

    port.listen((message) {
      if (message is! Map) return;
      switch (message['event']) {
        case 'cancel':
          activeGeneration = message['generation'] as int;
        case 'generate':
          final generation = message['generation'] as int;
          if (generation != activeGeneration) return;
          try {
            final audio = tts!.generateWithConfig(
              text: '',
              config: sherpa_onnx.OfflineTtsGenerationConfig(
                sid: message['sid'] as int,
                speed: message['speed'] as double,
                phonemeCodepoints: [
                  for (final sentence in message['codepoints'] as List)
                    List<int>.from(sentence as List),
                ],
              ),
            );
            // A result for a cancelled generation is dropped on the main
            // isolate by generation; sending it keeps the protocol simple.
            mainPort.send({
              'event': 'audio',
              'generation': generation,
              'samples': audio.samples,
              'sampleRate': audio.sampleRate,
            });
          } catch (e) {
            mainPort.send({
              'event': 'error',
              'generation': generation,
              'error': '$e',
            });
          }
      }
    });
  }

  // ── TextToSpeechService API ─────────────────────────────────────────────

  @override
  Future<void> speak(String text, {String? locale}) =>
      speakWithProgress(text, locale: locale, onPlaybackStarted: () {});

  @override
  Future<void> speakWithProgress(
    String text, {
    String? locale,
    required void Function() onPlaybackStarted,
  }) async {
    final requestedGeneration = _generation;
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    await _ensureWorker();
    if (_disposed || requestedGeneration != _generation) return;

    // Kokoro-en speaks English only; the requested locale is ignored.
    final generation = _nextGeneration();
    _playbackStarted = onPlaybackStarted;
    _playedUpTo = generation;
    _playQueue.clear();
    await _player?.stop();
    if (_disposed || generation != _generation) return;
    // Wake the playback loop for the old utterance, if any.
    _interruptPlayback();

    // Phonemize up front: espeak-ng is initialized on this isolate only.
    final codepoints = [
      for (final chunk in speechChunks(normalized))
        ...PiperPhonemize.phonemize(
          chunk,
          voice: 'en-us',
        ).where((sentence) => sentence.isNotEmpty),
    ];
    if (codepoints.isEmpty || _workerPort == null) return;

    // Send every sentence up front; the worker synthesizes them in order and
    // playback starts as soon as the first sentence's audio arrives.
    final done = Completer<void>();
    _utteranceDone = done;
    _utteranceGeneration = generation;
    _pendingSentences = codepoints.length;
    for (final sentence in codepoints) {
      _workerPort!.send({
        'event': 'generate',
        'generation': generation,
        'codepoints': [sentence],
        'sid': _sid,
        'speed': _speed,
      });
    }
    // The future resolves when playback of this utterance finishes, is
    // interrupted by stop(), or fails — matching the base-class contract.
    await done.future;
  }

  /// Bumps and returns the active generation, invalidating queued audio and
  /// any in-flight synthesis from the previous utterance.
  int _nextGeneration() {
    final generation = ++_generation;
    _workerPort?.send({'event': 'cancel', 'generation': generation});
    _finishUtterance(generation - 1);
    return generation;
  }

  /// Resolves the pending `speak()` future for [generation], whether its
  /// playback completed, was interrupted, or never produced audio.
  void _finishUtterance(
    int generation, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (generation == _utteranceGeneration &&
        !(_utteranceDone?.isCompleted ?? true)) {
      if (error == null) {
        _utteranceDone!.complete();
      } else {
        _utteranceDone!.completeError(error, stackTrace);
      }
      _utteranceDone = null;
      _utteranceGeneration = -1;
    }
  }

  /// Fail the awaiting caller and invalidate queued/in-flight sentence audio.
  void _failUtterance(int generation, Object error, StackTrace stackTrace) {
    if (generation != _generation || generation != _utteranceGeneration) return;
    ++_generation;
    _workerPort?.send({'event': 'cancel', 'generation': _generation});
    _playedUpTo = -1;
    _pendingSentences = 0;
    _playQueue.clear();
    _interruptPlayback();
    final player = _player;
    if (player != null) unawaited(player.stop().catchError((Object _) {}));
    _finishUtterance(generation, error: error, stackTrace: stackTrace);
  }

  @override
  Future<void> stop() async {
    _playbackStarted = null;
    _nextGeneration();
    _playQueue.clear();
    _playedUpTo = _generation;
    try {
      await _player?.stop();
    } finally {
      _interruptPlayback();
    }
  }

  @override
  Future<List<Map<String, String>>> getVoices() async => [
    for (final entry in voiceIds.entries)
      {'name': entry.key, 'locale': voiceLocales[entry.key] ?? 'en-US'},
  ];

  @override
  Future<void> setVoice(String name, String locale) async {
    final sid = voiceIds[name];
    if (sid != null) _sid = sid;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    // flutter_tts rates run ~[0.05, 3] with 1.0 as normal; the app's default
    // is 0.5. Kokoro clamps to [0.5, 1] for natural output, with the app's
    // default mapped to normal speed.
    _speed = (rate * 2).clamp(0.5, 1.0).toDouble();
  }

  @override
  Future<void> setPitch(double pitch) async {
    // Kokoro has no pitch control.
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _playQueue.clear();
    _interruptPlayback();
    _finishUtterance(_utteranceGeneration);
    unawaited(_playbackSubscription?.cancel());
    _playbackSubscription = null;
    unawaited(_player?.dispose());
    _player = null;
    _mainPort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _mainPort = null;
  }

  // ── Playback ────────────────────────────────────────────────────────────

  Future<void> _drainQueue() async {
    if (_draining) return;
    _draining = true;
    var playbackGeneration = _generation;
    try {
      while (_playQueue.isNotEmpty && !_disposed) {
        final generation = _generation;
        playbackGeneration = generation;
        if (_playedUpTo != generation) return;
        final (samples, sampleRate) = _playQueue.removeAt(0);
        final wav = _encodeWav(samples, sampleRate);
        final player = _player ??= AudioPlayer();
        await player.stop();
        await player.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              contentType: AndroidContentType.speech,
              usageType: _conversationMode
                  ? AndroidUsageType.voiceCommunication
                  : AndroidUsageType.media,
              audioFocus: _conversationMode
                  ? AndroidAudioFocus.none
                  : AndroidAudioFocus.gain,
              audioMode: _conversationMode
                  ? AndroidAudioMode.inCommunication
                  : AndroidAudioMode.normal,
              isSpeakerphoneOn: _conversationMode,
            ),
          ),
        );
        final played = Completer<void>();
        _sentenceDone = played;
        unawaited(_playbackSubscription?.cancel());
        _playbackSubscription = player.onPlayerComplete.listen((_) {
          if (!played.isCompleted) played.complete();
        });
        try {
          if (generation != _generation || _disposed) return;
          await player.play(BytesSource(wav));
          if (generation == _generation && !_disposed) {
            final started = _playbackStarted;
            _playbackStarted = null;
            started?.call();
          }
          // Wait for completion, ending early on interruption. The timeout is
          // a fallback in case the completion event never fires.
          final seconds = (samples.length / sampleRate).ceil() + 2;
          await played.future.timeout(Duration(seconds: seconds));
        } catch (error, stackTrace) {
          _failUtterance(generation, error, stackTrace);
          return;
        } finally {
          await _playbackSubscription?.cancel();
          _playbackSubscription = null;
          _sentenceDone = null;
        }
        if (generation != _generation || _disposed) return;
        if (_pendingSentences <= 0 && _playQueue.isEmpty) {
          _finishUtterance(generation);
        }
      }
    } catch (error, stackTrace) {
      _failUtterance(playbackGeneration, error, stackTrace);
    } finally {
      _draining = false;
      // A new utterance may have queued audio while an older loop unwound.
      if (_playQueue.isNotEmpty && !_disposed) unawaited(_drainQueue());
    }
  }

  /// Wakes a playback loop waiting on the current sentence, after the audio
  /// player has already been stopped by the interrupting call.
  void _interruptPlayback() {
    final sentence = _sentenceDone;
    if (sentence != null && !sentence.isCompleted) sentence.complete();
    _sentenceDone = null;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Encodes mono float PCM [-1, 1] as a 16-bit WAV file.
  static Uint8List _encodeWav(Float32List samples, int sampleRate) {
    final dataLength = samples.length * 2;
    final wav = Uint8List(44 + dataLength);
    final view = ByteData.view(wav.buffer);
    void str(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        wav[offset + i] = s.codeUnitAt(i);
      }
    }

    str(0, 'RIFF');
    view.setUint32(4, 36 + dataLength, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little); // PCM
    view.setUint16(22, 1, Endian.little); // mono
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    view.setUint16(32, 2, Endian.little); // block align
    view.setUint16(34, 16, Endian.little); // bits per sample
    str(36, 'data');
    view.setUint32(40, dataLength, Endian.little);

    var offset = 44;
    for (final sample in samples) {
      final clamped = sample.clamp(-1.0, 1.0);
      view.setInt16(offset, (clamped * 32767).round(), Endian.little);
      offset += 2;
    }
    return wav;
  }

  /// Copies a bundled model asset to [target], skipping when it already
  /// exists with a matching size (Kokoro's fp32 model is ~330 MB).
  static Future<String> _copyAsset(String asset, String target) async {
    final existing = File(target);
    final bytes = await rootBundle.load(asset);
    if (await existing.exists() &&
        await existing.length() == bytes.lengthInBytes) {
      return target;
    }
    await existing.create(recursive: true);
    await existing.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    return target;
  }
}
