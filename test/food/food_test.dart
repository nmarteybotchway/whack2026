import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/health_condition.dart';
import 'package:hackathon/food/preference.dart';

const bacon = Food(
  name: 'Bacon',
  generalAlternatives: ['Turkey bacon', 'Smoked tofu'],
  healthAlternatives: {
    HealthCondition.hypertension: ['Grilled chicken', 'Smoked tofu'],
  },
  prefAlternatives: {
    Preference.vegan: ['Tempeh bacon', 'Smoked tofu'],
    Preference.halal: ['Halal beef bacon'],
  },
  healthConditions: {HealthCondition.hypertension},
  personalPrefs: {Preference.vegan, Preference.halal},
  generalInfo: 'Processed meat high in salt and saturated fat.',
);

const apples = Food(
  name: 'Apples',
  healthAlternatives: {
    HealthCondition.ibs: ['Bananas'],
  },
  healthConditions: {HealthCondition.ibs},
);

void main() {
  test('alternatives keys never collide', () {
    final keys = [
      Food.generalKey,
      for (final c in HealthCondition.values) c.id,
      for (final p in Preference.values) p.id,
    ];
    expect(keys.toSet(), hasLength(keys.length));
  });

  test('toMap and fromMap round-trip', () {
    final map = bacon.toMap();
    expect(map['alternatives'], {
      'general': ['Turkey bacon', 'Smoked tofu'],
      'hypertension': ['Grilled chicken', 'Smoked tofu'],
      'vegan': ['Tempeh bacon', 'Smoked tofu'],
      'halal': ['Halal beef bacon'],
    });
    expect(Food.fromMap(map).toMap(), map);
  });

  test('foods that are fine have no general key', () {
    expect(apples.toMap()['alternatives'], {
      'ibs': ['Bananas'],
    });
    expect(Food.fromMap(apples.toMap()).generalAlternatives, isEmpty);
  });

  test('older flat alternatives load as general', () {
    final food = Food.fromMap({
      'food': 'Apples',
      'alternatives': ['Pears'],
    });
    expect(food.generalAlternatives, ['Pears']);
    expect(food.healthAlternatives, isEmpty);
  });

  group('alternativesFor', () {
    test('no conditions or preferences gives general', () {
      expect(bacon.alternativesFor(), bacon.generalAlternatives);
    });

    test('unrelated conditions and preferences give general', () {
      expect(
        bacon.alternativesFor(
          conditions: {HealthCondition.eggAllergy},
          prefs: {Preference.glutenFree},
        ),
        bacon.generalAlternatives,
      );
    });

    test('a food that is fine gives nothing without a clash', () {
      expect(apples.alternativesFor(), isEmpty);
      expect(apples.alternativesFor(conditions: {HealthCondition.ibs}), [
        'Bananas',
      ]);
    });

    test('a matching preference gives its list', () {
      expect(bacon.alternativesFor(prefs: {Preference.vegan}), [
        'Tempeh bacon',
        'Smoked tofu',
      ]);
    });

    test('several matches rank shared substitutes first', () {
      expect(
        bacon.alternativesFor(
          conditions: {HealthCondition.hypertension},
          prefs: {Preference.vegan},
        ),
        ['Smoked tofu', 'Grilled chicken', 'Tempeh bacon'],
      );
    });
  });
}
