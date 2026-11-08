import '../diet/nutrient_insights.dart';

/// Scores how well the user's recent diet meets the daily vitamin and mineral
/// targets, as a single 0..1 progress value for the garden.
///
/// Targets come from [nutrientTargets] via [NutrientInsights], so the garden,
/// the nutrient tracker and the gaps card all agree on what "enough" means.
/// The score is computed on demand and never stored.
class NutrientScoreService {
  NutrientScoreService({
    Future<NutrientInsights> Function(String userId)? loader,
  }) : _loader = loader ?? NutrientInsights.load;

  final Future<NutrientInsights> Function(String userId) _loader;

  /// Score 0..1: the mean of every nutrient's score in
  /// [NutrientInsights.coverage], or 0 when nothing has been tracked.
  ///
  /// Goal nutrients score their [NutrientCoverage.ratio] clamped to 1, so
  /// one megadose can't mask gaps elsewhere. Limit nutrients (sodium) score 1
  /// at or under the limit and fall linearly to 0 at twice the limit.
  static double scoreFromInsights(NutrientInsights insights) {
    if (insights.isEmpty || insights.coverage.isEmpty) return 0;
    var sum = 0.0;
    for (final c in insights.coverage) {
      sum += _nutrientScore(c);
    }
    return (sum / insights.coverage.length).clamp(0.0, 1.0);
  }

  /// One nutrient's 0..1 contribution to [scoreFromInsights].
  static double _nutrientScore(NutrientCoverage c) {
    final ratio = c.ratio;
    if (ratio.isNaN) return 0;
    if (c.target.isLimit) return (2 - ratio).clamp(0.0, 1.0);
    return ratio.clamp(0.0, 1.0);
  }

  /// Loads [userId]'s [NutrientInsights] and scores them.
  Future<double> scoreFor(String userId) async =>
      scoreFromInsights(await _loader(userId));
}
