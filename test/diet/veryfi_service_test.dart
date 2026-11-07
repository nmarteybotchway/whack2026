import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/veryfi_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('maps Veryfi line items onto receipt items', () async {
    const responseBody = '''
    {"line_items": [
      {"description": "Whole Milk 1L", "price": 2.49, "qty": 1, "total": 2.49},
      {"description": "Yoghurt", "price": 1.2, "qty": 3, "total": 3.6},
      {"description": "No price item", "price": 0, "total": 0, "qty": 1},
      {"description": "", "price": 5.0, "qty": 1}
    ]}
    ''';
    final service = VeryfiService(
      client: MockClient((request) async => http.Response(responseBody, 200)),
    );

    final items = await service.processReceipt(
      Uint8List.fromList([1, 2, 3]),
      'r.jpg',
    );

    expect(items, hasLength(2));
    expect(items[0].name, 'Whole Milk 1L');
    expect(items[0].price, 2.49);
    expect(items[0].quantity, 1);
    expect(items[1].name, 'Yoghurt');
    expect(items[1].price, 1.2);
    expect(items[1].quantity, 3);
  });

  test('derives unit price from line total when price is missing', () async {
    const responseBody = '''
    {"line_items": [{"description": "Bread", "price": 0, "qty": 2, "total": 3.0}]}
    ''';
    final service = VeryfiService(
      client: MockClient((request) async => http.Response(responseBody, 200)),
    );

    final items = await service.processReceipt(Uint8List.fromList([1]), 'r.jpg');

    expect(items.single.price, closeTo(1.5, 0.001));
    expect(items.single.quantity, 2);
  });

  test('sends signed headers and base64 file data', () async {
    http.Request? captured;
    final service = VeryfiService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'line_items': []}), 200);
      }),
    );

    await service.processReceipt(Uint8List.fromList([9, 9, 9]), 'r.jpg');

    final request = captured!;
    expect(request.headers['Client-Id'], isNotEmpty);
    expect(request.headers['X-Veryfi-Date'], isNotEmpty);
    expect(request.headers['X-Veryfi-Signature'], isNotEmpty);
    expect(request.headers['Authorization'], startsWith('apikey '));
    final body = jsonDecode(request.body) as Map;
    expect(body['file_name'], 'r.jpg');
    expect(body['file_data'], base64Encode([9, 9, 9]));
  });

  test('throws VeryfiException on non-200 responses', () async {
    final service = VeryfiService(
      client: MockClient(
        (request) async =>
            http.Response(jsonEncode({'message': 'quota exceeded'}), 403),
      ),
    );

    await expectLater(
      service.processReceipt(Uint8List.fromList([1]), 'r.jpg'),
      throwsA(isA<VeryfiException>()),
    );
  });
}
