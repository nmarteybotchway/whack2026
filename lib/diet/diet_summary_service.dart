import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../food/health_condition.dart';
import '../food/nutrient.dart';
import '../openrouter/openrouter_service.dart';
import 'diet_window_service.dart';
import 'nutrient_insights.dart';

/// How the two-week diet reads overall.
enum DietSummaryRating { good, mixed, concerning }

/// One nutrient the user is short of (or over on, for sodium), with why it
/// matters for them specifically and foods that would fix it.
class DietSummaryGap {
  const DietSummaryGap({
    required this.nutrient,
    required this.detail,
    required this.risk,
    this.foods = const [],
  });

  final String nutrient;
  final String detail;
  final String risk;
  final List<String> foods;

  Map<String, dynamic> toJson() => {
    'nutrient': nutrient,
    'detail': detail,
    'risk': risk,
    'foods': foods,
  };
}

/// An AI review of the user's recent diet: what is going well for them, what
/// is missing, and what each gap could grow into given their conditions.
class DietSummary {
  const DietSummary({
    required this.rating,
    required this.headline,
    required this.goodPoints,
    required this.gaps,
  });

  final DietSummaryRating rating;
  final String headline;
  final List<String> goodPoints;
  final List<DietSummaryGap> gaps;

  Map<String, dynamic> toJson() => {
    'rating': rating.name,
    'headline': headline,
    'good_points': goodPoints,
    'gaps': [for (final g in gaps) g.toJson()],
  };

  static DietSummary fromJson(Map<String, dynamic> json) => DietSummary(
    rating: DietSummaryRating.values.firstWhere(
      (r) => r.name == json['rating'],
      orElse: () => DietSummaryRating.mixed,
    ),
    headline: '${json['headline'] ?? ''}',
    goodPoints: [
      for (final s in (json['good_points'] as List? ?? const []))
        if (s is String && s.isNotEmpty) s,
    ],
    gaps: [
      for (final g in (json['gaps'] as List? ?? const []))
        if (g is Map)
          DietSummaryGap(
            nutrient: '${g['nutrient'] ?? ''}',
            detail: '${g['detail'] ?? ''}',
            risk: '${g['risk'] ?? ''}',
            foods: [
              for (final f in (g['foods'] as List? ?? const []))
                if (f is String && f.isNotEmpty) f,
            ],
          ),
    ],
  );
}

/// Thrown by [DietSummaryService.summarize] when the user has no tracked
/// days, so there is nothing to summarise yet.
class NoDietDataException implements Exception {
  const NoDietDataException();

  @override
  String toString() => 'No diet data to summarise yet.';
}

