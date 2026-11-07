import 'package:cloud_firestore/cloud_firestore.dart';

import '../diet/nutrient_insights.dart';
import 'food.dart';
import 'food_repository.dart';
import 'health_condition.dart';
import 'nutrient.dart';
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
    this.excessNutrients = const {},
    this.boostsNutrients = const {},
    this.alternatives = const [],
    this.swapDeclined = false,
    this.profile = const UserProfile(),
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

  /// Nutrients the user's recent diet is already over the limit on that this
  /// food is high in ([Food.highIn]), e.g. sodium.
  final Set<Nutrient> excessNutrients;

  /// Nutrients the user's recent diet is low on that this food is a source
  /// of ([Food.richIn]). A reason to buy it, so it never makes the food one
  /// to avoid.
  final Set<Nutrient> boostsNutrients;

  /// Vote-ranked substitutes ([Food.alternativesFor]); empty when the food
  /// is fine, no alternative is stored for them, or [swapDeclined].
  final List<String> alternatives;

  /// The user turned off swap suggestions for this food
  /// ([UserProfile.declinedSwaps]); the reasons to avoid it are still
  /// reported, but no [alternatives] are offered.
  final bool swapDeclined;

  /// The profile the decision was made against, so callers can check
  /// substitutes for the same conditions and preferences.
  final UserProfile profile;

  /// Any news, general info, preference/health-data match, or nutrient the
  /// user already has too much of.
  bool get shouldAvoid =>
      hasNews ||
      hasGeneralInfo ||
      clashingConditions.isNotEmpty ||
      clashingPrefs.isNotEmpty ||
      excessNutrients.isNotEmpty;

  /// The food exists and none of the reasons to avoid it apply.
  bool get canBuy => found && !shouldAvoid;
}

/// The user's preference and health profile parsed from `users/{uid}`, plus
/// the nutrient gaps and excesses of their recent diet.
class UserProfile {
  const UserProfile({
    this.prefs = const {},
    this.conditions = const {},
    this.lowNutrients = const {},
    this.highNutrients = const {},
    this.declinedSwaps = const {},
  });

  final Set<Preference> prefs;
  final Set<HealthCondition> conditions;

  /// Nutrients the user is lacking or low on ([NutrientInsights.gaps]).
  final Set<Nutrient> lowNutrients;

  /// Nutrients to limit that the user is over ([NutrientStatus.high]).
  final Set<Nutrient> highNutrients;

  /// [FoodRecommendationService.swapKey]s of foods the user chose to keep
  /// buying, stored as `ignored_swap_items` by the scan result sheet.
  final Set<String> declinedSwaps;
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
///
/// Foods with `nutrients` are also checked against the user's
/// [NutrientInsights] over the [DietWindowService] window (receipts plus
/// foods logged through the assistant, as on the nutrient tracker): a food
/// high in a nutrient they are already over the limit on is to be avoided, one rich in a nutrient they are low on is flagged as a
/// boost, and substitutes covering more of their low nutrients rank first.
///
/// Foods the user declined swaps for (`ignored_swap_items`) keep their
/// reasons but get no alternatives ([FoodRecommendation.swapDeclined]).
class FoodRecommendationService {
  /// [fetcher], [userFetcher] and [insightsFetcher] can be replaced in
  /// tests; the defaults read `food/{Food.idFor(name)}` via
  /// [FoodRepository], `users/{uid}`, and [NutrientInsights.load].
  FoodRecommendationService({
    Future<Food?> Function(String name)? fetcher,
    Future<Map<String, dynamic>?> Function(String uid)? userFetcher,
    Future<NutrientInsights> Function(String uid)? insightsFetcher,
  }) : _fetcher = fetcher ?? FoodRepository().get,
       _userFetcher = userFetcher ?? _defaultUserFetcher,
       _insightsFetcher = insightsFetcher ?? NutrientInsights.load;

  final Future<Food?> Function(String name) _fetcher;
  final Future<Map<String, dynamic>?> Function(String uid) _userFetcher;
  final Future<NutrientInsights> Function(String uid) _insightsFetcher;

  static Future<Map<String, dynamic>?> _defaultUserFetcher(String uid) async =>
      (await FirebaseFirestore.instance.collection('users').doc(uid).get())
          .data();

