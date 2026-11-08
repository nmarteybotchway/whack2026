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

  final String apiKey;
  final String model;

  /// Model used instead of [model] when a response schema is given. The
  /// `glm-flash` preset drops `response_format`, so schema calls name the
  /// model directly and pin the preset's first provider themselves.
  final String structuredModel;
  final http.Client _client;

  /// Creates a service bound to [apiKey].
  ///
  /// [apiKey] defaults to `openRouterApiKey` from the git-ignored
  /// `lib/secrets.dart` (copy `lib/secrets.example.dart` to create it).
  /// [model] defaults to the `@preset/glm-flash` OpenRouter preset, and
  /// [structuredModel] to the GLM model behind it. [client] can be replaced
  /// in tests.
  OpenRouterService({
    this.apiKey = openRouterApiKey,
    this.model = '@preset/glm-flash',
    this.structuredModel = 'z-ai/glm-5.3-flash',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Sends [prompt] (with an optional JPEG [image]) and returns the model's
  /// text response.
  ///
  /// If [responseSchema] (a JSON Schema object) is given, the model is asked
  /// to reply with JSON matching it, and the returned string is that JSON.
  ///
  /// If [webSearch] is true, OpenRouter's web plugin adds live search results
  /// to the prompt (billed per request on top of the model's tokens). Such
  /// calls can take minutes, so raise [timeout] to match.
  Future<String> generate({
    required String prompt,
    Map<String, Object?>? responseSchema,
    OpenRouterImage? image,
    bool webSearch = false,
    Duration timeout = const Duration(seconds: 45),
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

    final response = await _client
        .post(
          _endpoint,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': responseSchema == null ? model : structuredModel,
            'messages': [
              {'role': 'user', 'content': content},
            ],
            if (webSearch)
              'plugins': [
                {'id': 'web'},
              ],
            if (responseSchema != null)
              'provider': {
                'order': ['GMICloud'],
                'require_parameters': true,
              },
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
        )
        .timeout(timeout);

    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw OpenRouterException(
        response.statusCode,
        'OpenRouter returned a non-JSON response.',
      );
    }
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

  /// Sends raw OpenAI-compatible chat messages and tool definitions. The
  /// returned assistant message may contain text, tool calls, or both.
  Future<Map<String, dynamic>> chat({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final response = await _client
        .post(
          _endpoint,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            if (tools.isNotEmpty) 'tools': tools,
          }),
        )
        .timeout(timeout);
    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw OpenRouterException(
        response.statusCode,
        'OpenRouter returned a non-JSON response.',
      );
    }
    if (response.statusCode != 200 || body is! Map || body['error'] != null) {
      final error = body is Map ? body['error'] : null;
      throw OpenRouterException(
        error is Map
            ? error['code'] as int? ?? response.statusCode
            : response.statusCode,
        error is Map ? '${error['message']}' : 'OpenRouter request failed.',
      );
    }
    final choices = body['choices'];
    final message =
        choices is List && choices.isNotEmpty && choices.first is Map
        ? choices.first['message']
        : null;
    if (message is! Map) {
      throw StateError('OpenRouter returned no assistant message.');
    }
    return Map<String, dynamic>.from(message);
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