/// A receipt day as `yyyy-MM-dd`, matching the stored document ids.
String _formatDay(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// Builds the AI diet summary shown on the history page: recent receipt days,
/// their aggregated nutrients, and the user's saved profile, reviewed by the
/// OpenRouter model into a grounded verdict.
class DietSummaryService {
  DietSummaryService({OpenRouterService? ai}) : _ai = ai ?? OpenRouterService();

  final OpenRouterService _ai;

  /// Closes the underlying OpenRouter client.
  void dispose() => _ai.close();

  /// Summarises [userId]'s last two weeks. Returns null when nothing is
  /// tracked yet.
  Future<DietSummary?> summarize(String userId) async {
    final (days, insights, profile) = await (
      DietWindowService(userId).recentDays(),
      NutrientInsights.load(userId),
      FirebaseFirestore.instance.collection('users').doc(userId).get(),
    ).wait;
    if (insights.trackedDays == 0 || days.isEmpty) {
      throw const NoDietDataException();
    }

    final prompt = _prompt(
      days: days,
      insights: insights,
      profile: profile.data(),
    );
    final text = await _ai.generate(prompt: prompt, responseSchema: _schema);
    return DietSummary.fromJson(_decodeObject(text));
  }

  /// Extracts the JSON object from the model's reply. The preset route does
  /// not honour OpenRouter's strict-schema flag, so the reply may be wrapped
  /// in markdown fences or prose; the outermost braces are the object.
  static Map<String, dynamic> _decodeObject(String text) {
    final cleaned = text.trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Summary reply contained no JSON object.');
    }
    final dynamic json;
    try {
      json = jsonDecode(cleaned.substring(start, end + 1));
    } on FormatException {
      throw const FormatException('Summary was not valid JSON.');
    }
    if (json is! Map) throw const FormatException('Summary was not an object.');
    return Map<String, dynamic>.from(json);
  }

  /// The strict JSON schema the model must reply with.
  static final Map<String, Object?> _schema = {
    'type': 'object',
    'properties': {
      'rating': {
        'type': 'string',
        'enum': ['good', 'mixed', 'concerning'],
      },
      'headline': {'type': 'string'},
      'good_points': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'gaps': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'nutrient': {'type': 'string'},
            'detail': {'type': 'string'},
            'risk': {'type': 'string'},
            'foods': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['nutrient', 'detail', 'risk', 'foods'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['rating', 'headline', 'good_points', 'gaps'],
    'additionalProperties': false,
  };

  /// Builds the user prompt from the window's days, their nutrient coverage
  /// and the profile document.
  String _prompt({
    required List<DietDay> days,
    required NutrientInsights insights,
    required Map<String, dynamic>? profile,
  }) {
    final d = profile ?? const {};
    String list(String key) {
      final values = [
        for (final v in List<String>.from(d[key] ?? const [])) v.trim(),
      ].where((v) => v.isNotEmpty).toList();
      return values.isEmpty ? 'none' : values.join(', ');
    }

    String conditionList() {
      final labels = [
        for (final id in List<String>.from(d['health_conditions'] ?? const []))
          if (HealthCondition.fromId(id) case final c? when c != HealthCondition.none)
            c.label,
        for (final raw in List<String>.from(d['health_conditions'] ?? const []))
          if (HealthCondition.fromId(raw) == null) raw,
      ].where((l) => l.trim().isNotEmpty).toList();
      return labels.isEmpty ? 'none' : labels.join(', ');
    }

    String amount(double value) => value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(value >= 10 ? 1 : 2);

    String statusWord(NutrientStatus status) => switch (status) {
      NutrientStatus.lacking => 'well below target',
      NutrientStatus.low => 'below target',
      NutrientStatus.good => 'on track',
      NutrientStatus.high => 'OVER the limit',
    };

    final nutrientLines = [
      for (final c in insights.coverage)
        '- ${c.target.label}: ${amount(c.average)} '
        '${Nutrient.fromId(c.key)?.unit ?? ''} per day '
        '(${c.target.isLimit ? 'limit' : 'target'} '
        '${amount(c.target.daily)} ${Nutrient.fromId(c.key)?.unit ?? ''}) '
        '— ${statusWord(c.status)}',
    ].join('\n');

    // Day-by-day receipts, oldest first, so the model can compare days and
    // spot streaks and slips rather than only seeing averages.
    String dayLines() {
      final chronological = [...days]..sort((a, b) => a.date.compareTo(b.date));
      return [
        for (final day in chronological)
          '- ${_formatDay(day.date)}: ${day.foods.join(', ')}',
      ].join('\n');
    }

    return '''
You are the nutrition coach inside a grocery-scanning app. Review this
person's diet for the last two weeks, based on groceries scanned from their
receipts (so quantities reflect purchases, not exact portions eaten).

Their profile:
- Religion: ${list('religion')}
- Dietary preferences: ${list('dietary')}
- Health conditions: ${conditionList()}
- Days with tracked groceries: ${insights.trackedDays} of ${insights.days}

Day-by-day receipts, oldest first:
${dayLines()}

Nutrients (average per day across those days, from USDA data on the foods):
$nutrientLines

Write a short, personal review in second person. Rules:
- good_points: at most 2 items; each one short sentence on what is on
  track, naming the condition or preference it helps when relevant.
- gaps: at most 3 items, most important first. detail is one short
  sentence on the shortfall; risk is one short sentence on how it could
  grow into a bigger problem for their conditions or preferences (e.g.
  low iron mattering more in pregnancy; sodium with hypertension).
- foods: 2 or 3 concrete buys that fix the gap and respect their religion
  and dietary preferences (never pork to a halal or Jewish shopper, meat
  to a vegetarian, dairy to a vegan, and so on).
- Only describe patterns actually in the receipts and nutrient data; the
  day-by-day lines let you name specific days and streaks. Be honest.
- Tone: warm but firm. If their choices work against a health condition
  they told us about, say plainly that this is the time to lock in. Never
  diagnose, never moralise beyond their own conditions.
- headline under 12 words; every other string under 15 words. No medical
  diagnosis, no disclaimers.

Reply with ONLY a JSON object — no markdown fences, no commentary — with
exactly these keys:
{"rating": "good" | "mixed" | "concerning", "headline": "...",
 "good_points": ["..."], "gaps": [{"nutrient": "...", "detail": "...",
 "risk": "...", "foods": ["..."]}]}
''';
  }
}
