import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/food_news.dart';
import 'package:hackathon/openrouter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _reply(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content},
      },
    ],
  }),
  200,
);

FoodNewsService _service(String content) => FoodNewsService(
  client: OpenRouterService(
    apiKey: 'test-key',
    client: MockClient((_) async => _reply(content)),
  ),
);

void main() {
  group('FoodNewsService', () {
    test('sends the news prompt with the food-news schema', () async {
      late http.Request sent;
      final service = FoodNewsService(
        client: OpenRouterService(
          apiKey: 'test-key',
          client: MockClient((request) async {
            sent = request;
            return _reply(
              '{"summary":"E. coli outbreak linked to romaine","sentiment":"Bad"}',
            );
          }),
        ),
      );

      await service.getNews('romaine lettuce');

      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['messages'][0]['content'], contains('romaine lettuce'));
      expect(body['messages'][0]['content'], contains('Access the internet'));
      expect(body['response_format']['type'], 'json_schema');
      expect(
        body['response_format']['json_schema']['schema']['properties']
            ['sentiment']['enum'],
        ['Good', 'Bad'],
      );
    });

    test('parses a Bad result', () async {
      final service = _service(
        '{"summary":"Salmonella recall issued","sentiment":"Bad"}',
      );
      final result = await service.getNews('peanut butter');
      expect(result.summary, 'Salmonella recall issued');
      expect(result.sentiment, FoodNewsSentiment.bad);
    });

    test('parses a Good result', () async {
      final service = _service(
        '{"summary":"No negative news discovered","sentiment":"Good"}',
      );
      final result = await service.getNews('bananas');
      expect(result.summary, 'No negative news discovered');
      expect(result.sentiment, FoodNewsSentiment.good);
    });

    test('falls back to the fixed message on an empty summary', () async {
      final service = _service('{"summary":"","sentiment":"Good"}');
      final result = await service.getNews('bananas');
      expect(result.summary, 'No negative news discovered');
      expect(result.sentiment, FoodNewsSentiment.good);
    });

    test('throws StateError on an invalid sentiment', () async {
      final service = _service('{"summary":"x","sentiment":"Neutral"}');
      expect(() => service.getNews('bananas'), throwsStateError);
    });

    test('throws StateError on a non-JSON response', () async {
      final service = _service('sorry, I cannot help with that');
      expect(() => service.getNews('bananas'), throwsStateError);
    });
  });

  // Hits the real API with openRouterApiKey from lib/secrets.dart. Opt in with:
  //   flutter test --dart-define=FOODNEWS_LIVE_TEST=true --plain-name live
  test('live: food news for a common food', () async {
    if (!const bool.fromEnvironment('FOODNEWS_LIVE_TEST')) {
      markTestSkipped('Live test not requested; skipping.');
      return;
    }
    final service = FoodNewsService();
    final result = await service.getNews('eggs');
    service.close();
    // ignore: avoid_print
    print('Eggs: ${result.sentiment} — ${result.summary}');
    expect(result.summary, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
