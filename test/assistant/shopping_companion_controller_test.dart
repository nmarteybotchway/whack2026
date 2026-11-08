import 'dart:async';
import 'dart:convert';

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
      const AssistantSettings(voiceEnabled: true);
  @override
  Future<void> saveSettings(AssistantSettings settings) async {}
}

class _Speech extends SpeechToTextService {
  bool listening = false;
  final List<void Function(String, bool)> results = [];
  @override
  bool get isAvailable => true;
  @override
  bool get isListening => listening;
  @override
  Future<bool> initialize({void Function(String)? onError}) async => true;
  @override
  Future<bool> listen({
    required void Function(String, bool) onResult,
    void Function(String)? onStatus,
    String locale = 'en-GB',
  }) async {
    listening = true;
    results.add(onResult);
    return true;
  }

  void emit(int index, String text, {bool isFinal = false}) {
    results[index](text, isFinal);
  }

  @override
  Future<void> stop() async {
    listening = false;
  }

  @override
  Future<void> cancel() async {
    listening = false;
  }
}

class _Tts extends TextToSpeechService {
  int speaks = 0;
  @override
  Future<void> speak(String text, {String? locale}) async {
    speaks++;
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

http.Response _response(String text) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': text},
      },
    ],
  }),
  200,
);

AssistantController _assistant({
  http.Client? client,
  _Speech? speech,
  _Tts? tts,
}) => AssistantController(
  data: _Data(),
  ai: OpenRouterService(
    apiKey: 'test',
    client:
        client ?? MockClient((r) async => _response(_modelReply(r, 'Answer.'))),
  ),
  speech: speech ?? _Speech(),
  tts: tts ?? _Tts(),
);

ProductIdentification _product(String name, String gtin) =>
    ProductIdentification(
      status: 'identified',
      productName: name,
      brand: 'Acme',
      variant: 'Original',
      packageSize: '250 g',
      sku: null,
      gtin: gtin,
      catalogProductId: null,
      confidence: 95,
      productNameConfidence: 95,
      brandConfidence: 95,
      variantConfidence: 95,
      skuConfidence: 0,
      gtinConfidence: 100,
      evidence: const ['label'],
      uncertainties: const [],
    );

ProductBriefing _brief(ProductIdentification p) => ProductBriefing(
  key: productKeyFor(p),
  name: p.displayName,
  text: 'Briefing for ${p.productName}.',
  facts: {'say': 'Briefing for ${p.productName}.'},
  alternatives: const [
    CompanionAlternative(
      name: 'Other option',
      detail: 'has fewer known conflicts',
    ),
  ],
);

