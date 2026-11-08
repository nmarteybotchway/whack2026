import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/nutrient_insights.dart';
import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/food_recommendation_service.dart';
import 'package:hackathon/food/health_condition.dart';
import 'package:hackathon/food/nutrient.dart';
import 'package:hackathon/food/preference.dart';

// Same fixtures as test/food/food_test.dart.
const bacon = Food(
  name: 'Bacon',
  alternatives: {
    HealthCondition.none: {
      Preference.none: ['Roast chicken'],
      Preference.vegan: ['Smoked tofu', 'Tempeh bacon'],
      Preference.halal: ['Halal turkey rashers'],
    },
    HealthCondition.hypertension: {
      Preference.none: ['Grilled chicken', 'Smoked tofu'],
      Preference.vegan: ['Smoked tofu', 'Lentils'],
      Preference.halal: ['Grilled halal chicken'],
    },
  },
  healthConditions: {HealthCondition.hypertension},
  personalPrefs: {Preference.vegan, Preference.halal},
  generalInfo: 'Processed meat high in salt and saturated fat.',
);

const apples = Food(
  name: 'Apples',
  alternatives: {
    HealthCondition.ibs: {
      Preference.none: ['Bananas'],
    },
  },
  healthConditions: {HealthCondition.ibs},
);

const recalledTofu = Food(name: 'Tofu', localNews: 'Recalled batch detected.');

const oranges = Food(name: 'Oranges', nutrients: {Nutrient.vitaminC: 53});

const crisps = Food(
  name: 'Crisps',
  alternatives: {
    HealthCondition.none: {
      Preference.none: ['Popcorn', 'Oranges'],
    },
  },
  nutrients: {Nutrient.sodium: 700, Nutrient.vitaminC: 15},
);

/// Insights from one day of [nutrition] totals, tracked today only.
NutrientInsights insights(Map<String, double> nutrition) {
  final today = DateTime(2026, 11, 7);
  return NutrientInsights.fromDaily({today: nutrition}, today: today);
}

