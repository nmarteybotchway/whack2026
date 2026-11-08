import '../food/food.dart';
import '../food/health_condition.dart';
import '../food/preference.dart';

/// Master switch for the pantry-news demo; flip to false to disable the
/// startup notification entirely.
const bool pantryNewsEnabled = true;

/// How long after app startup the news "arrives".
const Duration pantryNewsDelay = Duration(seconds: 30);

/// Hardcoded breaking news per food, as if discovered in real time after
/// the food was already in the pantry. No database: this map IS the demo
/// data. To extend the demo (e.g. to a real receipt), add an entry.
const Map<String, PantryNewsItem> demoPantryNews = {
  'Strawberries': PantryNewsItem(
    news:
        'FSA alert: Salmonella found in a batch of strawberries sold in '
        'Aldi and Lidl in Coventry and across the West Midlands this week; '
        'do not eat, return to the store for a refund.',
    sources: [
      'https://www.food.gov.uk/news-alerts/alert/demo-strawberries-2026',
      'https://www.bbc.co.uk/news/health-demo-strawberries',
    ],
    // Judged through FoodRecommendationService.recommend like any scanned
    // food; the none/none row is what a user with no conditions/prefs gets.
    food: Food(
      name: 'Strawberries',
      localNews:
          'FSA alert: Salmonella found in a batch of strawberries sold in '
          'Aldi and Lidl in Coventry and across the West Midlands this '
          'week; do not eat, return to the store for a refund.',
      alternatives: {
        HealthCondition.none: {
          Preference.none: ['blueberries', 'kiwi', 'banana'],
        },
      },
    ),
  ),
};

/// One hardcoded pantry-news entry: what the banner shows plus the Food the
/// recommendation service judges.
class PantryNewsItem {
  const PantryNewsItem({
    required this.news,
    required this.sources,
    required this.food,
  });

  final String news;
  final List<String> sources;
  final Food food;
}
