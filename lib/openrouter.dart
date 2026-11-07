/// A Flutter/Dart-native wrapper for the OpenRouter API.
///
/// ```dart
/// import 'package:hackathon/openrouter.dart';
///
/// final service = OpenRouterService(); // key from lib/secrets.dart
/// final json = await service.generate(
///   prompt: 'What food is in this photo?',
///   responseSchema: {
///     'type': 'object',
///     'properties': {
///       'name': {'type': 'string'},
///       'score': {'type': 'integer'},
///     },
///     'required': ['name', 'score'],
///     'additionalProperties': false,
///   },
///   image: OpenRouterImage(jpegBytes),
/// );
/// ```
library;

export 'openrouter/openrouter_service.dart';
