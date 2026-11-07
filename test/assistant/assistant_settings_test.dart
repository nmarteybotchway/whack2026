import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/assistant/assistant_models.dart';

void main() {
  test('old or malformed stored personality falls back to usable defaults', () {
    final settings = AssistantSettings.fromMap({
      'name': '   ',
      'tone': 'unknown preset',
      'answerLength': 'infinite',
      'speechRate': double.nan,
      'instructions': 42,
      'locale': null,
    });
    expect(settings.name, 'Assistant');
    expect(settings.tone, 'Calm guide');
    expect(settings.answerLength, 'balanced');
    expect(settings.speechRate, .5);
    expect(settings.instructions, isEmpty);
    expect(settings.locale, 'en-GB');
  });

  test('stored personality stays within Firestore and device limits', () {
    final settings = AssistantSettings.fromMap({
      'name': 'a' * 100,
      'instructions': 'x' * 2000,
      'voiceName': 'v' * 300,
      'speechRate': 7,
    });
    expect(settings.name.length, 40);
    expect(settings.instructions.length, 1000);
    expect(settings.voiceName.length, 100);
    expect(settings.speechRate, .8);
  });

  test('a saved custom personality and voice survives reload', () {
    const original = AssistantSettings(
      name: 'Ari',
      tone: 'Friendly coach',
      answerLength: 'short',
      supportive: false,
      humor: true,
      instructions: 'Avoid emojis.',
      voiceEnabled: false,
      locale: 'en-US',
      voiceName: 'Example voice',
      speechRate: .4,
    );
    final reloaded = AssistantSettings.fromMap(original.toMap());
    expect(reloaded.toMap(), original.toMap());
    expect(reloaded.personalityPrompt, contains('Avoid emojis.'));
  });
}
