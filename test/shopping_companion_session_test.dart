import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background interruption retains draft, product and active session',
    () async {
      final assistant = _assistant();
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) async => _brief(p),
      );
      await companion.start();
      await companion.updateProduct(_product('Oats', '001'));
      companion.setDraft('Is this suitable');
      final messageCount = assistant.messages.length;
      await companion.suspendForBackground();
      expect(companion.active, isTrue);
      expect(companion.draft, 'Is this suitable');
      expect(companion.briefing, isNotNull);
      expect(assistant.messages.length, messageCount);
      expect(assistant.listening, isFalse);
      await companion.resumeFromBackground();
      expect(companion.draft, 'Is this suitable');
      expect(companion.active, isTrue);
      await _dispose(companion, assistant);
    },
  );

  test(
    'conversation and draft recover after recreation and stay user scoped',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = _assistant(sessionKey: 'alice');
      await first.initialize();
      first.setInputDraft('unfinished question');
      first.setShoppingDraft('unfinished spoken question');
      await first.send('What should I eat?');
      await first.saveSession();
      final texts = first.messages.map((m) => m.text).toList();
      first.dispose();
      final restored = _assistant(sessionKey: 'alice');
      await restored.initialize();
      expect(restored.messages.map((m) => m.text), texts);
      expect(restored.inputDraft, 'unfinished question');
      expect(restored.shoppingDraft, 'unfinished spoken question');
      expect(restored.pendingAction, isNull);
      final other = _assistant(sessionKey: 'bob');
      await other.initialize();
      expect(other.messages, isEmpty);
      expect(other.inputDraft, isEmpty);
      await restored.clear();
      await restored.saveSession();
      final cleared = _assistant(sessionKey: 'alice');
      await cleared.initialize();
      expect(cleared.messages, isEmpty);
      expect(cleared.inputDraft, isEmpty);
      restored.dispose();
      other.dispose();
      cleared.dispose();
    },
  );

  test(
    'cached scan waits for saved voice settings after opening camera',
    () async {
      for (final voiceEnabled in [false, true]) {
        final settingsLoaded = Completer<AssistantSettings>();
        final tts = _Tts();
        final assistant = _assistant(
          tts: tts,
          data: _Data(settingsLoaded: settingsLoaded),
        );
        await assistant.suspend(); // Home pauses audio before pushing ScanPage.
        final companion = ShoppingCompanionController(
          assistant: assistant,
          briefingLoader: (product) async => _brief(product),
        );
        var handedOff = false;
        companion.addListener(() {
          if (companion.active && !handedOff) {
            handedOff = true;
            unawaited(companion.updateProduct(_product('Oats', '001')));
          }
        });
        final starting = companion.start();
        await _flush();
        expect(tts.spoken, isEmpty);
        settingsLoaded.complete(AssistantSettings(voiceEnabled: voiceEnabled));
        await starting;
        await _flush();
        expect(tts.spoken, hasLength(2));
        expect(assistant.messages, hasLength(1));
        await _dispose(companion, assistant);
      }
    },
  );

  test(
    'same product across capture transitions speaks once per cooldown',
    () async {
      var now = DateTime(2026, 11, 8);
      final tts = _Tts();
      final assistant = _assistant(tts: tts);
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) async => _brief(p),
        now: () => now,
      );
      final a = _product('Oats', '001');
      await companion.start();
      await companion.scanning();
      await companion.updateProduct(a);
      await _flush();
      expect(tts.spoken, hasLength(2)); // session greeting + product briefing

      await companion.scanning();
      await companion.updateProduct(a);
      await _flush();
      expect(tts.spoken, hasLength(2));

      now = now.add(const Duration(seconds: 61));
      await companion.scanning();
      await companion.updateProduct(a);
      await _flush();
      expect(tts.spoken, hasLength(3));
      await _dispose(companion, assistant);
    },
  );

  test(
    'unknown product clears prior reply without inventing a safe result',
    () async {
      final assistant = _assistant();
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) async => _brief(p),
      );
      await companion.start();
      await companion.updateProduct(_product('Oats', '001'));
      expect(companion.reply, isNotNull);
      await companion.updateProduct(null);
      expect(companion.reply, isNull);
      expect(companion.briefing, isNull);
      expect(
        assistant.messages.any((m) => m.text.contains('Oats')),
        isTrue,
        reason: 'historical shared conversation remains available',
      );
      await _dispose(companion, assistant);
    },
  );

  test('late A briefing cannot replace or speak after B arrives', () async {
    final tts = _Tts();
    final assistant = _assistant(tts: tts);
    final a = Completer<ProductBriefing>();
    final b = Completer<ProductBriefing>();
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) => p.productName == 'A' ? a.future : b.future,
    );
    await companion.start();
    final loadA = companion.updateProduct(_product('A', '001'));
    await _flush();
    final loadB = companion.updateProduct(_product('B', '002'));
    a.complete(_brief(_product('A', '001')));
    await _flush();
    b.complete(_brief(_product('B', '002')));
    await Future.wait([loadA, loadB]);
    await _flush();
    expect(companion.briefing?.name, contains('B'));
    expect(
      assistant.messages
          .where((m) => m.text.contains('Briefing for'))
          .map((m) => m.text),
      ['Briefing for B.'],
    );
    expect(tts.spoken, [
      'Hi, I’m your shopping companion. Ask me about a product, its ingredients, or suitable alternatives.',
      'Briefing for B.',
    ]);
    await _dispose(companion, assistant);
  });

  test(
    'pause during briefing drops late completion and preserves conversation',
    () async {
      final tts = _Tts();
      final assistant = _assistant(tts: tts);
      await assistant.announceCameraBriefing(
        text: 'Earlier shared message.',
        product: const {'name': 'Previous'},
      );
      final delayed = Completer<ProductBriefing>();
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (_) => delayed.future,
      );
      await companion.start();
      final load = companion.updateProduct(_product('A', '001'));
      await _flush();
      await companion.pause();
      delayed.complete(_brief(_product('A', '001')));
      await load;
      await _flush();
      expect(assistant.messages.map((m) => m.text), [
        'Earlier shared message.',
      ]);
      expect(tts.spoken, [
        'Hi, I’m your shopping companion. Ask me about a product, its ingredients, or suitable alternatives.',
      ]);
      await _dispose(companion, assistant);
    },
  );

  test(
    'backgrounding during a reply keeps the turn without background speech',
    () async {
      final summary = Completer<Map<String, Object?>>();
      final tts = _Tts();
      final assistant = _assistant(
        tts: tts,
        data: _Data(summaryLoaded: summary),
      );
      final companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: (p) async => _brief(p),
      );
      await companion.start();
      final submission = companion.submit('What should I eat?');
      await _flush();
      expect(assistant.busy, isTrue);
      await companion.suspendForBackground();
      expect(assistant.busy, isTrue);
      summary.complete({});
      await submission;
      expect(
        assistant.messages.map((m) => m.text),
        containsAll(['What should I eat?', 'A grounded answer.']),
      );
      expect(
        tts.spoken,
        hasLength(1),
        reason: 'only the initial greeting should play',
      );
      await companion.resumeFromBackground();
      expect(
        tts.spoken,
        hasLength(1),
        reason: 'resuming must not repeat the greeting',
      );
      await _dispose(companion, assistant);
    },
  );

  test('scan snapshot preserves product details', () {
    final original = _product('Oats', '001');
    final restored = ProductIdentification.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.displayName, original.displayName);
    expect(restored.gtin, original.gtin);
    expect(restored.confidence, original.confidence);
    expect(restored.productNameConfidence, original.productNameConfidence);
    expect(restored.evidence, original.evidence);
  });

  test('general question works before a product is selected', () async {
    final assistant = _assistant();
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) async => _brief(p),
    );
    await companion.start();
    await companion.submit('What can you help with?');
    expect(
      assistant.messages.map((m) => m.text),
      containsAll(['What can you help with?', 'A grounded answer.']),
    );
    expect(companion.reply?.text, 'A grounded answer.');
    await _dispose(companion, assistant);
  });

  test('queued briefing waits for editable draft and pending action', () async {
    final assistant = _assistant();
    final companion = ShoppingCompanionController(
      assistant: assistant,
      briefingLoader: (p) async => _brief(p),
    );
    await companion.start();
    companion.setDraft('I am still typing');
    await companion.updateProduct(_product('A', '001'));
    expect(assistant.messages, isEmpty);

    companion.setDraft('');
    await _flush();
    expect(
      assistant.messages.map((m) => m.text),
      contains('Briefing for A.'),
      reason:
          'the queued summary should resume when the editable draft is cleared',
    );

    assistant.pendingAction = const AssistantAction(
      id: 'pending',
      toolName: 'propose_food_log',
      arguments: {},
      summary: 'Confirm log',
    );
    await companion.updateProduct(_product('B', '002'));
    expect(
      assistant.messages.map((m) => m.text),
      isNot(contains('Briefing for B.')),
    );
    await assistant.cancelAction();
    await _flush();
    expect(
      assistant.messages.map((m) => m.text),
      containsAll(['Briefing for A.', 'Briefing for B.']),
    );
    await _dispose(companion, assistant);
  });
}

