import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/assistant/assistant_controller.dart';
import 'package:hackathon/assistant/assistant_models.dart';
import 'package:hackathon/openrouter/openrouter_service.dart';
import 'package:hackathon/scan/product_identification_service.dart';
import 'package:hackathon/scan/shopping_companion_briefing.dart';
import 'package:hackathon/scan/shopping_companion_controller.dart';
import 'package:hackathon/services/speech_to_text_service.dart';
import 'package:hackathon/services/text_to_speech_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('rapid stop then start waits for old audio teardown', () async {
    final speech = _Speech();
    final tts = _GatedTts();
    final assistant = _assistant(speech: speech, tts: tts);
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (_) async => _briefing(),
    );
    await companion.start();
    tts.stopGate = Completer<void>();
    final stopping = companion.stop();
    final restarting = companion.start();
    await Future<void>.delayed(Duration.zero);
    expect(companion.active, isFalse);
    tts.stopGate!.complete();
    await Future.wait([stopping, restarting]);
    expect(companion.active, isTrue);
    expect(assistant.sessionVoiceEnabled, isTrue);
    expect(companion.listening, isTrue);
    tts.stopGate = null;
    await _dispose(companion, assistant);
  });

  test('last stop cancels a start queued behind teardown', () async {
    final tts = _GatedTts();
    final assistant = _assistant(tts: tts);
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (_) async => _briefing(),
    );
    await companion.start();
    final before = tts.spoken.length;
    tts.stopGate = Completer<void>();
    final stop = companion.stop();
    final start = companion.start();
    final lastStop = companion.stop();
    tts.stopGate!.complete();
    await Future.wait([stop, start, lastStop]);
    expect(companion.active, isFalse);
    expect(tts.spoken.length, before);
    expect(assistant.sessionVoiceEnabled, isFalse);
    tts.stopGate = null;
    await _dispose(companion, assistant);
  });

  test(
    'manual interruption reopens a microphone with a working callback',
    () async {
      final speech = _Speech()..duplex = true;
      final assistant = _assistant(speech: speech);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => _briefing(),
      );
      await companion.start();
      final listens = speech.listenCount;
      await companion.interruptAndListen();
      await _waitFor(() => speech.listenCount > listens);
      speech.result('A different question', isFinal: false);
      expect(companion.draft, 'A different question');
      await _dispose(companion, assistant);
    },
  );

  test('seeded mixed audio controls settle after a final stop', () async {
    final speech = _Speech()..duplex = true;
    final assistant = _assistant(speech: speech);
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (_) async => _briefing(),
    );
    final random = Random(7281);
    final pending = <Future<void>>[];
    for (var i = 0; i < 100; i++) {
      pending.add(switch (random.nextInt(7)) {
        0 => companion.start(),
        1 => companion.stop(),
        2 => companion.pauseListening(),
        3 => companion.resumeListening(),
        4 => companion.interruptAndListen(),
        5 => companion.replay(),
        _ => companion.submit('What can you help with?'),
      });
      if (i % 4 == 0) await Future<void>.delayed(Duration.zero);
    }
    await Future.wait(pending);
    await companion.stop();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(companion.active, isFalse);
    expect(assistant.listening, isFalse);
    expect(assistant.speaking, isFalse);
    expect(assistant.preparingSpeech, isFalse);
    expect(assistant.sessionVoiceEnabled, isFalse);
    await _dispose(companion, assistant);
  });

  test('starts listening automatically after the spoken greeting', () async {
    final events = <String>[];
    final speech = _Speech(events);
    final tts = _Tts(events);
    final assistant = _assistant(speech: speech, tts: tts);
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (_) async => throw StateError('unused'),
    );

    await companion.start();
    await _waitFor(() => speech.listenCount == 1);

    expect(events, contains('listen:1'));
    expect(
      events.any(
        (event) => event.startsWith('speak:Hi, I’m your shopping companion'),
      ),
      isTrue,
    );
    expect(companion.listening, isTrue);
    await _dispose(companion, assistant);
  });

  test(
    'failed greeting TTS exposes retry and still starts the microphone',
    () async {
      final speech = _Speech();
      final tts = _FailOnceTts();
      final assistant = _assistant(speech: speech, tts: tts);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => throw StateError('unused'),
      );

      await companion.start();
      await _waitFor(
        () => companion.speechError != null && speech.listenCount > 0,
      );
      expect(companion.preparingSpeech, isFalse);
      expect(companion.speaking, isFalse);

      await companion.retrySpeech();
      expect(tts.calls, 2);
      expect(companion.speechError, isNull);
      await _dispose(companion, assistant);
    },
  );

  test(
    'a final utterance submits automatically and resumes listening',
    () async {
      final speech = _Speech();
      final assistant = _assistant(speech: speech);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => throw StateError('unused'),
      );

      await companion.start();
      await _waitFor(() => speech.listenCount == 1);
      speech.result('What can you help with?', isFinal: true);
      await _waitFor(
        () =>
            companion.reply?.text == 'A grounded answer.' &&
            speech.listenCount >= 2 &&
            companion.listening,
      );

      expect(assistant.messages.map((message) => message.text), [
        'What can you help with?',
        'A grounded answer.',
      ]);
      expect(companion.listening, isTrue);
      await _dispose(companion, assistant);
    },
  );

  test(
    'duplex listening interrupts a read only turn and keeps new speech',
    () async {
      final pending = Completer<http.Response>();
      final speech = _Speech()..duplex = true;
      final assistant = AssistantController(
        data: _Data(),
        ai: OpenRouterService(
          apiKey: 'test',
          client: MockClient((_) => pending.future),
        ),
        speech: speech,
        tts: _Tts(),
      );
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => throw StateError('unused'),
      );

      await companion.start();
      await _waitFor(() => speech.listenCount == 1);
      final turn = companion.submit('Tell me about this product');
      await _waitFor(() => assistant.busy);
      await _waitFor(() => companion.listening);
      speech.result('Actually, is it suitable for me?', isFinal: false);
      await _waitFor(() => companion.draft.contains('Actually'));

      expect(assistant.busy, isFalse);
      expect(companion.draft, 'Actually, is it suitable for me?');
      pending.complete(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'The interrupted answer.',
                },
              },
            ],
          }),
          200,
        ),
      );
      await turn;
      await _dispose(companion, assistant);
    },
  );

  test(
    'duplex listening interrupts TTS and retains the user transcript',
    () async {
      final speech = _Speech()..duplex = true;
      final tts = _BlockingTts();
      final assistant = _assistant(speech: speech, tts: tts);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => throw StateError('unused'),
      );

      final starting = companion.start();
      await _waitFor(() => speech.listenCount == 1);
      speech.result(
        'Could you compare this with another option?',
        isFinal: false,
      );
      await _waitFor(() => companion.draft.isNotEmpty);

      expect(companion.draft, 'Could you compare this with another option?');
      expect(assistant.speaking, isFalse);
      await starting;
      await _dispose(companion, assistant);
    },
  );

  test(
    'a done status before the final result still submits the utterance',
    () async {
      final speech = _Speech();
      final assistant = _assistant(speech: speech);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => throw StateError('unused'),
      );

      await companion.start();
      await _waitFor(() => speech.listenCount == 1);
      speech.result('Tell me something', isFinal: false);
      speech.status('done');
      speech.result('Tell me something', isFinal: true);
      await _waitFor(
        () =>
            companion.reply?.text == 'A grounded answer.' &&
            speech.listenCount >= 2 &&
            companion.listening,
      );

      expect(assistant.messages.map((message) => message.text), [
        'Tell me something',
        'A grounded answer.',
      ]);
      await _dispose(companion, assistant);
    },
  );

  test(
    'stopping the session prevents automatic listening from restarting',
    () async {
      final speech = _Speech();
      final assistant = _assistant(speech: speech);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => throw StateError('unused'),
      );

      await companion.start();
      await _waitFor(() => speech.listenCount == 1);
      await companion.stop();
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(companion.active, isFalse);
      expect(speech.listenCount, 1);
      expect(companion.listening, isFalse);
      await _dispose(companion, assistant);
    },
  );

  test(
    'the details phrase invokes the details callback without sending a turn',
    () async {
      final speech = _Speech();
      final assistant = _assistant(speech: speech);
      var detailsOpened = 0;
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => throw StateError('unused'),
        onShowDetails: () => detailsOpened++,
      );

      await companion.start();
      await _waitFor(() => speech.listenCount == 1);
      speech.result('show me more', isFinal: true);
      await _waitFor(() => detailsOpened == 1);

      expect(detailsOpened, 1);
      expect(assistant.messages, isEmpty);
      await _dispose(companion, assistant);
    },
  );

  test('scan handoff speaks the briefing before listening resumes', () async {
    final speech = _Speech();
    final tts = _Tts();
    final assistant = _assistant(speech: speech, tts: tts);
    final briefingReady = Completer<ProductBriefing>();
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (_) => briefingReady.future,
    );

    await companion.start();
    await _waitFor(() => speech.listenCount == 1);
    await companion.scanning();
    expect(companion.listening, isFalse);

    final handoff = companion.updateProduct(_product());
    await _waitFor(() => companion.loading);
    expect(speech.listenCount, 1, reason: 'the mic stays off during a scan');
    briefingReady.complete(_briefing());
    await handoff;
    await _waitFor(
      () =>
          tts.spoken.any((text) => text.contains('A useful scan briefing.')) &&
          speech.listenCount >= 2 &&
          companion.listening,
    );

    expect(tts.spoken.first, startsWith('Hi, I’m your shopping companion'));
    expect(
      tts.spoken.any((text) => text.contains('A useful scan briefing.')),
      isTrue,
    );
    expect(companion.listening, isTrue);
    await _dispose(companion, assistant);
  });

  test(
    'pausing and resuming the microphone stops and restarts listening',
    () async {
      final speech = _Speech();
      final assistant = _assistant(speech: speech);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) async => throw StateError('unused'),
      );

      await companion.start();
      await _waitFor(() => speech.listenCount == 1);
      await companion.pauseListening();
      expect(companion.micPaused, isTrue);
      expect(companion.listening, isFalse);
      await companion.resumeListening();
      await _waitFor(() => speech.listenCount >= 2);

      expect(companion.micPaused, isFalse);
      expect(companion.listening, isTrue);
      await _dispose(companion, assistant);
    },
  );
}

