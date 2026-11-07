import 'health_condition.dart';
import 'nutrient.dart';
import 'preference.dart';

/// A food entry stored in Firestore at `food/{foodId}`.
///
/// Firestore has no set type, so `health_conditions` and `personal_prefs` are
/// stored as arrays of [HealthCondition.id]s and [Preference.id]s.
///
/// `alternatives` maps a health condition, then a personal preference, to
/// substitutes suitable for someone with both. [HealthCondition.none] and
/// [Preference.none] stand for no condition or no preference, so `none.none`
/// holds healthier substitutes for anyone and exists only when [generalInfo]
/// is not empty:
///
/// ```json
/// "alternatives": {
///   "none":         {"none": ["Roast chicken"], "vegan": ["Smoked tofu"]},
///   "hypertension": {"none": ["Grilled chicken"], "vegan": ["Tofu"]}
/// }
/// ```
///
/// `nutrients` maps [Nutrient.id]s to the amount per 100 g in each
/// nutrient's [Nutrient.unit], e.g. `{"VITC": 53.2, "K": 184}`. It is
/// optional, so foods stored before it existed simply have none.
class Food {
  const Food({
    required this.name,
    this.alternatives = const {},
    this.healthConditions = const {},
    this.personalPrefs = const {},
    this.localNews = '',
    this.generalInfo = '',
    this.nutrients = const {},
  });

  /// Display name, e.g. `Peanut Butter`; stored as `food`.
  final String name;

  /// Substitutes by health condition, then personal preference, using
  /// [HealthCondition.none] and [Preference.none] for neither. none/none is
  /// absent unless [generalInfo] is set.
  final Map<HealthCondition, Map<Preference, List<String>>> alternatives;

  /// Health conditions this food clashes with; never [HealthCondition.none].
  final Set<HealthCondition> healthConditions;

  /// Religious or dietary preferences this food clashes with, e.g. beef for
  /// [Preference.hinduism] or [Preference.vegetarian]; never
  /// [Preference.none].
  final Set<Preference> personalPrefs;

  /// Current food-safety news (e.g. an outbreak or recall) naming the affected
  /// regions; empty when there is none.
  final String localNews;

  /// Why even a healthy person should avoid or limit this food (e.g. bacon
  /// is a processed meat high in salt); empty when the food is fine.
  final String generalInfo;

  /// Vitamins and minerals per 100 g, in each [Nutrient.unit]; nutrients
  /// that are absent are unknown or negligible.
  final Map<Nutrient, double> nutrients;

  bool get hasNews => localNews.isNotEmpty;

  /// Nutrients this food is a source of ([Nutrient.sourceThreshold]).
  Set<Nutrient> get richIn => {
    for (final MapEntry(key: n, value: amount) in nutrients.entries)
      if (n.sourceThreshold case final t? when amount >= t) n,
  };

  /// Nutrients to limit that this food is high in ([Nutrient.highThreshold]).
  Set<Nutrient> get highIn => {
    for (final MapEntry(key: n, value: amount) in nutrients.entries)
      if (n.highThreshold case final t? when amount >= t) n,
  };

  /// Substitutes for a person with [conditions] and [prefs].
  ///
  /// Looks up every pair of their conditions and preferences that this food
  /// has alternatives for, using `none` on a side where none of theirs
  /// apply, and ranks substitutes that suit more pairs first. Empty when the
  /// food is fine for them. [tieBreak] orders substitutes that suit the
  /// same number of pairs, e.g. by the nutrients the person is low on.
  List<String> alternativesFor({
    Set<HealthCondition> conditions = const {},
    Set<Preference> prefs = const {},
    Comparator<String>? tieBreak,
  }) {
    final matched = conditions.where(alternatives.containsKey);
    final lists = <List<String>>[];
    for (final c in matched.isEmpty ? [HealthCondition.none] : matched) {
      final row = alternatives[c] ?? const {};
      final prefsMatched = prefs.where(row.containsKey);
      for (final p in prefsMatched.isEmpty ? [Preference.none] : prefsMatched) {
        lists.addAll([?row[p]]);
      }
    }

    final votes = <String, int>{};
    for (final list in lists) {
      for (final alt in list) {
        votes[alt] = (votes[alt] ?? 0) + 1;
      }
    }
    // Stable sort keeps each list's own order among equally ranked items.
    return votes.keys.toList()..sort((a, b) {
      final byVotes = votes[b]! - votes[a]!;
      return byVotes != 0 || tieBreak == null ? byVotes : tieBreak(a, b);
    });
  }

  /// Document ID for [name]: lower-cased, trimmed, and with whitespace and
  /// `/` (which Firestore forbids in IDs) collapsed to `_`.
  static String idFor(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[\s/]+'), '_');

  String get id => idFor(name);

  /// Unknown condition, preference and nutrient IDs are skipped so older
  /// clients tolerate new ones, as are alternatives in an older, non-nested
  /// format.
  factory Food.fromMap(Map<String, dynamic> data) => Food(
    name: data['food'] as String,
    alternatives: {
      for (final MapEntry(key: h, value: row)
          in (data['alternatives'] as Map? ?? const {}).entries)
        if ((HealthCondition.fromId(h as String), row) case (final c?, Map row))
          c: {
            for (final MapEntry(key: p, value: alts) in row.entries)
              if ((Preference.fromId(p as String), alts) case (
                final pref?,
                List alts,
              ))
                pref: List<String>.from(alts),
          },
    },
    healthConditions: {
      for (final id in List<String>.from(data['health_conditions'] ?? const []))
        if (HealthCondition.fromId(id) case final c?
            when c != HealthCondition.none)
          c,
    },
    personalPrefs: {
      for (final id in List<String>.from(data['personal_prefs'] ?? const []))
        if (Preference.fromId(id) case final p? when p != Preference.none) p,
    },
    localNews: data['local_news'] as String? ?? '',
    generalInfo: data['general_info'] as String? ?? '',
    nutrients: Nutrient.parseAmounts(data['nutrients']),
  );

  Map<String, dynamic> toMap() => {
    'food': name,
    'alternatives': {
      for (final MapEntry(key: c, value: row) in alternatives.entries)
        c.id: {
          for (final MapEntry(key: p, value: alts) in row.entries) p.id: alts,
        },
    },
    'health_conditions': [for (final c in healthConditions) c.id],
    'personal_prefs': [for (final p in personalPrefs) p.id],
    'local_news': localNews,
    'general_info': generalInfo,
    'nutrients': {
      for (final MapEntry(:key, :value) in nutrients.entries) key.id: value,
    },
  };
}
