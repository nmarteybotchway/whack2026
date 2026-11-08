import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/food/food_recommendation_service.dart';
import 'package:hackathon/food/nutrient.dart';
import 'package:hackathon/food/preference.dart';
import 'package:hackathon/scan/product_identification_service.dart';
import 'package:hackathon/scan/shopping_companion_briefing.dart';

void main() {
  group('productKeyFor', () {
    test('GTIN identity is stable across product variants', () {
      final a = _product(variant: 'Original', gtin: '0123456789012');
      final b = _product(variant: 'Vanilla', gtin: '0123456789012');
      expect(productKeyFor(a), 'gtin:0123456789012');
      expect(productKeyFor(b), productKeyFor(a));
    });

    test('fallback key distinguishes normalized product variants', () {
      final a = _product(brand: 'Acme', variant: 'Original');
      final b = _product(brand: 'Acme', variant: 'Vanilla');
      expect(productKeyFor(a), contains('brand:acme'));
      expect(productKeyFor(a), isNot(productKeyFor(b)));
    });
  });

  group('ProductBriefingService', () {
    test('unknown catalog item is not described as suitable', () async {
      final service = ProductBriefingService(
        userId: 'uid',
        recommendations: _Recommendations({
          'Oat drink': const FoodRecommendation(
            food: 'Oat drink',
            found: false,
          ),
        }),
      );
      final result = await service.describe(_product());
      expect(result.text, contains('can’t assess its suitability'));
      expect(result.alternatives, isEmpty);
    });

    test(
      'ambiguous match stays qualified even with no known conflicts',
      () async {
        final service = ProductBriefingService(
          userId: 'uid',
          recommendations: _Recommendations({
            'Oat drink': const FoodRecommendation(
              food: 'Oat drink',
              found: true,
            ),
          }),
          profileLoader: (_) async => null,
        );
        final result = await service.describe(_product(status: 'ambiguous'));
        expect(result.text, contains('identification is uncertain'));
        expect(result.text, contains('can’t confirm'));
        expect(result.text, isNot(contains('safe to buy')));
      },
    );

    test(
      'preference, nutrient, declined swap, and broken image are handled',
      () async {
        const profile = UserProfile(
          prefs: {Preference.vegan},
          declinedSwaps: {'soy milk'},
        );
        final recommendations = _Recommendations({
          'Oat drink': const FoodRecommendation(
            food: 'Oat drink',
            found: true,
            hasGeneralInfo: true,
            generalInfo: 'Contains added sugar.',
            clashingPrefs: {Preference.vegan},
            excessNutrients: {Nutrient.sodium},
            alternatives: ['Tofu drink', 'Soy milk'],
            profile: profile,
          ),
          'Tofu drink': const FoodRecommendation(
            food: 'Tofu drink',
            found: true,
            boostsNutrients: {Nutrient.calcium},
            profile: profile,
          ),
          'Soy milk': const FoodRecommendation(
            food: 'Soy milk',
            found: true,
            profile: profile,
          ),
        });
        final service = ProductBriefingService(
          userId: 'uid',
          recommendations: recommendations,
          profileLoader: (_) async => {
            'dietary': ['Vegan'],
          },
          imageLoader: (_) async => throw StateError('broken image lookup'),
        );
        final result = await service.describe(_product());
        expect(result.text, contains('Vegan'));
        expect(result.text, contains('sodium'));
        expect(result.text, contains('Tofu drink'));
        expect(result.alternatives.map((a) => a.name), ['Tofu drink']);
        expect(result.alternatives.single.image, isNull);
        expect(result.alternatives.single.detail, contains('calcium'));
      },
    );

    test('unknown custom profile constraints remain explicit', () async {
      final recommendations = _Recommendations({
        'Oat drink': const FoodRecommendation(
          food: 'Oat drink',
          found: true,
          hasGeneralInfo: true,
          generalInfo: 'Stored note.',
          alternatives: ['Tofu drink'],
        ),
        'Tofu drink': const FoodRecommendation(food: 'Tofu drink', found: true),
      });
      final service = ProductBriefingService(
        userId: 'uid',
        recommendations: recommendations,
        profileLoader: (_) async => {
          'dietary': ['Other: low FODMAP'],
        },
        imageLoader: (_) async => null,
      );
      final result = await service.describe(_product());
      expect(result.text, contains('low FODMAP'));
      expect(result.alternatives.single.detail, contains('low FODMAP'));
    });

    test(
      'beliefs without food rules are not marked as unknown constraints',
      () async {
        final service = ProductBriefingService(
          userId: 'uid',
          recommendations: _Recommendations({
            'Oat drink': const FoodRecommendation(
              food: 'Oat drink',
              found: true,
            ),
          }),
          profileLoader: (_) async => {
            'religion': ['Christianity', 'Atheist', 'Agnostic'],
          },
        );
        final result = await service.describe(_product());
        expect(result.text, isNot(contains('unknown')));
        expect(result.text, contains('no known alerts or conflicts'));
      },
    );

    test('ambiguous scan omits zero-confidence percentage', () async {
      final service = ProductBriefingService(
        userId: 'uid',
        recommendations: _Recommendations({
          'Oat drink': const FoodRecommendation(food: 'Oat drink', found: true),
        }),
        profileLoader: (_) async => null,
      );
      final result = await service.describe(
        _product(status: 'ambiguous', confidence: 0),
      );
      expect(result.text, contains('may match'));
      expect(result.text, contains('identification is uncertain'));
      expect(result.text, isNot(contains('0%')));
    });

    test(
      'long stored general information is shortened after alert reasons',
      () async {
        final longInfo = List.filled(120, 'Long stored explanation.').join(' ');
        final service = ProductBriefingService(
          userId: 'uid',
          recommendations: _Recommendations({
            'Oat drink': FoodRecommendation(
              food: 'Oat drink',
              found: true,
              hasNews: true,
              hasGeneralInfo: true,
              generalInfo: longInfo,
              clashingPrefs: {Preference.vegan},
              alternatives: [],
            ),
          }),
          profileLoader: (_) async => {
            'dietary': ['Vegan'],
          },
        );
        final result = await service.describe(_product());
        expect(result.text.length, lessThanOrEqualTo(480));
        expect(result.text, contains('stored food alert'));
        expect(result.text, contains('Vegan'));
        expect(result.text, isNot(contains(longInfo)));
        expect(longInfo.length, greaterThan(480));
      },
    );
  });
}

class _Recommendations extends FoodRecommendationService {
  _Recommendations(this.values)
    : super(fetcher: (_) async => null, userFetcher: (_) async => null);

  final Map<String, FoodRecommendation> values;

  @override
  Future<FoodRecommendation> recommendFor({
    required String uid,
    required String foodName,
  }) async =>
      values[foodName] ?? FoodRecommendation(food: foodName, found: false);
}

ProductIdentification _product({
  String status = 'identified',
  String? brand = 'OatCo',
  String? variant = 'Barista',
  String? packageSize = '1 litre',
  String? gtin,
  String? catalogProductId,
  int confidence = 92,
}) => ProductIdentification(
  status: status,
  productName: 'Oat drink',
  brand: brand,
  variant: variant,
  packageSize: packageSize,
  sku: null,
  gtin: gtin,
  catalogProductId: catalogProductId,
  confidence: confidence,
  productNameConfidence: 92,
  brandConfidence: brand == null ? 0 : 92,
  variantConfidence: variant == null ? 0 : 92,
  skuConfidence: 0,
  gtinConfidence: gtin == null ? 0 : 100,
  evidence: const ['front label'],
  uncertainties: const [],
);
