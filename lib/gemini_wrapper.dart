/// A Flutter/Dart-native wrapper service for Google Gemini.
///
/// Import it as:
///
/// ```dart
/// import 'package:hackathon/gemini_wrapper.dart';
/// ```
///
/// then:
///
/// ```dart
/// final service = GeminiService(); // key from lib/secrets.dart
/// final answer = await service.generate(
///   prompt: 'Classify this receipt image.',
///   responseSchema: Schema.object(properties: {
///     'merchant': Schema.string(description: 'Merchant name as printed.'),
///     'total': Schema.number(description: 'Total amount as a number.'),
///   }),
///   image: GeminiImage(jpegBytes),
/// );
/// ```
library;

export 'gemini_wrapper/gemini_service.dart';
export 'package:google_generative_ai/google_generative_ai.dart'
    show Schema;
