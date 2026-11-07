import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/food/food.dart';
import 'package:hackathon/food_news.dart';

FoodNewsService _service(Map<String, Food> foods) => FoodNewsService(
  fetcher: (name) async => foods[Food.idFor(name)],
);

void main() {
  group('FoodNewsService', () {
    test('returns the fixed message for an unknown food', () async {
      final result = await _service({}).getNews('dragon fruit');
      expect(result.localNews, 'No negative news discovered');
      expect(result.generalInfo, 'No negative news discovered');
      expect(result.hasAlerts, isFalse);
    });

    test('returns stored news for bacon (carcinogen studies)', () async {
      final bacon = const Food(
        name: 'Bacon',
        localNews: 'Recall of brand X bacon in Gauteng.',
        generalInfo: 'Processed meat high in carcinogens; IARC Group 1.',
      );
      final result = await _service({'bacon': bacon}).getNews('bacon');
      expect(result.localNews, 'Recall of brand X bacon in Gauteng.');
      expect(
        result.generalInfo,
        'Processed meat high in carcinogens; IARC Group 1.',
      );
      expect(result.hasAlerts, isTrue);
    });

    test('falls back per field when only generalInfo is set', () async {
      final eggs = const Food(name: 'Eggs', generalInfo: 'Fine in moderation.');
      final result = await _service({'eggs': eggs}).getNews('eggs');
      expect(result.localNews, 'No negative news discovered');
      expect(result.generalInfo, 'Fine in moderation.');
      expect(result.hasAlerts, isTrue);
    });

    test('falls back when both fields are empty', () async {
      final result = await _service({
        'tofu': const Food(name: 'Tofu'),
      }).getNews('tofu');
      expect(result.localNews, 'No negative news discovered');
      expect(result.generalInfo, 'No negative news discovered');
    });

    test('names are normalized through Food.idFor', () async {
      final rice = const Food(name: 'Rice');
      final result = await _service({'rice': rice}).getNews('  RICE ');
      expect(result.hasAlerts, isFalse); // lookup matched, no news stored
    });

    test('hasAlerts is true when only localNews is set', () async {
      final result = await _service({
        'lettuce': const Food(name: 'Lettuce', localNews: 'E. coli recall.'),
      }).getNews('lettuce');
      expect(result.hasAlerts, isTrue);
      expect(result.generalInfo, 'No negative news discovered');
    });
  });
}
