import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/nutrition_service.dart';

void main() {
  test('maps USDA nutrient names onto shorthands with correct units', () {
    final nutrients = NutritionService.nutrientsFromUsda([
      {
        'nutrientName': 'Calcium, Ca, mg',
        'unitName': 'MG',
        'value': 56.0,
      },
      {
        'nutrientName': 'Vitamin B-12',
        'unitName': 'UG',
        'value': 0.89,
      },
      {
        'nutrientName': 'Sodium, Na, mg',
        'unitName': 'MG',
        'value': 142.0,
      },
      {
        'nutrientName': 'Vitamin E (alpha-tocopherol)',
        'unitName': 'MG',
        'value': 1.05,
      },
      {
        'nutrientName': 'Vitamin A, RAE',
        'unitName': 'UG',
        'value': 160.0,
      },
      {
        // IU duplicate of RAE — must be ignored.
        'nutrientName': 'Vitamin A, IU',
        'unitName': 'IU',
        'value': 540.0,
      },
      {
        'nutrientName': 'Vitamin E, added',
        'unitName': 'MG',
        'value': 5.0,
      },
      {'nutrientName': 'Energy', 'unitName': 'KCAL', 'value': 100.0},
    ]);

    expect(nutrients['CA'], 56.0);
    expect(nutrients['VITB12'], 0.89);
    expect(nutrients['NA'], 142.0);
    expect(nutrients['VITE'], 1.05);
    expect(nutrients['VITA'], 160.0);
    // No energy, no added-vitamin double count, no IU double count.
    expect(nutrients.containsKey('ENERGY'), isFalse);
    expect(nutrients.length, 5);
  });

  test('prefers folate DFE and falls back to food folate', () {
    final withDfe = NutritionService.nutrientsFromUsda([
      {'nutrientName': 'Folate, food', 'unitName': 'UG', 'value': 40.0},
      {'nutrientName': 'Folate, DFE', 'unitName': 'UG', 'value': 47.0},
    ]);
    expect(withDfe['FOL'], 47.0);

    final foodOnly = NutritionService.nutrientsFromUsda([
      {'nutrientName': 'Folate, food', 'unitName': 'UG', 'value': 40.0},
    ]);
    expect(foodOnly['FOL'], 40.0);
  });

  test('converts MG values to UG for UG-tracked nutrients', () {
    final nutrients = NutritionService.nutrientsFromUsda([
      {'nutrientName': 'Vitamin K (phylloquinone)', 'unitName': 'MG', 'value': 0.1},
    ]);
    expect(nutrients['VITK'], closeTo(100.0, 0.001));
  });

  test('converts IU vitamin D entries tracked in UG', () {
    final nutrients = NutritionService.nutrientsFromUsda([
      {'nutrientName': 'Vitamin D (D2 + D3), International Units', 'unitName': 'IU', 'value': 82.0},
    ]);
    // IU entries for D are ignored: only the UG variant counts.
    expect(nutrients.containsKey('VITD'), isFalse);
  });
}
