import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/food_recommendation_service.dart';
import 'package:hackathon/food/health_condition.dart';
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
    HealthCondition.ibs: {Preference.none: ['Bananas']},
  },
  healthConditions: {HealthCondition.ibs},
);

const recalledTofu = Food(name: 'Tofu', localNews: 'Recalled batch detected.');

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

    test('unknown food is flagged as not found', () async {
      final r = await service.recommendFor(uid: 'u1', foodName: 'Durian');
      expect(r.found, isFalse);
      expect(r.shouldAvoid, isFalse);
      expect(r.canBuy, isFalse);
    });
  });
}
