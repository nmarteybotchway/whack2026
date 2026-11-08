import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/assistant/assistant_controller.dart';
import 'package:hackathon/assistant/assistant_models.dart';
import 'package:hackathon/scan/product_identification_service.dart';
import 'package:hackathon/scan/shopping_companion_briefing.dart';
import 'package:hackathon/scan/shopping_companion_controller.dart';
import 'package:hackathon/scan/shopping_companion_overlay.dart';
import 'package:hackathon/services/speech_to_text_service.dart';
import 'package:hackathon/services/text_to_speech_service.dart';

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
  Future<Map<String, Object?>> confirm(AssistantAction action) async =>
      const {};
  @override
  Future<AssistantSettings> loadSettings() async =>
      const AssistantSettings(voiceEnabled: false);
  @override
  Future<void> saveSettings(AssistantSettings settings) async {}
}

class _FakeTts extends TextToSpeechService {
  @override
  Future<List<Map<String, String>>> getVoices() async => const [];
  @override
  Future<void> speak(String text, {String? locale}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
}

class _FakeSpeech extends SpeechToTextService {
  @override
  bool get isAvailable => true;

  @override
  Future<bool> initialize({void Function(String)? onError}) async => true;

  @override
  Future<bool> listen({
    required void Function(String text, bool finalResult) onResult,
    void Function(String status)? onStatus,
    String locale = 'en-GB',
  }) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

ProductIdentification _product() => const ProductIdentification(
  status: 'identified',
  productName: 'Porridge oats',
  brand: 'North Farm',
  variant: null,
  packageSize: '500 g',
  sku: null,
  gtin: '1234567890123',
  confidence: 95,
  productNameConfidence: 95,
  brandConfidence: 90,
  variantConfidence: 0,
  skuConfidence: 0,
  gtinConfidence: 100,
  evidence: ['front label'],
  uncertainties: [],
);

ShoppingCompanionController _coordinator({
  ProductBriefing Function(ProductIdentification)? briefing,
}) {
  final assistant = AssistantController(
    data: _Data(),
    speech: _FakeSpeech(),
    tts: _FakeTts(),
  );
  return ShoppingCompanionController(
    assistant: assistant,
    briefingLoader: (product) async =>
        briefing?.call(product) ??
        ProductBriefing(
          key: 'oats',
          name: product.displayName,
          text: 'This scanned food matches porridge oats.',
          alternatives: [
            const CompanionAlternative(
              name: 'Buckwheat flakes',
              detail: 'A suitable grain-free option.',
              image: AssistantImage(
                foodId: 'buckwheat_flakes',
                name: 'Buckwheat flakes',
                url: '',
                sourcePage: 'https://example.com/buckwheat',
              ),
            ),
          ],
        ),
  );
}

void main() {
  testWidgets(
    'answer and voice status stays visible while microphone is open',
    (tester) async {
      final coordinator = _coordinator();
      await coordinator.start();
      coordinator.assistant.listening = true;
      coordinator.assistant.busy = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShoppingCompanionOverlay(controller: coordinator),
          ),
        ),
      );
      expect(find.text('Working on your answer…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      coordinator.assistant.busy = false;
      coordinator.assistant.speaking = true;
      coordinator.assistant.preparingSpeech = true;
      coordinator.setDraft('');
      await tester.pump();
      expect(find.text('Preparing voice…'), findsOneWidget);
      coordinator.assistant.preparingSpeech = false;
      coordinator.setDraft('');
      await tester.pump();
      expect(find.text('Speaking — tap mic to interrupt'), findsOneWidget);
      expect(find.byKey(const ValueKey('companion-mic')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await coordinator.stop();
      coordinator.dispose();
      coordinator.assistant.dispose();
    },
  );

  testWidgets('starts explicitly and waits for a scan before questions', (
    tester,
  ) async {
    final coordinator = _coordinator();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShoppingCompanionOverlay(controller: coordinator)),
      ),
    );
    expect(find.text('Voice shopping companion'), findsOneWidget);
    expect(find.text('Start voice chat'), findsOneWidget);

    await tester.tap(find.text('Start voice chat'));
    await tester.pumpAndSettle();
    expect(find.text('Listening — speak naturally'), findsOneWidget);
    expect(
      find.text(
        'Talk naturally to ask a question. Scan a product for a tailored briefing.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('companion-mic')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Show alternatives'),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('companion-mic')), findsOneWidget);
    expect(find.byTooltip('Stop shopping companion'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse companion'));
    await tester.pump();
    expect(find.byKey(const ValueKey('companion-mic')), findsOneWidget);
    expect(find.byTooltip('Stop shopping companion'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await coordinator.stop();
    coordinator.dispose();
    coordinator.assistant.dispose();
  });

  testWidgets('speech failure offers a visible retry while collapsed', (
    tester,
  ) async {
    final coordinator = _coordinator();
    await coordinator.start();
    coordinator.assistant.speechError = 'Speech output failed';
    coordinator.setDraft('');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShoppingCompanionOverlay(controller: coordinator)),
      ),
    );

    expect(find.text('Speech output failed'), findsOneWidget);
    expect(find.text('Retry speech'), findsOneWidget);
    expect(find.byKey(const ValueKey('companion-mic')), findsOneWidget);
    expect(find.byTooltip('Stop shopping companion'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await coordinator.stop();
    coordinator.dispose();
    coordinator.assistant.dispose();
  });

  testWidgets('shows briefing, alternatives, reply and scan details action', (
    tester,
  ) async {
    var detailsOpened = false;
    final coordinator = _coordinator();
    await coordinator.start();
    await coordinator.updateProduct(_product());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingCompanionOverlay(
            controller: coordinator,
            onShowDetails: () => detailsOpened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand companion'));
    await tester.pumpAndSettle();

    expect(find.text('North Farm Porridge oats 500 g'), findsOneWidget);
    // No model is reachable here, so the fallback wording is the reply and
    // the alternative is shown once, on the product card.
    expect(find.text('Buckwheat flakes'), findsOneWidget);
    expect(find.text('A suitable grain-free option.'), findsOneWidget);
    expect(
      find.textContaining(
        'This scanned food matches porridge oats.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Show scan details'));
    expect(detailsOpened, isTrue);

    await tester.pumpWidget(const SizedBox());
    await coordinator.stop();
    coordinator.dispose();
    coordinator.assistant.dispose();
  });

  testWidgets('panel content scrolls within a small keyboard camera view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    final coordinator = _coordinator(
      briefing: (product) => ProductBriefing(
        key: 'oats',
        name: product.displayName,
        text: List.filled(10, 'Detailed product information. ').join(),
        alternatives: List.generate(
          3,
          (i) => CompanionAlternative(
            name: 'Alternative ${i + 1}',
            detail: List.filled(
              4,
              'An explanation for this alternative. ',
            ).join(),
          ),
        ),
      ),
    );
    await coordinator.start();
    await coordinator.updateProduct(_product());
    coordinator.assistant.pendingAction = AssistantAction(
      id: 'action-1',
      toolName: 'propose_food_log',
      arguments: const {},
      summary: List.filled(25, 'Please confirm this proposed change. ').join(),
    );
    coordinator.assistant.committing = true;
    await coordinator.start(); // Notify the overlay of the pending write.

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              Positioned(
                left: 8,
                right: 8,
                bottom: 0,
                child: ShoppingCompanionOverlay(controller: coordinator),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Expand companion'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Confirm this change?'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(const SizedBox());
    await coordinator.stop();
    coordinator.dispose();
    coordinator.assistant.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
}