class _Data implements AssistantDataSource {
  @override
  List<Map<String, Object?>> get tools => const [];
  @override
  Future<Map<String, Object?>> summary() async => const {};
  @override
  Future<AssistantToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
  ) async => const AssistantToolResult({});
  @override
  Future<Map<String, Object?>> confirm(AssistantAction action) async => const {
    'success': true,
  };
  @override
  Future<AssistantSettings> loadSettings() async =>
      const AssistantSettings(voiceEnabled: false);
  @override
  Future<void> saveSettings(AssistantSettings settings) async {}
}

class _Speech extends SpeechToTextService {
  _Speech([this.events]);

  final List<String>? events;
  bool duplex = false;
  void Function(String, bool)? _onResult;
  void Function(String)? _onStatus;
  int listenCount = 0;

  @override
  bool get supportsDuplex => duplex;

  @override
  bool get isAvailable => true;
  @override
  Future<bool> initialize({void Function(String)? onError}) async => true;
  @override
  Future<bool> listen({
    required void Function(String, bool) onResult,
    void Function(String)? onStatus,
    String locale = 'en-GB',
  }) async {
    listenCount++;
    events?.add('listen:$listenCount');
    _onResult = onResult;
    _onStatus = onStatus;
    return true;
  }

  void result(String text, {required bool isFinal}) =>
      _onResult?.call(text, isFinal);
  void status(String value) => _onStatus?.call(value);

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class _Tts extends TextToSpeechService {
  _Tts([this.events]);
  final List<String>? events;
  final spoken = <String>[];

  @override
  Future<void> speak(String text, {String? locale}) async {
    spoken.add(text);
    events?.add('speak:$text');
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVoice(String name, String locale) async {}
  @override
  Future<List<Map<String, String>>> getVoices() async => const [];
}

class _GatedTts extends _Tts {
  Completer<void>? stopGate;
  @override
  Future<void> stop() async {
    await stopGate?.future;
  }
}

class _BlockingTts extends TextToSpeechService {
  final Completer<void> _stopped = Completer<void>();

  @override
  Future<void> speak(String text, {String? locale}) => _stopped.future;

  @override
  Future<void> stop() async {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVoice(String name, String locale) async {}
  @override
  Future<List<Map<String, String>>> getVoices() async => const [];
}

class _FailOnceTts extends TextToSpeechService {
  int calls = 0;

  @override
  Future<void> speak(String text, {String? locale}) async {
    calls++;
    if (calls == 1) throw StateError('synthetic speech failure');
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVoice(String name, String locale) async {}
  @override
  Future<List<Map<String, String>>> getVoices() async => const [];
}

ProductIdentification _product() => const ProductIdentification(
  status: 'identified',
  productName: 'Oats',
  brand: 'Acme',
  variant: null,
  packageSize: '500 g',
  sku: null,
  gtin: '1234567890123',
  catalogProductId: null,
  confidence: 95,
  productNameConfidence: 95,
  brandConfidence: 90,
  variantConfidence: 0,
  skuConfidence: 0,
  gtinConfidence: 100,
  evidence: ['front label'],
  uncertainties: [],
);

ProductBriefing _briefing() => const ProductBriefing(
  key: 'oats',
  name: 'Acme Oats 500 g',
  text: 'A useful scan briefing.',
  facts: {'say': 'A useful scan briefing.'},
);

AssistantController _assistant({_Speech? speech, TextToSpeechService? tts}) =>
    AssistantController(
      data: _Data(),
      ai: OpenRouterService(
        apiKey: 'test',
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': _modelReply(r, 'A grounded answer.'),
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
      speech: speech ?? _Speech(),
      tts: tts ?? _Tts(),
    );

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'condition did not become true in time');
}

Future<void> _dispose(
  ShoppingCompanionController companion,
  AssistantController assistant,
) async {
  await companion.stop();
  companion.dispose();
  await assistant.stopAudio();
  assistant.dispose();
}

/// Mock model reply: answers a scan reaction with the assessment's test-only
/// `say` field, proving the assessment reached the prompt.
String _modelReply(http.BaseRequest request, String fallback) {
  final messages =
      (jsonDecode((request as http.Request).body) as Map)['messages'] as List;
  final last = messages.last as Map;
  if (last['role'] != 'user' ||
      !'${last['content']}'.startsWith('I just scanned this')) {
    return fallback;
  }
  final say = RegExp(r'"say":"([^"]*)"')
      .firstMatch('${(messages.first as Map)['content']}');
  return say?.group(1) ?? fallback;
}
