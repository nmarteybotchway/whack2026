import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

/// A JPEG image to attach to a prompt.
///
/// The data contract fixes the image type to JPEG (`image/jpeg`) — the format
/// cameras and `ImagePicker` produce by default, and one Gemini supports
/// natively. Callers only supply the raw bytes; the MIME type is implied.
class GeminiImage {
  /// Raw JPEG bytes.
  final Uint8List bytes;

  /// Fixed by the data contract; Gemini accepts JPEG without preprocessing.
  static const String mimeType = 'image/jpeg';

  /// Inline (base64) requests are capped at 20 MB total by the Gemini API;
  /// leave headroom for the prompt text itself.
  static const int maxBytes = 19 * 1024 * 1024;

  const GeminiImage._(this.bytes);

  /// Creates a validated JPEG attachment.
  factory GeminiImage(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('GeminiImage bytes must not be empty.');
    }
    if (bytes.length > maxBytes) {
      throw ArgumentError(
        'GeminiImage is ${bytes.length} bytes; the contract allows at most '
        '$maxBytes bytes (Gemini caps inline requests at 20 MB total).',
      );
    }
    return GeminiImage._(bytes);
  }
}

/// A Flutter/Dart-native wrapper service around Google Gemini.
///
/// Simplified I/O: a prompt (plus an optional [GeminiImage]) goes in, and a
/// text response shaped by a mandatory [Schema] comes out. The schema is
/// applied on every call (`responseMimeType: 'application/json'`), so the
/// output shape — natural-language fields or structured JSON — is declared
/// once per prompt by the caller.
class GeminiService {
  final GenerativeModel _model;

  /// Creates a service bound to [apiKey].
  ///
  /// [model] defaults to `gemini-3.8-flash`; override for other Gemini
  /// variants. The key is typically injected with
  /// `--dart-define=GEMINI_API_KEY=...` and read via
  /// `String.fromEnvironment('GEMINI_API_KEY')` — never commit it.
  ///
  /// [client] overrides the underlying [GenerativeModel]; used by tests to
  /// inject a mock HTTP transport instead of calling the real API.
  GeminiService({
    required String apiKey,
    String model = 'gemini-3.8-flash',
    GenerativeModel? client,
  }) : _model =
            client ?? GenerativeModel(model: model, apiKey: apiKey);

  /// Sends [prompt] (with an optional JPEG [image]) to Gemini and returns the
  /// model's text response, constrained to [responseSchema].
  ///
  /// [responseSchema] is mandatory: callers always declare the output shape.
  /// Use `Schema.object(properties: {...})` for structured JSON, or a
  /// single-property object with a descriptive field for natural-language
  /// output.
  Future<String> generate({
    required String prompt,
    required Schema responseSchema,
    GeminiImage? image,
  }) async {
    final content = image == null
        ? Content.text(prompt)
        : Content.multi([
            TextPart(prompt),
            DataPart(GeminiImage.mimeType, image.bytes),
          ]);

    final response = await _model.generateContent(
      [content],
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: responseSchema,
      ),
    );

    return response.text ??
        (throw StateError(
          'Gemini returned no text content (prompt: "${prompt.trim().substring(0, prompt.trim().length.clamp(0, 60))}...").',
        ));
  }
}
