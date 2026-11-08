import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/nutrient_insights.dart';

void main() {
  final today = DateTime(2026, 11, 7);

  test('averages over days since tracking began and ranks gaps first', () {
    final insights = NutrientInsights.fromDaily(
      {
        DateTime(2026, 11, 6): {'VITC': 160, 'CA': 100},
        DateTime(2026, 11, 7, 18): {'VITC': 0, 'CA': 100, 'NA': 6000},
      },
      today: today,
      days: 7,
    );

    expect(insights.trackedDays, 2);
    final vitC = insights.coverage.firstWhere((c) => c.key == 'VITC');
    expect(vitC.average, 80);
    expect(vitC.status, NutrientStatus.good);
    expect(vitC.daily, [0, 0, 0, 0, 0, 160, 0]);

    final calcium = insights.coverage.firstWhere((c) => c.key == 'CA');
    expect(calcium.average, 100);
    expect(calcium.status, NutrientStatus.lacking);

    final sodium = insights.coverage.firstWhere((c) => c.key == 'NA');
    expect(sodium.status, NutrientStatus.high);

    expect(insights.gaps, isNot(contains(vitC)));
    expect(insights.gaps, contains(calcium));
    expect(insights.coverage.first.ratio, 0); // Untouched nutrients lead.
  });

  test('ignores records outside the window', () {
    final insights = NutrientInsights.fromDaily(
      {
        DateTime(2026, 10, 1): {'FE': 50},
      },
      today: today,
      days: 7,
    );
    expect(insights.isEmpty, isTrue);
  });
}
