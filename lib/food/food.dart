import 'health_condition.dart';
import 'preference.dart';

/// A food entry stored in Firestore at `food/{foodId}`.
///
/// Firestore has no set type, so `health_conditions` and `personal_prefs` are
/// stored as arrays of [HealthCondition.id]s and [Preference.id]s.
///
/// `alternatives` maps a health condition, then a personal preference, to
/// substitutes suitable for someone with both. [noneKey] stands for no
/// condition or no preference, so `none.none` holds healthier substitutes for
/// anyone and exists only when [generalInfo] is not empty:
///
/// ```json
/// "alternatives": {
///   "none":         {"none": ["Roast chicken"], "vegan": ["Smoked tofu"]},
///   "hypertension": {"none": ["Grilled chicken"], "vegan": ["Tofu"]}
/// }
/// ```
class Food {
  const Food({
    required this.name,
    this.alternatives = const {},
    this.healthConditions = const {},
    this.personalPrefs = const {},
    this.localNews = '',
    this.generalInfo = '',
  });

  /// Key in `alternatives` for no health condition or no preference.
  static const noneKey = 'none';

  /// Display name, e.g. `Peanut Butter`; stored as `food`.
  final String name;

  /// Substitutes by health condition, then personal preference; a null key
  /// is [noneKey]. `alternatives[null]?[null]` is empty unless
  /// [generalInfo] is set.
  final Map<HealthCondition?, Map<Preference?, List<String>>> alternatives;

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
  /// Looks up every pair of their conditions and preferences that this food
  /// has alternatives for, using [noneKey] on a side where none of theirs
  /// apply, and ranks substitutes that suit more pairs first. Empty when the
  /// food is fine for them.
  List<String> alternativesFor({
    Set<HealthCondition> conditions = const {},
    Set<Preference> prefs = const {},
  }) {
    final matched = conditions.where(alternatives.containsKey);
    final rows = [
      for (final c in matched.isEmpty ? const [null] : matched)
        ?alternatives[c],
    ];
    final lists = [
      for (final row in rows)
        for (final p in [
          ...prefs.where(row.containsKey),
          if (!prefs.any(row.containsKey)) null,
        ])
          ?row[p],
    ];

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
  /// tolerate new ones, as are alternatives in an older, non-nested format.
  factory Food.fromMap(Map<String, dynamic> data) => Food(
    name: data['food'] as String,
    alternatives: {
      for (final MapEntry(key: h, value: row)
          in (data['alternatives'] as Map? ?? const {}).entries)
        if ((_key(h as String, HealthCondition.fromId), row) case (
          (final c,),
          Map row,
        ))
          c: {
            for (final MapEntry(key: p, value: alts) in row.entries)
              if ((_key(p as String, Preference.fromId), alts) case (
                (final pref,),
                List alts,
              ))
                pref: List<String>.from(alts),
          },
    },
    healthConditions: {
      for (final id in List<String>.from(data['health_conditions'] ?? const []))
        ?HealthCondition.fromId(id),
    },
    personalPrefs: {
      for (final id in List<String>.from(data['personal_prefs'] ?? const []))
        ?Preference.fromId(id),
    },
    localNews: data['local_news'] as String? ?? '',
    generalInfo: data['general_info'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'food': name,
    'alternatives': {
      for (final MapEntry(key: c, value: row) in alternatives.entries)
        c?.id ?? noneKey: {
          for (final MapEntry(key: p, value: alts) in row.entries)
            p?.id ?? noneKey: alts,
        },
    },
    'health_conditions': [for (final c in healthConditions) c.id],
    'personal_prefs': [for (final p in personalPrefs) p.id],
    'local_news': localNews,
    'general_info': generalInfo,
  };

  /// Parses an `alternatives` key: `(null,)` for [noneKey], `(value,)` for a
  /// known ID, or null to skip an unknown one.
  static (T?,)? _key<T>(String key, T? Function(String) fromId) {
    if (key == noneKey) return (null,);
    final value = fromId(key);
    return value == null ? null : (value,);
  }
}