class _Data implements AssistantDataSource {
  _Data({this.settingsLoaded, this.summaryLoaded});
  final Completer<Map<String, Object?>>? summaryLoaded;
  final Completer<AssistantSettings>? settingsLoaded;
  @override
  List<Map<String, Object?>> get tools => const [];
  @override
  Future<Map<String, Object?>> summary() async =>
      summaryLoaded?.future ?? const {};
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
      settingsLoaded?.future ?? const AssistantSettings(voiceEnabled: true);
  @override
  Future<void> saveSettings(AssistantSettings settings) async {}
}

class _Speech extends SpeechToTextService {
  @override
  bool get isAvailable => true;
  @override
  Future<bool> initialize({void Function(String)? onError}) async => true;
  @override
  Future<bool> listen({
    required void Function(String, bool) onResult,
    void Function(String)? onStatus,
    String locale = 'en-GB',
  }) async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class _Tts extends TextToSpeechService {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, {String? locale}) async => spoken.add(text);
  @override
  Future<void> stop() async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVoice(String name, String locale) async {}
  @override
  Future<List<Map<String, String>>> getVoices() async => const [];
}

AssistantController _assistant({_Tts? tts, _Data? data, String? sessionKey}) =>
    AssistantController(
      sessionKey: sessionKey,
      data: data ?? _Data(),
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
      speech: _Speech(),
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
);

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _dispose(
  ShoppingCompanionController companion,
  AssistantController assistant,
) async {
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
