import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/nutrient_insights.dart';
import 'package:hackathon/garden/nutrient_score_service.dart';

void main() {
  final today = DateTime(2026, 11, 7);

  /// Insights for a single tracked day ([today]) with [day] intake.
  NutrientInsights oneDay(Map<String, double> day) =>
      NutrientInsights.fromDaily({today: day}, today: today, days: 7);

  /// Every goal nutrient at [fraction] of its target, sodium at [sodium].
  Map<String, double> goalsAt(double fraction, {double sodium = 0}) => {
    for (final e in nutrientTargets.entries)
      e.key: e.value.isLimit ? sodium : e.value.daily * fraction,
  };

  final goalCount = nutrientTargets.values.where((t) => !t.isLimit).length;
  final total = nutrientTargets.length;

  test('empty insights score 0', () {
    final insights = NutrientInsights.fromDaily({}, today: today, days: 7);
    expect(insights.isEmpty, isTrue);
    expect(NutrientScoreService.scoreFromInsights(insights), 0);
  });

  test('all targets met with sodium under the limit scores 1', () {
    final score = NutrientScoreService.scoreFromInsights(
      oneDay(goalsAt(1, sodium: 1500)),
    );
    expect(score, closeTo(1, 1e-9));
  });

  test('half of each goal scores about 0.5', () {
    final score = NutrientScoreService.scoreFromInsights(oneDay(goalsAt(0.5)));
    // Goals contribute 0.5 each; sodium at 0 is within the limit and scores 1.
    expect(score, closeTo((goalCount * 0.5 + 1) / total, 1e-9));
    expect(score, closeTo(0.5, 0.05));
  });

  test('going over the sodium limit lowers the score', () {
    final limit = nutrientTargets['NA']!.daily;
    double scoreAt(double sodium) => NutrientScoreService.scoreFromInsights(
      oneDay(goalsAt(1, sodium: sodium)),
    );

    expect(scoreAt(limit), closeTo(1, 1e-9));
    expect(scoreAt(limit * 1.5), closeTo((total - 0.5) / total, 1e-9));
    expect(scoreAt(limit * 2), closeTo((total - 1) / total, 1e-9));
    expect(scoreAt(limit * 5), closeTo((total - 1) / total, 1e-9));
  });

  test('a megadose of one nutrient is clamped', () {
    final score = NutrientScoreService.scoreFromInsights(
      oneDay({'VITC': nutrientTargets['VITC']!.daily * 100}),
    );
    // Vitamin C contributes at most 1, sodium (0) scores 1, the rest 0.
    expect(score, closeTo(2 / total, 1e-9));
  });

  test('scoreFor uses the injected loader', () async {
    final requested = <String>[];
    final service = NutrientScoreService(
      loader: (userId) async {
        requested.add(userId);
        return oneDay(goalsAt(1));
      },
    );

    expect(await service.scoreFor('user-1'), closeTo(1, 1e-9));
    expect(requested, ['user-1']);
  });
}
