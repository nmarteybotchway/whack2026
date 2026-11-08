import 'diet_window_service.dart';
import 'nutrition_service.dart';
import 'receipt_store.dart';

/// Display name and recommended adult daily intake for one tracked nutrient,
/// in the unit from [nutrientUnits].
///
/// [isLimit] marks nutrients to keep under the target (sodium) rather than
/// reach.
class NutrientTarget {
  const NutrientTarget(
    this.label,
    this.daily, {
    this.isLimit = false,
    this.sources = const [],
  });

  final String label;
  final double daily;
  final bool isLimit;

  /// Common foods rich in this nutrient, suggested when it is lacking.
  final List<String> sources;
}

/// Adult reference daily intakes (UK/EU NRVs, NHS sodium limit), keyed by the
/// shorthands in [nutrientUnits].
const nutrientTargets = <String, NutrientTarget>{
  'CA': NutrientTarget(
    'Calcium',
    800,
    sources: ['Milk', 'Yoghurt', 'Cheese', 'Tofu'],
  ),
  'NA': NutrientTarget('Sodium', 2400, isLimit: true),
  'FE': NutrientTarget(
    'Iron',
    14,
    sources: ['Spinach', 'Lentils', 'Red meat', 'Fortified cereal'],
  ),
  'K': NutrientTarget(
    'Potassium',
    2000,
    sources: ['Bananas', 'Potatoes', 'Beans', 'Avocado'],
  ),
  'MG': NutrientTarget(
    'Magnesium',
    375,
    sources: ['Almonds', 'Spinach', 'Oats', 'Brown rice'],
  ),
  'ZN': NutrientTarget(
    'Zinc',
    10,
    sources: ['Beef', 'Chickpeas', 'Pumpkin seeds', 'Cashews'],
  ),
  'VITA': NutrientTarget(
    'Vitamin A',
    800,
    sources: ['Carrots', 'Sweet potato', 'Spinach', 'Eggs'],
  ),
  'VITB6': NutrientTarget(
    'Vitamin B6',
    1.4,
    sources: ['Chicken', 'Salmon', 'Bananas', 'Chickpeas'],
  ),
  'VITB12': NutrientTarget(
    'Vitamin B12',
    2.5,
    sources: ['Eggs', 'Milk', 'Salmon', 'Fortified cereal'],
  ),
  'VITC': NutrientTarget(
    'Vitamin C',
    80,
    sources: ['Oranges', 'Peppers', 'Strawberries', 'Broccoli'],
  ),
  'VITD': NutrientTarget(
    'Vitamin D',
    10,
    sources: ['Oily fish', 'Eggs', 'Fortified milk', 'Mushrooms'],
  ),
  'VITE': NutrientTarget(
    'Vitamin E',
    12,
    sources: ['Sunflower seeds', 'Almonds', 'Avocado', 'Olive oil'],
  ),
  'VITK': NutrientTarget(
    'Vitamin K',
    75,
    sources: ['Kale', 'Spinach', 'Broccoli', 'Cabbage'],
  ),
  'FOL': NutrientTarget(
    'Folate',
    200,
    sources: ['Lentils', 'Asparagus', 'Spinach', 'Chickpeas'],
  ),
};

enum NutrientStatus { lacking, low, good, high }

/// One nutrient's average daily intake over a window, compared with its
/// target.
class NutrientCoverage {
  const NutrientCoverage({
    required this.key,
    required this.average,
    required this.daily,
  });

  final String key;

  /// Average intake per day across the window.
  final double average;

  /// Intake on each day of the window, oldest first.
  final List<double> daily;

  NutrientTarget get target => nutrientTargets[key]!;

  /// Average intake as a fraction of the target (1.0 = 100%).
  double get ratio => average / target.daily;

  NutrientStatus get status {
    if (target.isLimit) {
      return ratio > 1 ? NutrientStatus.high : NutrientStatus.good;
    }
    if (ratio < 0.35) return NutrientStatus.lacking;
    if (ratio < 0.7) return NutrientStatus.low;
    return NutrientStatus.good;
  }
}

/// Historical nutrient intake built from stored receipt days and logged
/// foods, used to spot what the user is consistently short of.
class NutrientInsights {
  const NutrientInsights({
    required this.start,
    required this.days,
    required this.coverage,
    required this.trackedDays,
  });

  /// First day of the window.
  final DateTime start;

  /// Window length in days.
  final int days;

  /// Coverage for every nutrient in [nutrientTargets], most lacking first;
  /// limits (sodium) sort by how far over they are.
  final List<NutrientCoverage> coverage;

  /// Days in the window with any food recorded.
  final int trackedDays;

  bool get isEmpty => trackedDays == 0;

  /// Nutrients the user is lacking or low on, most lacking first.
  List<NutrientCoverage> get gaps => [
    for (final c in coverage)
      if (c.status == NutrientStatus.lacking || c.status == NutrientStatus.low)
        c,
  ];

  /// Loads [userId]'s insights for the last [days] days (at most the
  /// [DietWindowService] window): receipt days from the window plus foods
  /// logged through the assistant, combined per day.
  static Future<NutrientInsights> load(String userId, {int? days}) async {
    days ??= DietWindowService.window.inDays;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (days - 1));
    final (receiptDays, intake) = await (
      DietWindowService(userId).recentDays(),
      ReceiptStore(userId).loggedIntakeSince(start),
    ).wait;
    for (final day in receiptDays) {
      if (day.date.isBefore(start)) continue;
      final into = intake.putIfAbsent(day.date, () => {});
      day.nutrition.forEach((k, v) => into[k] = (into[k] ?? 0) + v);
    }
    return NutrientInsights.fromDaily(intake, today: now, days: days);
  }

  /// Builds insights for the [days] days ending on [today] from per-day
  /// nutrient totals in [intake], keyed by midnight dates.
  ///
  /// Averages divide by the days since tracking began (capped at [days]) so
  /// a new user isn't penalised for days before their first record.
  factory NutrientInsights.fromDaily(
    Map<DateTime, Map<String, double>> intake, {
    required DateTime today,
    int days = 30,
  }) {
    final end = DateTime(today.year, today.month, today.day);
    final start = end.subtract(Duration(days: days - 1));
    final window = [
      for (var i = 0; i < days; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    final normalised = <DateTime, Map<String, double>>{};
    intake.forEach((date, values) {
      final day = DateTime(date.year, date.month, date.day);
      final into = normalised.putIfAbsent(day, () => {});
      values.forEach((k, v) => into[k] = (into[k] ?? 0) + v);
    });

    final tracked = window.where((d) => normalised[d]?.isNotEmpty ?? false);
    final first = tracked.isEmpty ? end : tracked.first;
    final divisor = end.difference(first).inDays + 1;

    final coverage = [
      for (final key in nutrientTargets.keys)
        () {
          final daily = [for (final d in window) normalised[d]?[key] ?? 0.0];
          final total = daily.fold<double>(0, (a, b) => a + b);
          return NutrientCoverage(
            key: key,
            average: total / divisor,
            daily: daily,
          );
        }(),
    ];
    coverage.sort((a, b) {
      double score(NutrientCoverage c) =>
          c.target.isLimit ? 1 - (c.ratio - 1).clamp(0, 10) : c.ratio;
      return score(a).compareTo(score(b));
    });
    return NutrientInsights(
      start: start,
      days: days,
      coverage: coverage,
      trackedDays: tracked.length,
    );
  }
}
