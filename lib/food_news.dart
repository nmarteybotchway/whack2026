/// A service that looks up local and general-info news about a food
/// from the Firebase food collection.
///
/// ```dart
/// import 'package:hackathon/food_news.dart';
///
/// final service = FoodNewsService();
/// final result = await service.getNews('romaine lettuce');
/// print(result.localNews);
/// print(result.generalInfo);
/// ```
library;

export 'food_news/food_news_service.dart';
