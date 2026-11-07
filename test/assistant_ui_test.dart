import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/assistant/assistant_controller.dart';
import 'package:hackathon/assistant/assistant_models.dart';
import 'package:hackathon/assistant/assistant_page.dart';
import 'package:hackathon/assistant/assistant_settings_page.dart';
import 'package:hackathon/services/text_to_speech_service.dart';

class _FakeTts extends TextToSpeechService {
  @override
  Future<List<Map<String, String>>> getVoices() async => const [];
}

class _Data implements AssistantDataSource {
  AssistantSettings saved = const AssistantSettings();
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
  Future<AssistantSettings> loadSettings() async => saved;
  @override
  Future<void> saveSettings(AssistantSettings settings) async {
    saved = settings;
  }
}

void main() {
  testWidgets('assistant page exposes conversation, voice input and settings', (
    tester,
  ) async {
    final data = _Data()
      ..saved = const AssistantSettings(tone: 'Friendly coach');
    final controller = AssistantController(data: data, tts: _FakeTts())
      ..settings = const AssistantSettings(tone: 'Friendly coach');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AssistantPage(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.text('Hi, I’m Assistant'), findsOneWidget);
    expect(find.byTooltip('Start voice input'), findsOneWidget);
    expect(find.byTooltip('Assistant settings'), findsOneWidget);
    expect(find.byTooltip('New conversation'), findsOneWidget);
    expect(find.text('Ask about food, preferences…'), findsOneWidget);

    await tester.tap(find.byTooltip('Assistant settings'));
    await tester.pumpAndSettle();
    expect(find.text('Assistant personality'), findsOneWidget);
    expect(find.text('Friendly coach'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('assistant settings reset drafts and save preferences', (
    tester,
  ) async {
    final data = _Data()
      ..saved = const AssistantSettings(name: 'Luna', tone: 'Friendly coach');
    final controller = AssistantController(data: data, tts: _FakeTts())
      ..settings = data.saved;
    await tester.pumpWidget(
      MaterialApp(home: AssistantSettingsPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Luna'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('Assistant'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save settings'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(data.saved.name, 'Assistant');
    expect(data.saved.tone, 'Calm guide');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'assistant actions remain scrollable on a small keyboard layout',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      final controller = AssistantController(data: _Data(), tts: _FakeTts())
        ..pendingAction = AssistantAction(
          id: 'action-1',
          toolName: 'propose_food_log',
          arguments: {},
          summary: List.filled(30, 'Please confirm this change. ').join(),
        );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(body: AssistantPage(controller: controller)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Start voice input'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    },
  );
}
