import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/health_condition.dart';
import 'package:hackathon/food/nutrient.dart';
import 'package:hackathon/food/preference.dart';

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

void main() {
  test('none is stored as "none" and excluded from the real values', () {
    expect(HealthCondition.fromId('none'), HealthCondition.none);
    expect(Preference.fromId('none'), Preference.none);
    expect(HealthCondition.conditions, isNot(contains(HealthCondition.none)));
    expect(Preference.preferences, isNot(contains(Preference.none)));
    expect(Preference.fromLabel('None'), isNull);
  });

  test('every preference is a settings option that maps back', () {
    expect(
      {...Preference.religions, ...Preference.dietary},
      {...Preference.preferences},
    );
    for (final p in Preference.preferences) {
      expect(Preference.fromLabel(p.label), p);
    }
    for (final belief in Preference.otherBeliefs) {
      expect(Preference.fromLabel(belief), isNull);
    }
  });

  test('none is never a clash', () {
    final food = Food.fromMap({
      'food': 'Apples',
      'health_conditions': ['none', 'ibs'],
      'personal_prefs': ['none'],
    });
    expect(food.healthConditions, {HealthCondition.ibs});
    expect(food.personalPrefs, isEmpty);
  });

  test('toMap and fromMap round-trip', () {
    final map = bacon.toMap();
    expect(map['alternatives'], {
      'none': {
        'none': ['Roast chicken'],
        'vegan': ['Smoked tofu', 'Tempeh bacon'],
        'halal': ['Halal turkey rashers'],
      },
      'hypertension': {
        'none': ['Grilled chicken', 'Smoked tofu'],
        'vegan': ['Smoked tofu', 'Lentils'],
        'halal': ['Grilled halal chicken'],
      },
    });
    expect(Food.fromMap(map).toMap(), map);
  });

  group('nutrients', () {
    const spinach = Food(
      name: 'Spinach',
      nutrients: {
        Nutrient.vitaminK: 483, // way over 15% of 75 µg
        Nutrient.iron: 2.7, // 19% of 14 mg
        Nutrient.calcium: 99, // 12% of 800 mg
        Nutrient.sodium: 79,
      },
    );

    test('round-trip by id', () {
      final map = spinach.toMap();
      expect(map['nutrients'], {'VITK': 483, 'FE': 2.7, 'CA': 99, 'NA': 79});
      expect(Food.fromMap(map).nutrients, spinach.nutrients);
    });

    test('unknown ids, non-numbers and zeros are skipped', () {
      final food = Food.fromMap({
        'food': 'X',
        'nutrients': {'VITC': 10, 'VITZ': 5, 'FE': 'lots', 'CA': 0},
      });
      expect(food.nutrients, {Nutrient.vitaminC: 10.0});
    });

    test('missing nutrients parse as none', () {
      expect(Food.fromMap({'food': 'X'}).nutrients, isEmpty);
    });

    test('richIn uses 15% of the daily value', () {
      expect(spinach.richIn, {Nutrient.vitaminK, Nutrient.iron});
    });

    test('highIn uses 25% of the daily limit', () {
      expect(spinach.highIn, isEmpty);
      const bacon = Food(name: 'Bacon', nutrients: {Nutrient.sodium: 1700});
      expect(bacon.highIn, {Nutrient.sodium});
      expect(bacon.richIn, isEmpty);
    });
  });

  test('unknown condition and preference IDs are skipped', () {
    final food = Food.fromMap({
      'food': 'Bacon',
      'alternatives': {
        'none': {
          'none': ['A'],
          'future_pref': ['B'],
        },
        'future_condition': {
          'none': ['C'],
        },
      },
    });
    expect(food.alternatives, {
      HealthCondition.none: {
        Preference.none: ['A'],
      },
    });
  });

  test('older non-nested alternatives are skipped', () {
    final food = Food.fromMap({
      'food': 'Apples',
      'alternatives': {
        'general': ['Pears'],
        'ibs': ['Bananas'],
      },
    });
    expect(food.alternatives, isEmpty);
  });

  group('alternativesFor', () {
    test('no conditions or preferences gives none/none', () {
      expect(bacon.alternativesFor(), ['Roast chicken']);
    });

    test('unrelated conditions and preferences give none/none', () {
      expect(
        bacon.alternativesFor(
          conditions: {HealthCondition.eggAllergy},
          prefs: {Preference.glutenFree},
        ),
        ['Roast chicken'],
      );
    });

    test('only a preference uses the none row', () {
      expect(bacon.alternativesFor(prefs: {Preference.vegan}), [
        'Smoked tofu',
        'Tempeh bacon',
      ]);
    });

    test('only a condition uses its none column', () {
      expect(
        bacon.alternativesFor(conditions: {HealthCondition.hypertension}),
        ['Grilled chicken', 'Smoked tofu'],
      );
    });

    test('a condition and a preference use their pair', () {
      expect(
        bacon.alternativesFor(
          conditions: {HealthCondition.hypertension},
          prefs: {Preference.vegan},
        ),
        ['Smoked tofu', 'Lentils'],
      );
    });

    test('several preferences rank shared substitutes first', () {
      expect(
        bacon.alternativesFor(
          conditions: {HealthCondition.hypertension},
          prefs: {Preference.vegan, Preference.halal},
        ),
        ['Smoked tofu', 'Lentils', 'Grilled halal chicken'],
      );
    });

    test('tieBreak only orders equally voted substitutes', () {
      // Reverse alphabetical among ties; 'Smoked tofu' (2 votes) stays first.
      expect(
        bacon.alternativesFor(
          conditions: {HealthCondition.hypertension},
          prefs: {Preference.vegan, Preference.halal},
          tieBreak: (a, b) => b.compareTo(a),
        ),
        ['Smoked tofu', 'Lentils', 'Grilled halal chicken'],
      );
      expect(
        bacon.alternativesFor(
          prefs: {Preference.vegan},
          tieBreak: (a, b) => b.compareTo(a),
        ),
        ['Tempeh bacon', 'Smoked tofu'],
      );
    });

    test('a food that is fine gives nothing without a clash', () {
      expect(apples.alternativesFor(), isEmpty);
      expect(apples.alternativesFor(conditions: {HealthCondition.ibs}), [
        'Bananas',
      ]);
    });
  });
}
