import 'package:cloud_firestore/cloud_firestore.dart';

import 'food.dart';
import 'food_repository.dart';
import 'health_condition.dart';
import 'preference.dart';

/// What the recommender decided about a food for a specific user.
class FoodRecommendation {
  const FoodRecommendation({
    required this.food,
    required this.found,
    this.hasNews = false,
    this.hasGeneralInfo = false,
    this.generalInfo,
    this.clashingConditions = const {},
    this.clashingPrefs = const {},
    this.alternatives = const [],
  });

  /// Display name of the food checked.
  final String food;

  /// False when the food is not in the `food` collection.
  final bool found;

  /// The food's [Food.localNews] is non-empty.
  final bool hasNews;

  /// The food's [Food.generalInfo] is non-empty.
  final bool hasGeneralInfo;

  /// Stored explanation for why this food may be unhealthy.
  final String? generalInfo;

  /// The user's health conditions this food clashes with.
  final Set<HealthCondition> clashingConditions;

  /// The user's preferences this food clashes with.
  final Set<Preference> clashingPrefs;

  /// Vote-ranked substitutes ([Food.alternativesFor]); empty when the food
  /// is fine or no alternative is stored for them.
  final List<String> alternatives;

  /// Any news, general info, or preference/health-data match.
  bool get shouldAvoid =>
      hasNews ||
      hasGeneralInfo ||
      clashingConditions.isNotEmpty ||
      clashingPrefs.isNotEmpty;

  /// The food exists and none of the reasons to avoid it apply.
  bool get canBuy => found && !shouldAvoid;
}

/// The user's preference and health profile parsed from `users/{uid}`.
class UserProfile {
  const UserProfile({this.prefs = const {}, this.conditions = const {}});

  final Set<Preference> prefs;
  final Set<HealthCondition> conditions;
}

/// Recommends whether a user can buy a food or should pick an alternative.
///
/// Loads the food from the `food` collection and the user's profile from
/// `users/{uid}`, then compares the user's preferences and health data
/// against the food's clash sets and `alternatives` map:
///
/// - no local news, no general info, and no matching preference or health
///   condition → the food is fine to buy ([FoodRecommendation.canBuy]).
/// - otherwise → the stored alternatives are recommended; when the user has
///   no specific match (news or general info only), [Food.alternativesFor]
///   resolves the `none`/`none` entry.
class FoodRecommendationService {
  /// [fetcher] and [userFetcher] can be replaced in tests; the defaults read
  /// `food/{Food.idFor(name)}` via [FoodRepository] and `users/{uid}`.
  FoodRecommendationService({
    Future<Food?> Function(String name)? fetcher,
    Future<Map<String, dynamic>?> Function(String uid)? userFetcher,
  }) : _fetcher = fetcher ?? FoodRepository().get,
       _userFetcher = userFetcher ?? _defaultUserFetcher;

  final Future<Food?> Function(String name) _fetcher;
  final Future<Map<String, dynamic>?> Function(String uid) _userFetcher;

  static Future<Map<String, dynamic>?> _defaultUserFetcher(String uid) async =>
      (await FirebaseFirestore.instance.collection('users').doc(uid).get())
          .data();

  /// The user's profile parsed from a `users/{uid}` document, matching how
  /// the settings page stores it: `religion` and `dietary` are label
  /// strings, `health_conditions` are [HealthCondition.id]s. Unknown
  /// entries are skipped, and a missing document yields an empty profile.
  static UserProfile parseProfile(Map<String, dynamic>? data) {
    final d = data ?? const {};
    return UserProfile(
      prefs: {
        for (final s in [
          ...List<String>.from(d['religion'] ?? const []),
          ...List<String>.from(d['dietary'] ?? const []),
        ])
          if (Preference.fromLabel(s) case final p? when p != Preference.none)
            p,
      },
      conditions: {
        for (final s in List<String>.from(d['health_conditions'] ?? const []))
          if (HealthCondition.fromId(s) case final c?
              when c != HealthCondition.none)
            c,
      },
    );
  }

  /// The decision for [food] for a person with [conditions] and [prefs].
  /// Pure — no Firestore — so it is directly unit-testable.
  static FoodRecommendation recommend(
    Food food, {
    Set<HealthCondition> conditions = const {},
    Set<Preference> prefs = const {},
  }) {
    final clashingConditions = food.healthConditions.intersection(conditions);
    final clashingPrefs = food.personalPrefs.intersection(prefs);
    final hasNews = food.hasNews;
    final hasGeneralInfo = food.generalInfo.trim().isNotEmpty;

    final fine =
        !hasNews &&
        !hasGeneralInfo &&
        clashingConditions.isEmpty &&
        clashingPrefs.isEmpty;
    if (fine) return FoodRecommendation(food: food.name, found: true);

    // Full sets, not just the clashing subsets: alternativesFor falls back
    // to `none` rows for anything unmatched, so a user with one clashing
    // and one non-clashing preference still gets the best substitutes.
    return FoodRecommendation(
      food: food.name,
      found: true,
      hasNews: hasNews,
      hasGeneralInfo: hasGeneralInfo,
      generalInfo: food.generalInfo,
      clashingConditions: clashingConditions,
      clashingPrefs: clashingPrefs,
      alternatives: food.alternativesFor(conditions: conditions, prefs: prefs),
    );
  }

  /// Loads [foodName] and [uid]'s profile and decides.
  Future<FoodRecommendation> recommendFor({
    required String uid,
    required String foodName,
  }) async {
    final food = await _fetcher(foodName);
    if (food == null) {
      return FoodRecommendation(food: foodName, found: false);
    }
    final profile = parseProfile(await _userFetcher(uid));
    return recommend(
      food,
      conditions: profile.conditions,
      prefs: profile.prefs,
    );
  }
}
