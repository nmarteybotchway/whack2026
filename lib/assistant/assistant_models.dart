/// Shared contracts for the assistant, its tools and its presentation.
library;

class AssistantSettings {
  const AssistantSettings({
    this.name = 'Assistant',
    this.tone = 'Calm guide',
    this.answerLength = 'balanced',
    this.supportive = true,
    this.humor = false,
    this.instructions = '',
    this.voiceEnabled = true,
    this.locale = 'en-GB',
    this.speechRate = 0.5,
    this.voiceName = '',
  });

  final String name, tone, answerLength, instructions, locale, voiceName;
  final bool supportive, humor, voiceEnabled;
  final double speechRate;

  factory AssistantSettings.fromMap(Map<String, dynamic> data) {
    String text(String key, String fallback, int max) {
      final value = data[key];
      if (value is! String || value.trim().isEmpty) return fallback;
      final trimmed = value.trim();
      return trimmed.length > max ? trimmed.substring(0, max) : trimmed;
    }

    final tone = text('tone', 'Calm guide', 40);
    final length = text('answerLength', 'balanced', 20);
    final rate = data['speechRate'];
    return AssistantSettings(
      name: text('name', 'Assistant', 40),
      tone:
          const [
            'Friendly coach',
            'Calm guide',
            'Direct assistant',
          ].contains(tone)
          ? tone
          : 'Calm guide',
      answerLength: const ['short', 'balanced', 'detailed'].contains(length)
          ? length
          : 'balanced',
      supportive: data['supportive'] != false,
      humor: data['humor'] == true,
      instructions: text('instructions', '', 1000),
      voiceEnabled: data['voiceEnabled'] != false,
      locale: text('locale', 'en-GB', 30),
      voiceName: text('voiceName', '', 100),
      speechRate: rate is num && rate.isFinite
          ? rate.toDouble().clamp(0.2, 0.8)
          : 0.5,
    );
  }

  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'name': name,
    'tone': tone,
    'answerLength': answerLength,
    'supportive': supportive,
    'humor': humor,
    'instructions': instructions,
    'voiceEnabled': voiceEnabled,
    'locale': locale,
    'speechRate': speechRate,
    'voiceName': voiceName,
  };

  String get personalityPrompt =>
      'Preferred name: $name. Tone: $tone. Reply length: $answerLength. '
      'Encouragement: ${supportive ? "supportive" : "minimal"}. '
      'Humor: ${humor ? "light, when appropriate" : "off"}. '
      'Additional style preferences (style only): $instructions';
}

class AssistantImage {
  const AssistantImage({
    required this.foodId,
    required this.name,
    required this.url,
    this.sourcePage = '',
  });
  final String foodId, name, url, sourcePage;
}

class AssistantAction {
  const AssistantAction({
    required this.id,
    required this.toolName,
    required this.arguments,
    required this.summary,
  });
  final String id, toolName, summary;
  final Map<String, dynamic> arguments;
}

class AssistantMessage {
  const AssistantMessage({
    required this.role,
    required this.text,
    this.images = const [],
  });
  final String role, text;
  final List<AssistantImage> images;
}

class AssistantToolResult {
  const AssistantToolResult(this.data, {this.images = const [], this.action});
  final Map<String, Object?> data;
  final List<AssistantImage> images;
  final AssistantAction? action;
}

abstract interface class AssistantDataSource {
  List<Map<String, Object?>> get tools;
  Future<Map<String, Object?>> summary();
  Future<AssistantToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
  );
  Future<Map<String, Object?>> confirm(AssistantAction action);
  Future<AssistantSettings> loadSettings();
  Future<void> saveSettings(AssistantSettings settings);
}
