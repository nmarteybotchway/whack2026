import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/tesco/tesco_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _product(String id, {bool marketplace = false}) => {
  '__typename': marketplace ? 'MPProduct' : 'ProductType',
  'id': id,
  'title': 'Product $id',
  'gtin': '0500000000$id',
  'superDepartmentName': marketplace ? 'Marketplace' : 'Groceries & Essentials',
  'departmentName': 'Bakery',
  'price': {'actual': 1.5, 'unitPrice': 3.0, 'unitOfMeasure': 'kg'},
  'foodIcons': ['Suitable for Vegans'],
};

Map<String, dynamic> _page(int total, List<Map<String, dynamic>> products) => {
  'data': {
    'category': {
      'info': {'total': total},
      'results': [
        for (final p in products) {'node': p},
      ],
    },
  },
};

TescoApi _api(MockClientHandler handler) => TescoApi(
  client: MockClient(handler),
  requestDelay: Duration.zero,
  pageSize: 2,
);

void main() {
  group('TescoStoreDirectory', () {
    final directory = TescoStoreDirectory.parse(
      jsonEncode([
        {
          'branchNumber': '1',
          'name': 'Far Extra',
          'format': 'Extra',
          'latitude': 53.0,
          'longitude': -1.5,
        },
        {
          'branchNumber': '2',
          'name': 'Near Express',
          'format': 'Express',
          'latitude': 52.39,
          'longitude': -1.56,
        },
        {'branchNumber': '3', 'name': 'No coordinates'},
      ]),
    );

    test('orders stores by distance and skips ones without coordinates', () {
      final nearest = directory.nearest(52.385, -1.565);
      expect(nearest.map((s) => s.branchNumber), ['2', '1']);
      expect(nearest.first.distanceMiles, closeTo(0.4, 0.1));
      expect(nearest.last.distanceMiles, closeTo(42, 1));
    });

    test('filters by store format', () {
      final nearest = directory.nearest(52.385, -1.565, formats: {'Extra'});
      expect(nearest.single.name, 'Far Extra');
    });
  });

  test('geocode parses lat,lng and falls back to place search', () async {
    final requested = <String>[];
    final api = _api((request) async {
      requested.add(request.url.path);
      if (request.url.path.startsWith('/postcodes/')) {
        return _json({'status': 404, 'error': 'Invalid postcode'}, 404);
      }
      return _json({
        'result': [
          {'latitude': 52.34, 'longitude': -1.58},
        ],
      });
    });

    expect(await api.geocode(' 52.1, -1.2 '), (52.1, -1.2));
    expect(requested, isEmpty);
    expect(await api.geocode('Kenilworth'), (52.34, -1.58));
    expect(requested, ['/postcodes/Kenilworth', '/places']);
  });

  test('pages through a category, de-duplicating and dropping marketplace '
      'items', () async {
    final pages = [
      _page(4, [_product('1'), _product('2', marketplace: true)]),
      // Sponsored repeat of product 1.
      _page(4, [_product('1'), _product('3'), _product('4')]),
    ];
    var calls = 0;
    final api = _api((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.headers['x-apikey'], isNotEmpty);
      expect(body['variables']['page'], calls + 1);
      return _json(pages[calls++]);
    });

    final products = await api.fetchCategory(
      const TescoCategory(id: 'b;x', name: 'Bakery'),
    );

    expect(calls, 2);
    expect(products.map((p) => p.id), ['1', '3', '4']);
    expect(products.first.price, 1.5);
    expect(products.first.foodIcons, ['Suitable for Vegans']);
  });

  test('splits capped departments into aisles', () async {
    final facets = <String>[];
    final api = _api((request) async {
      final facet =
          (jsonDecode(request.body) as Map)['variables']['facet'] as String;
      facets.add(facet);
      return _json(switch (facet) {
        'dept' => _page(TescoApi.resultCap, [_product('1'), _product('2')]),
        'aisle-a' => _page(1, [_product('1')]),
        _ => _page(1, [_product('5')]),
      });
    });

    final products = await api.fetchCategory(
      const TescoCategory(
        id: 'dept',
        name: 'Drinks',
        children: [
          TescoCategory(id: 'aisle-a', name: 'Water'),
          TescoCategory(id: 'aisle-b', name: 'Wine'),
        ],
      ),
    );

    expect(facets, ['dept', 'aisle-a', 'aisle-b']);
    expect(products.map((p) => p.id), ['1', '5']);
  });

  test('retries after rate limiting', () async {
    var calls = 0;
    final api = TescoApi(
      client: MockClient((request) async {
        calls++;
        if (calls == 1) {
          return _json({
            'errors': [
              {'message': 'Too many requests'},
            ],
          });
        }
        return _json({
          'data': {
            'product': {
              'id': '9',
              'details': {
                'ingredients': ['Flour', 'Water'],
                'allergens': [
                  {
                    'name': 'Other Allergen Info',
                    'values': ['May contain Soya.'],
                  },
                ],
                'nutrition': [
                  {'name': 'Typical Values', 'value1': 'Per 100g'},
                  {'name': 'Energy kcal', 'value1': '272'},
                ],
              },
            },
          },
        });
      }),
      maxRetries: 1,
    );

    final details = await api.fetchDetails('9');

    expect(calls, 2);
    expect(details!.ingredients, ['Flour', 'Water']);
    expect(details.allergens['Other Allergen Info'], ['May contain Soya.']);
    expect(details.nutrition[1], ['Energy kcal', '272']);
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('fetchDetails returns null for unknown products', () async {
    final api = _api(
      (_) async => _json({
        'errors': [
          {
            'message': 'product-not-found',
            'extensions': {
              'http': {'status': 404},
            },
          },
        ],
        'data': {'product': null},
      }),
    );
    expect(await api.fetchDetails('0'), isNull);
  });
}
