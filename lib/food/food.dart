import 'health_condition.dart';
import 'preference.dart';

/// A food entry stored in Firestore at `food/{foodId}`.
///
/// Firestore has no set type, so `health_conditions` and `personal_prefs` are
/// stored as arrays of [HealthCondition.id]s and [Preference.id]s.
class Food {
  const Food({
    required this.name,
    this.alternatives = const [],
    this.healthConditions = const {},
    this.personalPrefs = const {},
    this.localNews = '',
    this.generalInfo = '',
  });

  /// Display name, e.g. `Peanut Butter`; stored as `food`.
  final String name;

  /// Suggested substitutes, in order of preference.
  final List<String> alternatives;

  /// Health conditions this food clashes with.
  final Set<HealthCondition> healthConditions;

  /// Religious or dietary preferences this food clashes with, e.g. beef for
  /// [Preference.hinduism] or [Preference.vegetarian].
  final Set<Preference> personalPrefs;

  /// Current food-safety news (e.g. an outbreak or recall) naming the affected
  /// regions; empty when there is none.
  final String localNews;

  /// A short general description of the food and its nutrition.
  final String generalInfo;

  bool get hasNews => localNews.isNotEmpty;

  /// Document ID for [name]: lower-cased, trimmed, and with whitespace and
  /// `/` (which Firestore forbids in IDs) collapsed to `_`.
  static String idFor(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[\s/]+'), '_');

  String get id => idFor(name);

  /// Unknown condition and preference IDs are skipped so older clients
  /// tolerate new ones.
  factory Food.fromMap(Map<String, dynamic> data) => Food(
    name: data['food'] as String,
    alternatives: List<String>.from(data['alternatives'] ?? const []),
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
    'alternatives': alternatives,
    'health_conditions': [for (final c in healthConditions) c.id],
    'personal_prefs': [for (final p in personalPrefs) p.id],
    'local_news': localNews,
    'general_info': generalInfo,
  };
}