void main() {
  test(
    'a scan is answered by the model from the personal assessment',
    () async {
      final requests = <String>[];
      final assistant = _assistant(
        client: MockClient((r) async {
          requests.add(r.body);
          return _response(_modelReply(r, 'Answer.'));
        }),
      );
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) async => _brief(p),
      );
      await companion.start();
      await companion.updateProduct(_product('Oats', '001'));
      expect(companion.reply?.text, 'Briefing for Oats.');
      expect(
        assistant.messages.where((m) => m.role == 'user'),
        isEmpty,
        reason: 'the scan prompt is hidden from the conversation',
      );
      expect(requests.last, contains('assessment'));
      companion.dispose();
      assistant.dispose();
    },
  );

  test('a scan falls back to the fixed wording when the model fails', () async {
    final tts = _Tts();
    final assistant = _assistant(
      tts: tts,
      client: MockClient((_) async => http.Response('down', 500)),
    );
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) async => _brief(p),
    );
    await companion.start();
    await companion.updateProduct(_product('Oats', '001'));
    expect(companion.reply?.text, startsWith('Briefing for Oats.'));
    expect(assistant.error, isNull);
    companion.dispose();
    assistant.dispose();
  });

  test(
    'an assistant photo assessment is adopted without a second briefing',
    () async {
      var loads = 0;
      final assistant = _assistant();
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) async {
          loads++;
          return _brief(p);
        },
      );
      await companion.start();
      final facts = await companion.assess(_product('Oats', '001'));
      expect(facts['say'], 'Briefing for Oats.');
      final before = assistant.messages.length;
      await companion.updateProduct(_product('Oats', '001'));
      expect(loads, 1);
      expect(assistant.messages.length, before);
      expect(companion.briefing?.name, contains('Oats'));
      companion.dispose();
      assistant.dispose();
    },
  );

  test('duplicate scans across scanning transitions do not repeat the announcement', () async {
    final assistant = _assistant();
    var loads = 0;
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) async {
        loads++;
        return _brief(p);
      },
    );
    final product = _product('Oats', '001');
    await companion.start();
    await companion.updateProduct(product);
    final messageCount = assistant.messages.length;
    await companion.scanning();
    await companion.updateProduct(product);
    expect(loads, 2, reason: 'fresh product facts are loaded after a new scan');
    expect(
      assistant.messages.length,
      messageCount,
      reason: 'same product announcement is deduplicated',
    );
    companion.dispose();
    assistant.dispose();
  });

  test(
    'late briefing for prior product is ignored and latest product is shown',
    () async {
      final assistant = _assistant();
      final a = Completer<ProductBriefing>();
      final b = Completer<ProductBriefing>();
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) => p.productName == 'Oats' ? a.future : b.future,
      );
      await companion.start();
      final first = companion.updateProduct(_product('Oats', '001'));
      await Future<void>.delayed(Duration.zero);
      final second = companion.updateProduct(_product('Beans', '002'));
      a.complete(_brief(_product('Oats', '001')));
      await Future<void>.delayed(Duration.zero);
      b.complete(_brief(_product('Beans', '002')));
      await Future.wait([first, second]);
      expect(companion.briefing?.name, contains('Beans'));
      expect(
        assistant.messages
            .where((m) => m.text.contains('Briefing for'))
            .single
            .text,
        contains('Beans'),
      );
      companion.dispose();
      assistant.dispose();
    },
  );

  test('briefing speaks while recognition remains active', () async {
    final tts = _Tts();
    final speech = _Speech();
    final assistant = _assistant(speech: speech, tts: tts);
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) async => _brief(p),
    );
    await companion.start();
    await companion.listen();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await companion.updateProduct(_product('Oats', '001'));
    expect(assistant.messages, isNotEmpty);
    expect(speech.listening, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await companion.pause();
    expect(tts.speaks, 2, reason: 'the greeting and briefing are spoken');
    companion.dispose();
    assistant.dispose();
  });

  test('pending confirmation defers automatic briefing', () async {
    final assistant = _assistant();
    assistant.pendingAction = const AssistantAction(
      id: 'a',
      toolName: 'write',
      arguments: {},
      summary: 'Confirm?',
    );
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) async => _brief(p),
    );
    await companion.start();
    await companion.updateProduct(_product('Oats', '001'));
    expect(assistant.messages, isEmpty);
    expect(companion.briefing, isNotNull);
    companion.dispose();
    assistant.dispose();
  });

  test('start resumes a suspended foreground session and starts the mic after speech', () async {
    final tts = _Tts();
    final speech = _Speech();
    final assistant = _assistant(speech: speech, tts: tts);
    await assistant.suspend();
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) async => _brief(p),
    );
    await companion.start();
    await companion.updateProduct(_product('Oats', '001'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(tts.speaks, 2); // greeting and product briefing
    expect(speech.listening, isTrue);
    companion.dispose();
    assistant.dispose();
  });

  test(
    'briefing and follow-up remain in the shared assistant conversation',
    () async {
      final assistant = _assistant();
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) async => _brief(p),
      );
      await companion.start();
      await companion.updateProduct(_product('Oats', '001'));
      await companion.submit('Does this suit my diet?');
      expect(assistant.messages.first.text, startsWith('Briefing for Oats.'));
      expect(
        assistant.messages.map((m) => m.text),
        containsAll(['Does this suit my diet?', 'Answer.']),
      );
      expect(companion.reply?.text, 'Answer.');
      companion.dispose();
      assistant.dispose();
    },
  );

  test(
    'voice turn joins native final segments and waits for the response pause',
    () async {
      final speech = _Speech();
      final assistant = _assistant(speech: speech);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) async => _brief(p),
      );
      await companion.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(speech.results, hasLength(1));
      speech.emit(0, 'What ingredients are in it', isFinal: true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        speech.results,
        hasLength(2),
        reason: 'recognition reopens after a native end',
      );
      expect(
        assistant.messages,
        isEmpty,
        reason: 'a native final does not submit immediately',
      );
      speech.emit(1, 'Does it contain nuts', isFinal: true);
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(
        assistant.messages
            .where((message) => message.role == 'user')
            .single
            .text,
        'What ingredients are in it Does it contain nuts',
      );
      companion.dispose();
      assistant.dispose();
    },
  );
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
