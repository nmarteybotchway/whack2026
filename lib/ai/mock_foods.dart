/// Mock scanned foods for exercising [FoodComplianceService] before the
/// camera pipeline produces real results.
///
/// Each entry stands in for one scan: pass the `name` (and `ingredients`,
/// when known) to `FoodComplianceService.checkFood`. When the camera lands,
/// these are replaced by whatever the vision call returns.
class MockFood {
  const MockFood(this.name, {this.ingredients = const []});

  final String name;
  final List<String> ingredients;
}

const mockFoods = [
  MockFood('Beef gelatin gummy sweets', ingredients: [
    'glucose syrup',
    'sugar',
    'pork gelatin',
    'citric acid',
    'colour E120',
  ]),
  MockFood('Cheese pizza slice', ingredients: [
    'wheat flour',
    'tomato',
    'mozzarella (animal rennet)',
    'olive oil',
  ]),
  MockFood('Grilled chicken wrap', ingredients: [
    'tortilla',
    'grilled chicken',
    'mayonnaise (egg)',
    'lettuce',
  ]),
  MockFood('Greek salad', ingredients: [
    'tomato',
    'cucumber',
    'feta cheese',
    'olives',
    'olive oil',
  ]),
  MockFood('Apple'),
];
