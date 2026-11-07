/// A service that checks the latest negative news about a food.
///
/// ```dart
/// import 'package:hackathon/food_news.dart';
///
/// final service = FoodNewsService();
/// final result = await service.getNews('romaine lettuce');
/// print('${result.sentiment}: ${result.summary}');
/// ```
library;

export 'food_news/food_news_service.dart';
