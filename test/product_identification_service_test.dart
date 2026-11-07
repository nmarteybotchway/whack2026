import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/openrouter.dart';
import 'package:hackathon/scan/product_identification_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _productJson({String? gtin}) => {
  'status': 'identified',
  'product_name': 'Mini Chocolate Fingers',
  'brand': 'Cadbury',
  'variant': 'Milk Chocolate',
  'package_size': '114 g',
  'sku': null,
  'gtin': gtin,
  'confidence': 94,
  'product_name_confidence': 96,
  'brand_confidence': 99,
  'variant_confidence': 83,
  'sku_confidence': 0,
  'gtin_confidence': gtin == null ? 0 : 99,
  'evidence': ['Cadbury logo', 'Mini Fingers text', '114 g net weight'],
  'uncertainties': ['No seller SKU is printed on the visible packaging'],
};

void main() {
  test(
    'identifies the item and preserves unknown identifiers as null',
    () async {
      late http.Request sent;
      final service = ProductIdentificationService(
        openRouter: OpenRouterService(
          apiKey: 'test-key',
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': jsonEncode(_productJson())},
                  },
                ],
              }),
              200,
            );
          }),
        ),
      );
      addTearDown(service.close);

      final result = await service.identify(Uint8List.fromList([1, 2, 3]));

      expect(
        result.displayName,
        'Cadbury Mini Chocolate Fingers Milk Chocolate 114 g',
      );
      expect(result.sku, isNull);
      expect(result.gtin, isNull);
      expect(result.brandConfidence, 99);
      expect(result.uncertainties, contains(contains('SKU')));
      final request = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(request['model'], '@preset/glm-flash');
      expect(
        request['messages'][0]['content'][1]['image_url']['url'],
        'data:image/jpeg;base64,AQID',
      );
      final prompt = request['messages'][0]['content'][0]['text'] as String;
      expect(prompt, contains('Do not guess'));
      expect(prompt, contains('SKU is seller-specific'));
      expect(request['response_format']['json_schema']['strict'], isTrue);
    },
  );

  test('rejects a guessed or malformed barcode value', () async {
    final service = ProductIdentificationService(
      openRouter: OpenRouterService(
        apiKey: 'test-key',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(_productJson(gtin: 'unknown')),
                  },
                },
              ],
            }),
            200,
          ),
        ),
      ),
    );
    addTearDown(service.close);

    await expectLater(
      service.identify(Uint8List.fromList([1])),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('GTIN'),
        ),
      ),
    );
  });

  test('accepts a GTIN with a valid check digit', () async {
    final service = ProductIdentificationService(
      openRouter: OpenRouterService(
        apiKey: 'test-key',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(_productJson(gtin: '4006381333931')),
                  },
                },
              ],
            }),
            200,
          ),
        ),
      ),
    );
    addTearDown(service.close);

    final result = await service.identify(Uint8List.fromList([1]));
    expect(result.gtin, '4006381333931');
  });
}
