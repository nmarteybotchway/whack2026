import 'health_condition.dart';
import 'preference.dart';

/// A food entry stored in Firestore at `food/{foodId}`.
///
/// Firestore has no set type, so `health_conditions` and `personal_prefs` are
/// stored as arrays of [HealthCondition.id]s and [Preference.id]s.
///
/// `alternatives` is a map from a [HealthCondition.id] or [Preference.id] to
/// substitutes suitable for someone with that condition or preference. When
/// [generalInfo] gives a reason for anyone to avoid the food, [generalKey]
/// maps to healthier substitutes; otherwise that key is absent:
///
/// ```json
/// "alternatives": {
///   "general": ["Roast chicken"],
///   "hypertension": ["Grilled chicken breast"],
///   "vegan": ["Tempeh bacon", "Smoked tofu"]
/// }
/// ```
class Food {
  const Food({
    required this.name,
    this.generalAlternatives = const [],
    this.healthAlternatives = const {},
    this.prefAlternatives = const {},
    this.healthConditions = const {},
    this.personalPrefs = const {},
    this.localNews = '',
    this.generalInfo = '',
  });

  /// Key in `alternatives` for healthier substitutes, present only when
  /// [generalInfo] is not empty.
  static const generalKey = 'general';

  /// Display name, e.g. `Peanut Butter`; stored as `food`.
  final String name;

  /// Healthier substitutes for anyone, given the reason in [generalInfo];
  /// empty when [generalInfo] is.
  final List<String> generalAlternatives;

  /// Substitutes suitable for someone with each health condition.
  final Map<HealthCondition, List<String>> healthAlternatives;

  /// Substitutes suitable for someone with each personal preference.
  final Map<Preference, List<String>> prefAlternatives;

  /// Health conditions this food clashes with.
  final Set<HealthCondition> healthConditions;

  /// Religious or dietary preferences this food clashes with, e.g. beef for
  /// [Preference.hinduism] or [Preference.vegetarian].
  final Set<Preference> personalPrefs;

  /// Current food-safety news (e.g. an outbreak or recall) naming the affected
  /// regions; empty when there is none.
  final String localNews;

  /// Why even a healthy person should avoid or limit this food (e.g. bacon
  /// is a processed meat high in salt); empty when the food is fine.
  final String generalInfo;

  bool get hasNews => localNews.isNotEmpty;

  /// Substitutes for a person with [conditions] and [prefs].
  ///
  /// Uses the lists for whichever of them this food has alternatives for,
  /// ranking substitutes that suit more of them first. Falls back to
  /// [generalAlternatives] when none apply, including when the person has no
  /// conditions or preferences at all; that is empty when the food is fine
  /// for them.
  List<String> alternativesFor({
    Set<HealthCondition> conditions = const {},
    Set<Preference> prefs = const {},
  }) {
    final lists = [
      for (final c in conditions) ?healthAlternatives[c],
      for (final p in prefs) ?prefAlternatives[p],
    ];
    if (lists.isEmpty) return generalAlternatives;

    final votes = <String, int>{};
    for (final list in lists) {
      for (final alt in list) {
        votes[alt] = (votes[alt] ?? 0) + 1;
      }
    }
    // Stable sort keeps each list's own order among equally ranked items.
    return votes.keys.toList()..sort((a, b) => votes[b]! - votes[a]!);
  }

  /// Document ID for [name]: lower-cased, trimmed, and with whitespace and
  /// `/` (which Firestore forbids in IDs) collapsed to `_`.
  static String idFor(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[\s/]+'), '_');

  String get id => idFor(name);

  /// Unknown condition and preference IDs are skipped so older clients
  /// tolerate new ones.
  factory Food.fromMap(Map<String, dynamic> data) {
    final alternatives = switch (data['alternatives']) {
      Map m => {
        for (final MapEntry(:key, :value) in m.entries)
          key as String: List<String>.from(value as List),
      },
      // Older documents stored one flat list.
      List l => {generalKey: List<String>.from(l)},
      _ => const <String, List<String>>{},
    };
    return Food(
      name: data['food'] as String,
      generalAlternatives: alternatives[generalKey] ?? const [],
      healthAlternatives: {
        for (final MapEntry(:key, :value) in alternatives.entries)
          ?HealthCondition.fromId(key): value,
      },
      prefAlternatives: {
        for (final MapEntry(:key, :value) in alternatives.entries)
          ?Preference.fromId(key): value,
      },
      healthConditions: {
        for (final id in List<String>.from(
          data['health_conditions'] ?? const [],
        ))
          ?HealthCondition.fromId(id),
      },
      personalPrefs: {
        for (final id in List<String>.from(data['personal_prefs'] ?? const []))
          ?Preference.fromId(id),
      },
      localNews: data['local_news'] as String? ?? '',
      generalInfo: data['general_info'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'food': name,
    'alternatives': {
      if (generalAlternatives.isNotEmpty) generalKey: generalAlternatives,
      for (final MapEntry(:key, :value) in healthAlternatives.entries)
        key.id: value,
      for (final MapEntry(:key, :value) in prefAlternatives.entries)
        key.id: value,
    },
    'health_conditions': [for (final c in healthConditions) c.id],
    'personal_prefs': [for (final p in personalPrefs) p.id],
    'local_news': localNews,
    'general_info': generalInfo,
  };
}
