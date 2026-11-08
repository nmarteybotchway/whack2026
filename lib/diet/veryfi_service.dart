import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../secrets.dart';
import 'receipt_parser.dart';

/// Recognises receipts with the Veryfi document-processing API and turns the
/// response into [ReceiptItem]s.
///
/// Veryfi does its own OCR plus understanding, so no local parsing is needed.
/// HTTP requests are signed per the Veryfi v8 API: HMAC-SHA256 of
/// "timestamp:filename" under HMAC signatures.
class VeryfiService {
  VeryfiService({http.Client? client, String? apiUrl})
    : _client = client ?? http.Client(),
      apiUrl = apiUrl ?? 'https://api.veryfi.com/api/v8/partner/documents/';

  static const _timestampHeader = 'X-Veryfi-Date';
  static const _signatureHeader = 'X-Veryfi-Signature';

  final http.Client _client;

  /// Overridable for tests and alternative API versions.
  final String apiUrl;

  /// Sends the JPEG [bytes] of a receipt photo and returns the items Veryfi
  /// read off it.
  Future<List<ReceiptItem>> processReceipt(
    Uint8List bytes,
    String filename,
  ) async {
    final timestamp =
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final response = await _client.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Client-Id': veryfiClientId,
        'Authorization': 'apikey $veryfiUsername:$veryfiApiKey',
        _timestampHeader: timestamp,
        _signatureHeader: _signature(timestamp, filename),
      },
      body: jsonEncode({
        'file_data': base64Encode(bytes),
        'file_name': filename,
      }),
    );

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    // Veryfi returns 201 Created on successful document processing.
    if (response.statusCode != 200 && response.statusCode != 201) {
      final message = body is Map
          ? (body['message'] ?? body['error'] ?? response.reasonPhrase)
          : response.reasonPhrase;
      throw VeryfiException(
        'Veryfi request failed (${response.statusCode}): $message',
      );
    }
    if (body is! Map) throw const VeryfiException('Unexpected Veryfi response.');
    return _itemsFromResponse(body);
  }

  String _signature(String timestamp, String filename) {
    final payload = utf8.encode('$timestamp:$filename');
    final key = utf8.encode(veryfiApiKey);
    return crypto.Hmac(crypto.sha256, key).convert(payload).toString();
  }

  /// Maps Veryfi's `line_items` array onto [ReceiptItem]s.
  ///
  /// In practice Veryfi often leaves `price` and `quantity` null and only fills
  /// `total`, so the line total is used as a single-quantity price then.
  List<ReceiptItem> _itemsFromResponse(Map<dynamic, dynamic> body) {
    final lineItems = body['line_items'];
    if (lineItems is! List) return const [];
    final items = <ReceiptItem>[];
    for (final raw in lineItems) {
      if (raw is! Map) continue;
      final name = (raw['description'] as String? ?? '')
          .replaceAll(_whitespace, ' ')
          .trim();
      if (name.isEmpty) continue;
      final price = _toDouble(raw['price']);
      final total = _toDouble(raw['total']);
      final quantity = _toDouble(raw['quantity']).round();
      if (price > 0) {
        items.add(ReceiptItem(
          name: name,
          price: price,
          quantity: quantity > 0 ? quantity : 1,
        ));
      } else if (total > 0) {
        // Only the line total is known: treat it as one purchase of that
        // amount rather than dropping the item.
        items.add(ReceiptItem(
          name: name,
          price: total,
          quantity: 1,
        ));
      }
    }
    return items;
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}

final _whitespace = RegExp(r'\s+');

class VeryfiException implements Exception {
  const VeryfiException(this.message);

  final String message;

  @override
  String toString() => message;
}
