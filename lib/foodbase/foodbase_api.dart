import 'dart:convert';

import 'package:http/http.dart' as http;

/// FoodBase rejected the request or returned an unexpected response.
class FoodBaseException implements Exception {
  const FoodBaseException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'FoodBaseException${statusCode == null ? '' : ' ($statusCode)'}: $message';
}

/// Identifies a packaged food using FoodBase's product-photo endpoint.
///
/// Pass bytes from a camera/gallery XFile without depending on dart:io:
/// ```dart
/// final result = await identifyFoodProduct(
///   imageBytes: await photo.readAsBytes(),
///   filename: photo.name,
///   apiKey: foodBaseApiKey,
/// );
/// ```
/// Returns the API's JSON object unchanged. Throws [ArgumentError] for empty
/// inputs, [FoodBaseException] for HTTP/response errors, or a transport/timeout
/// exception when the request cannot complete. No automatic retries are made.
/// Keep the API key outside version control. A supplied [client] remains owned
/// by the caller; otherwise this function creates and closes its own client.
Future<Map<String, dynamic>> identifyFoodProduct({
  required List<int> imageBytes,
  required String filename,
  required String apiKey,
  Duration timeout = const Duration(seconds: 60),
  http.Client? client,
}) async {
  if (imageBytes.isEmpty) throw ArgumentError('Image must not be empty.');
  if (filename.trim().isEmpty) {
    throw ArgumentError('Filename must not be empty.');
  }
  if (apiKey.trim().isEmpty) {
    throw ArgumentError('FoodBase API key is required.');
  }
  if (timeout <= Duration.zero) {
    throw ArgumentError('Timeout must be positive.');
  }

  final request =
      http.MultipartRequest(
          'POST',
          Uri.parse('https://foodbase.dev/v1/vision/product'),
        )
        ..headers['X-API-Key'] = apiKey.trim()
        ..files.add(
          http.MultipartFile.fromBytes('image', imageBytes, filename: filename),
        );

  final transport = client ?? http.Client();
  try {
    final response = await (() async {
      final streamed = await transport.send(request);
      return http.Response.fromStream(streamed);
    })().timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Avoid echoing uploaded content or credentials from a response body.
      throw FoodBaseException(
        'Product recognition request failed.',
        statusCode: response.statusCode,
      );
    }

    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw FoodBaseException('FoodBase returned invalid JSON.');
    }
    if (body is! Map<String, dynamic>) {
      throw FoodBaseException('FoodBase returned an unexpected JSON format.');
    }
    return body;
  } finally {
    if (client == null) transport.close();
  }
}
