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
    return true;
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
    client: client ?? MockClient((_) async => _response('Answer.')),
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
  alternatives: const [
    CompanionAlternative(
      name: 'Other option',
      detail: 'has fewer known conflicts',
    ),
  ],
);

void main() {
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

  test('pause discards a deferred briefing and prevents speech', () async {
    final tts = _Tts();
    final speech = _Speech();
    final assistant = _assistant(speech: speech, tts: tts);
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) async => _brief(p),
    );
    await companion.start();
    await companion.listen();
    await companion.updateProduct(_product('Oats', '001'));
    expect(
      assistant.messages,
      isEmpty,
      reason: 'announcement waits while microphone is active',
    );
    await companion.pause();
    expect(assistant.messages, isEmpty);
    expect(tts.speaks, 0);
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

  test(
    'start resumes a suspended foreground session without starting the mic',
    () async {
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
      await Future<void>.delayed(Duration.zero);
      expect(tts.speaks, 1);
      expect(speech.listening, isFalse);
      companion.dispose();
      assistant.dispose();
    },
  );

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
}