void main() {
  group('recommend', () {
    test('fine food with no user match is buyable', () {
      final r = FoodRecommendationService.recommend(apples);
      expect(r.canBuy, isTrue);
      expect(r.shouldAvoid, isFalse);
      expect(r.alternatives, isEmpty);
      expect(r.found, isTrue);
    });

    test('general info only falls back to the none/none alternatives', () {
      final r = FoodRecommendationService.recommend(bacon);
      expect(r.shouldAvoid, isTrue);
      expect(r.hasGeneralInfo, isTrue);
      expect(r.generalInfo, bacon.generalInfo);
      expect(r.clashingConditions, isEmpty);
      expect(r.clashingPrefs, isEmpty);
      expect(r.alternatives, ['Roast chicken']); // the ['none']['none'] entry
    });

    test('local news only also recommends the none/none alternatives', () {
      final r = FoodRecommendationService.recommend(recalledTofu);
      expect(r.shouldAvoid, isTrue);
      expect(r.hasNews, isTrue);
      expect(r.hasGeneralInfo, isFalse);
      expect(r.alternatives, isEmpty);
    });

    test('health condition clash recommends the condition alternatives', () {
      final r = FoodRecommendationService.recommend(
        bacon,
        conditions: {HealthCondition.hypertension},
      );
      expect(r.clashingConditions, {HealthCondition.hypertension});
      expect(r.generalInfo, bacon.generalInfo);
      expect(r.clashingPrefs, isEmpty);
      expect(r.alternatives, ['Grilled chicken', 'Smoked tofu']);
    });

    test('preference clash recommends the preference alternatives', () {
      final r = FoodRecommendationService.recommend(
        bacon,
        prefs: {Preference.vegan},
      );
      expect(r.clashingPrefs, {Preference.vegan});
      expect(r.alternatives, ['Smoked tofu', 'Tempeh bacon']);
    });

    test('condition + preference pair recommends the pair alternatives', () {
      final r = FoodRecommendationService.recommend(
        bacon,
        conditions: {HealthCondition.hypertension},
        prefs: {Preference.vegan},
      );
      expect(r.alternatives, ['Smoked tofu', 'Lentils']);
    });

    test('user data the food does not clash with leaves it buyable', () {
      final r = FoodRecommendationService.recommend(
        apples,
        conditions: {HealthCondition.eggAllergy},
        prefs: {Preference.glutenFree},
      );
      expect(r.canBuy, isTrue);
    });

    test('news with no stored alternatives avoids without crashing', () {
      final r = FoodRecommendationService.recommend(
        Food(name: 'Spinach', localNews: 'E. coli outbreak.'),
      );
      expect(r.shouldAvoid, isTrue);
      expect(r.alternatives, isEmpty);
    });
  });

  group('recommend with nutrients', () {
    test('high in a nutrient the user is over the limit on is avoided', () {
      final r = FoodRecommendationService.recommend(
        crisps,
        highNutrients: {Nutrient.sodium},
      );
      expect(r.shouldAvoid, isTrue);
      expect(r.excessNutrients, {Nutrient.sodium});
      expect(r.alternatives, ['Popcorn', 'Oranges']);
    });

    test('high in a nutrient the user is not over on is fine', () {
      final r = FoodRecommendationService.recommend(crisps);
      expect(r.canBuy, isTrue);
      expect(r.excessNutrients, isEmpty);
    });

    test('rich in a low nutrient is a boost, not a reason to avoid', () {
      final r = FoodRecommendationService.recommend(
        oranges,
        lowNutrients: {Nutrient.vitaminC, Nutrient.iron},
      );
      expect(r.canBuy, isTrue);
      expect(r.boostsNutrients, {Nutrient.vitaminC});
    });

    test('substitutes covering low nutrients rank first', () {
      final r = FoodRecommendationService.recommend(
        crisps,
        highNutrients: {Nutrient.sodium},
        lowNutrients: {Nutrient.vitaminC},
        alternativeFoods: {oranges.id: oranges},
      );
      expect(r.alternatives, ['Oranges', 'Popcorn']);
    });
  });

  group('declined swaps', () {
    test('keys normalize like the scan result sheet', () {
      expect(
        FoodRecommendationService.swapKey('  Smoked\tBACON  x '),
        'smoked bacon x',
      );
    });

    test('a declined food keeps its reasons but offers no swaps', () {
      final r = FoodRecommendationService.recommend(
        bacon,
        conditions: {HealthCondition.hypertension},
        declinedSwaps: {'bacon'},
      );
      expect(r.shouldAvoid, isTrue);
      expect(r.clashingConditions, {HealthCondition.hypertension});
      expect(r.swapDeclined, isTrue);
      expect(r.alternatives, isEmpty);
    });

    test('declining another food leaves the swaps in place', () {
      final r = FoodRecommendationService.recommend(
        bacon,
        declinedSwaps: {'apples'},
      );
      expect(r.swapDeclined, isFalse);
      expect(r.alternatives, ['Roast chicken']);
    });

    test('a buyable food is never reported as declined', () {
      final r = FoodRecommendationService.recommend(
        oranges,
        declinedSwaps: {'oranges'},
      );
      expect(r.canBuy, isTrue);
      expect(r.swapDeclined, isFalse);
    });

    test('parseProfile reads ignored_swap_items as normalized keys', () {
      final p = FoodRecommendationService.parseProfile({
        'ignored_swap_items': ['bacon', '  Apple   Pie ', ' '],
      });
      expect(p.declinedSwaps, {'bacon', 'apple pie'});
    });

    test('recommendFor applies the stored declined swaps', () async {
      final service = FoodRecommendationService(
        fetcher: (name) async => bacon,
        userFetcher: (uid) async => {
          'health_conditions': ['hypertension'],
          'ignored_swap_items': ['bacon'],
        },
        insightsFetcher: (uid) async =>
            NutrientInsights.fromDaily({}, today: DateTime(2026, 11, 7)),
      );
      final r = await service.recommendFor(uid: 'u1', foodName: 'Bacon');
      expect(r.shouldAvoid, isTrue);
      expect(r.swapDeclined, isTrue);
      expect(r.alternatives, isEmpty);
      expect(r.profile.conditions, {HealthCondition.hypertension});
    });
  });

  group('parseProfile', () {
    test('missing document yields an empty profile', () {
      final p = FoodRecommendationService.parseProfile(null);
      expect(p.prefs, isEmpty);
      expect(p.conditions, isEmpty);
    });

    test('religion and dietary labels map through Preference.fromLabel', () {
      final p = FoodRecommendationService.parseProfile({
        'religion': ['Islam', 'Christianity', 'Other thing'],
        'dietary': ['Vegan'],
      });
      expect(p.prefs, {Preference.islam, Preference.vegan});
      expect(p.conditions, isEmpty);
    });

    test('health_conditions ids map through HealthCondition.fromId', () {
      final p = FoodRecommendationService.parseProfile({
        'health_conditions': ['hypertension', 'bogus'],
      });
      expect(p.conditions, {HealthCondition.hypertension});
      expect(p.prefs, isEmpty);
    });

    test('insight gaps are low and limits over target are high', () {
      final p = FoodRecommendationService.parseProfile(
        null,
        insights: insights({'VITC': 80, 'NA': 5000, 'FE': 2, 'BOGUS': 1}),
      );
      expect(p.lowNutrients, contains(Nutrient.iron)); // 2 of 14 mg
      expect(p.lowNutrients, isNot(contains(Nutrient.vitaminC)));
      expect(p.lowNutrients, isNot(contains(Nutrient.sodium)));
      expect(p.highNutrients, {Nutrient.sodium}); // 5000 > 2400 mg
    });

    test('nothing tracked means nothing is low', () {
      final p = FoodRecommendationService.parseProfile(
        null,
        insights: NutrientInsights.fromDaily({}, today: DateTime(2026, 11, 7)),
      );
      expect(p.lowNutrients, isEmpty);
      expect(p.highNutrients, isEmpty);
    });

    test('none strings never yield none values', () {
      final p = FoodRecommendationService.parseProfile({
        'religion': ['None'],
        'health_conditions': ['none'],
      });
      expect(p.prefs, isEmpty);
      expect(p.conditions, isEmpty);
    });
  });

  group('recommendFor', () {
    final foods = {Food.idFor('bacon'): bacon, Food.idFor('apples'): apples};
    final service = FoodRecommendationService(
      fetcher: (name) async => foods[Food.idFor(name)],
      userFetcher: (uid) async => {
        'dietary': ['Halal'],
        'health_conditions': ['hypertension'],
      },
      insightsFetcher: (uid) async =>
          NutrientInsights.fromDaily({}, today: DateTime(2026, 11, 7)),
    );

    test('matching user data triggers an alternative', () async {
      final r = await service.recommendFor(uid: 'u1', foodName: 'Bacon');
      expect(r.shouldAvoid, isTrue);
      expect(r.clashingPrefs, {Preference.halal});
      expect(r.clashingConditions, {HealthCondition.hypertension});
      expect(r.alternatives, ['Grilled halal chicken']);
    });

    test('name lookup normalizes via Food.idFor', () async {
      final r = await service.recommendFor(uid: 'u1', foodName: '  BACON ');
      expect(r.found, isTrue);
    });

    test('diet loads nutrients and ranks fetched substitutes', () async {
      final foods = {
        for (final f in [crisps, oranges]) f.id: f,
      };
      final service = FoodRecommendationService(
        fetcher: (name) async => foods[Food.idFor(name)],
        userFetcher: (uid) async => null,
        insightsFetcher: (uid) async => insights({'NA': 20000, 'VITC': 10}),
      );
      final r = await service.recommendFor(uid: 'u1', foodName: 'Crisps');
      expect(r.excessNutrients, {Nutrient.sodium});
      expect(r.alternatives, ['Oranges', 'Popcorn']);
    });

    test('a failed diet read skips nutrient checks', () async {
      final service = FoodRecommendationService(
        fetcher: (name) async => crisps,
        userFetcher: (uid) async => null,
        insightsFetcher: (uid) async => throw Exception('offline'),
      );
      final r = await service.recommendFor(uid: 'u1', foodName: 'Crisps');
      expect(r.canBuy, isTrue);
    });

    test('a failed parallel diet read (ParallelWaitError) skips nutrient '
        'checks', () async {
      final service = FoodRecommendationService(
        fetcher: (name) async => crisps,
        userFetcher: (uid) async => null,
        // Mirrors NutrientInsights.load: a record `.wait` where one read
        // fails throws a ParallelWaitError, which is an Error.
        insightsFetcher: (uid) async {
          await (Future<int>.error(Exception('offline')), Future.value(1)).wait;
          return insights({'NA': 20000});
        },
      );
      final r = await service.recommendFor(uid: 'u1', foodName: 'Crisps');
      expect(r.canBuy, isTrue);
    });

    test('a diet fetcher throwing an Error skips nutrient checks', () async {
      final service = FoodRecommendationService(
        fetcher: (name) async => crisps,
        userFetcher: (uid) async => null,
        insightsFetcher: (uid) async => throw StateError('bad diet'),
      );
      final r = await service.recommendFor(uid: 'u1', foodName: 'Crisps');
      expect(r.canBuy, isTrue);
    });

    test('a failed profile read propagates the original error', () async {
      final service = FoodRecommendationService(
        fetcher: (name) async => bacon,
        userFetcher: (uid) async => throw Exception('permission-denied'),
        insightsFetcher: (uid) async => throw Exception('offline'),
      );
      await expectLater(
        service.recommendFor(uid: 'u1', foodName: 'Bacon'),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('permission-denied'),
          ),
        ),
      );
    });

    test('unknown food is flagged as not found', () async {
      final r = await service.recommendFor(uid: 'u1', foodName: 'Durian');
      expect(r.found, isFalse);
      expect(r.shouldAvoid, isFalse);
      expect(r.canBuy, isFalse);
    });
  });
}
