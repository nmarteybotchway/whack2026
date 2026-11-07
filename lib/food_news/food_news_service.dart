import 'dart:convert';

import '../openrouter.dart';

/// How the latest news reflects on the food.
enum FoodNewsSentiment { good, bad }

/// The latest negative-news verdict for a food.
class FoodNewsResult {
  const FoodNewsResult({required this.summary, required this.sentiment});

  /// A ≤30-word summary of the latest breaking news, or the fixed
  /// "No negative news discovered" message when there is none.
  final String summary;

  final FoodNewsSentiment sentiment;
}

/// Looks up recent negative news about a food via OpenRouter.
///
/// The model is asked to access the internet and find breaking news about
/// outbreaks, recalls, discovered allergens, or potential issues such as
/// high carcinogen records, and to reply as JSON matching the food-news
/// schema: `{"summary":"string","sentiment":"Good"|"Bad"}`.
class FoodNewsService {
  /// Creates a service on top of a fresh [OpenRouterService].
  /// [client] can be replaced in tests.
  FoodNewsService({OpenRouterService? client})
      : _client = client ?? OpenRouterService();

  /// The fixed reply when the model finds no negative news.
  static const String noNewsMessage = 'No negative news discovered';

  static final Map<String, Object?> _schema = {
    'type': 'object',
    'properties': {
      'summary': {'type': 'string'},
      'sentiment': {'type': 'string', 'enum': ['Good', 'Bad']},
    },
    'required': ['summary', 'sentiment'],
    'additionalProperties': false,
  };

  final OpenRouterService _client;

  /// Returns the latest breaking news about [foodName], or the fixed
  /// [noNewsMessage] with [FoodNewsSentiment.good] when none is found.
  Future<FoodNewsResult> getNews(String foodName) async {
    final text = await _client.generate(
      prompt: 'Access the internet and search for the latest breaking news '
          'about "$foodName": outbreaks, recalls, discovered allergens, or '
          'potential issues such as records of high carcinogens. Reply with '
          'a summary of at most 30 words; if there is no such negative '
          'news, reply with exactly "$noNewsMessage". Set sentiment to '
          '"Bad" if there is negative news and "Good" if there is not.',
      responseSchema: _schema,
    );

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw StateError('FoodNewsService got non-JSON response: $text');
    }
    if (decoded is! Map || decoded['summary'] is! String) {
      throw StateError('FoodNewsService got an unexpected response: $text');
    }

    final summary = (decoded['summary'] as String).trim();
    final sentiment = switch (decoded['sentiment']) {
      'Good' => FoodNewsSentiment.good,
      'Bad' => FoodNewsSentiment.bad,
      _ => throw StateError(
          'FoodNewsService got an invalid sentiment: ${decoded['sentiment']}',
        ),
    };

    return FoodNewsResult(
      summary: summary.isEmpty ? noNewsMessage : summary,
      sentiment: sentiment,
    );
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
