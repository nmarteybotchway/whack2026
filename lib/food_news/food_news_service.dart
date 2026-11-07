import '../food/food.dart';
import '../food/food_repository.dart';

/// The food news a lookup returns.
class FoodNewsResult {
  const FoodNewsResult({
    required this.localNews,
    required this.generalInfo,
    required this.hasAlerts,
  });

  /// Current food-safety news (outbreak/recall), or the fixed fallback
  /// message when there is none.
  final String localNews;

  /// Why to avoid or limit the food, or the fixed fallback message when
  /// the food is fine.
  final String generalInfo;

  /// Whether the food had any real news: a plain non-empty check on the raw
  /// stored values ('' means no news per the Food contract), computed
  /// before the fallback message is substituted for display.
  final bool hasAlerts;
}

/// Looks up local and general-info news about a food from the food database.
///
/// Reads the Firestore `food` collection through [fetcher] — pass
/// `FoodRepository().get` (the default) in production, or a mock in tests.
class FoodNewsService {
  /// Creates a service that reads foods through [fetcher].
  FoodNewsService({Future<Food?> Function(String name)? fetcher})
    : _fetcher = fetcher ?? FoodRepository().get;

  /// The fixed reply when the database has no news for a food.
  static const String noNewsMessage = 'No negative news discovered';

  final Future<Food?> Function(String name) _fetcher;

  /// Returns the stored local and general-info news about [name].
  ///
  /// Missing fields — an unknown food, or empty `localNews` /
  /// `generalInfo` — fall back to [noNewsMessage] per field.
  /// [FoodNewsResult.hasAlerts] reflects the raw non-empty check.
  Future<FoodNewsResult> getNews(String name) async {
    final food = await _fetcher(name);
    final local = food?.localNews ?? '';
    final general = food?.generalInfo ?? '';
    return FoodNewsResult(
      localNews: _orNoNews(local),
      generalInfo: _orNoNews(general),
      hasAlerts: local.trim().isNotEmpty || general.trim().isNotEmpty,
    );
  }

  static String _orNoNews(String text) =>
      text.trim().isEmpty ? noNewsMessage : text;
}