  /// The `ignored_swap_items` key for a food [name]: trimmed, lower-cased,
  /// with whitespace runs collapsed, as the scan result sheet writes it.
  static String swapKey(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// The user's profile parsed from a `users/{uid}` document, matching how
  /// the settings page stores it: `religion` and `dietary` are label
  /// strings, `health_conditions` are [HealthCondition.id]s, and
  /// `ignored_swap_items` are [swapKey]s (re-normalized on read). Unknown
  /// entries are skipped, and a missing document yields an empty profile.
  ///
  /// Low and high nutrients come from [insights]; with none, or nothing
  /// tracked yet, nothing is low or high rather than everything low.
  static UserProfile parseProfile(
    Map<String, dynamic>? data, {
    NutrientInsights? insights,
  }) {
    final d = data ?? const {};
    final coverage = insights == null || insights.isEmpty
        ? const <NutrientCoverage>[]
        : insights.coverage;
    Set<Nutrient> withStatus(Set<NutrientStatus> statuses) => {
      for (final c in coverage)
        if (statuses.contains(c.status)) ?Nutrient.fromId(c.key),
    };
    return UserProfile(
      prefs: {
        for (final s in [
          ...List<String>.from(d['religion'] ?? const []),
          ...List<String>.from(d['dietary'] ?? const []),
        ])
          if (Preference.fromLabel(s) ?? Preference.fromId(s) case final p?
              when p != Preference.none)
            p,
      },
      conditions: {
        for (final s in List<String>.from(d['health_conditions'] ?? const []))
          if (HealthCondition.fromId(s) case final c?
              when c != HealthCondition.none)
            c,
      },
      lowNutrients: withStatus({NutrientStatus.lacking, NutrientStatus.low}),
      highNutrients: withStatus({NutrientStatus.high}),
      declinedSwaps: {
        for (final s in List<String>.from(d['ignored_swap_items'] ?? const []))
          if (swapKey(s) case final k when k.isNotEmpty) k,
      },
    );
  }

  /// The decision for [food] for a person with [conditions], [prefs], and a
  /// recent diet low in [lowNutrients] and over the limit on
  /// [highNutrients]. [alternativeFoods], keyed by [Food.idFor], gives the
  /// nutrients of stored substitutes so those covering more of
  /// [lowNutrients] rank first. A food whose [swapKey] is in
  /// [declinedSwaps] is still judged, but offers no alternatives. Pure — no
  /// Firestore — so it is directly unit-testable.
  static FoodRecommendation recommend(
    Food food, {
    Set<HealthCondition> conditions = const {},
    Set<Preference> prefs = const {},
    Set<Nutrient> lowNutrients = const {},
    Set<Nutrient> highNutrients = const {},
    Set<String> declinedSwaps = const {},
    Map<String, Food> alternativeFoods = const {},
  }) {
    final profile = UserProfile(
      prefs: prefs,
      conditions: conditions,
      lowNutrients: lowNutrients,
      highNutrients: highNutrients,
      declinedSwaps: declinedSwaps,
    );
    final clashingConditions = food.healthConditions.intersection(conditions);
    final clashingPrefs = food.personalPrefs.intersection(prefs);
    final excessNutrients = food.highIn.intersection(highNutrients);
    final boostsNutrients = food.richIn.intersection(lowNutrients);
    final hasNews = food.hasNews;
    final hasGeneralInfo = food.generalInfo.trim().isNotEmpty;

    final fine =
        !hasNews &&
        !hasGeneralInfo &&
        clashingConditions.isEmpty &&
        clashingPrefs.isEmpty &&
        excessNutrients.isEmpty;
    if (fine) {
      return FoodRecommendation(
        food: food.name,
        found: true,
        boostsNutrients: boostsNutrients,
        profile: profile,
      );
    }
    final swapDeclined = declinedSwaps.contains(swapKey(food.name));

    int boosts(String alt) => switch (alternativeFoods[Food.idFor(alt)]) {
      final f? => f.richIn.intersection(lowNutrients).length,
      null => 0,
    };

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
      excessNutrients: excessNutrients,
      boostsNutrients: boostsNutrients,
      alternatives: swapDeclined
          ? const []
          : food.alternativesFor(
              conditions: conditions,
              prefs: prefs,
              tieBreak: (a, b) => boosts(b) - boosts(a),
            ),
      swapDeclined: swapDeclined,
      profile: profile,
    );
  }

  /// Loads [foodName], [uid]'s profile (including declined swaps) and recent
  /// diet, and decides. When the user is low on any nutrient, the
  /// substitutes are loaded too so they can be ranked by what they provide.
  Future<FoodRecommendation> recommendFor({
    required String uid,
    required String foodName,
  }) async {
    final food = await _fetcher(foodName);
    if (food == null) {
      return FoodRecommendation(food: foodName, found: false);
    }
    final (data, insights) = await (_userFetcher(uid), _loadInsights(uid)).wait;
    final profile = parseProfile(data, insights: insights);
    FoodRecommendation decide([
      Map<String, Food> alternativeFoods = const {},
    ]) => recommend(
      food,
      conditions: profile.conditions,
      prefs: profile.prefs,
      lowNutrients: profile.lowNutrients,
      highNutrients: profile.highNutrients,
      declinedSwaps: profile.declinedSwaps,
      alternativeFoods: alternativeFoods,
    );

    final first = decide();
    if (profile.lowNutrients.isEmpty || first.alternatives.length < 2) {
      return first;
    }
    final alts = await Future.wait(
      first.alternatives.map((a) => _fetcher(a).catchError((_) => null)),
    );
    return decide({for (final f in alts.nonNulls) f.id: f});
  }

  /// The stored food named [name], read through the same fetcher as
  /// [recommendFor], e.g. to inspect a recommended substitute.
  Future<Food?> lookup(String name) => _fetcher(name);

  /// The user's nutrient insights; nutrient checks are best-effort, so a
  /// failed read just leaves them out.
  Future<NutrientInsights?> _loadInsights(String uid) async {
    try {
      return await _insightsFetcher(uid);
    } on Exception {
      return null;
    }
  }
}
