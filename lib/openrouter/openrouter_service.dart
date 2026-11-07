import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../secrets.dart';

/// A JPEG image to attach to a prompt.
///
/// The image is sent inline as a base64 `data:image/jpeg` URL, so callers
/// only supply the raw bytes.
class OpenRouterImage {
  /// Raw JPEG bytes.
  final Uint8List bytes;

  static const String mimeType = 'image/jpeg';

  /// Inline images inflate by a third when base64-encoded; keep requests
  /// comfortably small.
  static const int maxBytes = 10 * 1024 * 1024;

  const OpenRouterImage._(this.bytes);

  /// Creates a validated JPEG attachment.
  factory OpenRouterImage(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('OpenRouterImage bytes must not be empty.');
    }
    if (bytes.length > maxBytes) {
      throw ArgumentError(
        'OpenRouterImage is ${bytes.length} bytes; at most $maxBytes allowed.',
      );
    }
    return OpenRouterImage._(bytes);
  }

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

/// An error response from OpenRouter.
class OpenRouterException implements Exception {
  const OpenRouterException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'OpenRouterException($statusCode): $message';
}

/// A Flutter/Dart-native wrapper around the OpenRouter chat completions API.
///
/// A prompt (plus an optional [OpenRouterImage]) goes in and the model's text
/// comes out. Pass a JSON Schema as `responseSchema` to get structured JSON
/// back instead of free text.
class OpenRouterService {
  static final Uri _endpoint = Uri.parse(
    'https://openrouter.ai/api/v1/chat/completions',
  );

  final String _apiKey;
  final String model;
  final http.Client _client;

  /// Creates a service bound to [apiKey].
  ///
  /// [apiKey] defaults to `openRouterApiKey` from the git-ignored
  /// `lib/secrets.dart` (copy `lib/secrets.example.dart` to create it).
  /// [model] defaults to the `@preset/glm-flash` OpenRouter preset. [client]
  /// can be replaced in tests.
  OpenRouterService({
    this._apiKey = openRouterApiKey,
    this.model = '@preset/glm-flash',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Sends [prompt] (with an optional JPEG [image]) and returns the model's
  /// text response.
  ///
  /// If [responseSchema] (a JSON Schema object) is given, the model is asked
  /// to reply with JSON matching it, and the returned string is that JSON.
  Future<String> generate({
    required String prompt,
    Map<String, Object?>? responseSchema,
    OpenRouterImage? image,
  }) async {
    final content = image == null
        ? prompt
        : [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': image.dataUrl},
            },
          ];

    final response = await _client.post(
      _endpoint,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': content},
        ],
        if (responseSchema != null)
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'response',
              'strict': true,
              'schema': responseSchema,
            },
          },
      }),
    );

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 || body is! Map || body['error'] != null) {
      final error = body is Map ? body['error'] : null;
      throw OpenRouterException(
        error is Map
            ? error['code'] as int? ?? response.statusCode
            : response.statusCode,
        error is Map ? '${error['message']}' : response.body,
      );
    }

    final text = body['choices']?[0]?['message']?['content'];
    if (text is! String || text.isEmpty) {
      throw StateError('OpenRouter returned no text content.');
    }
    return text;
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
