import 'package:cloud_firestore/cloud_firestore.dart';

import '../assistant/assistant_models.dart';
import '../food/food.dart';
import '../food/food_matcher.dart';
import '../food/food_recommendation_service.dart';
import '../food/health_condition.dart';
import '../food/preference.dart';
import 'product_identification_service.dart';

/// A spoken scan summary plus a small set of visual substitute cards.
class ProductBriefing {
  const ProductBriefing({
    required this.key,
    required this.name,
    required this.text,
    this.alternatives = const [],
    this.facts = const {},
  });

  final String key;
  final String name;

  /// Deterministic fallback wording, spoken only when the model is unavailable.
  final String text;
  final List<CompanionAlternative> alternatives;

  /// JSON-safe personal assessment the assistant phrases its reply from.
  final Map<String, Object?> facts;
}

/// A substitute that passed the stored recommendation checks.
class CompanionAlternative {
  const CompanionAlternative({
    required this.name,
    this.image,
    this.detail = '',
  });

  final String name;
  final AssistantImage? image;
  final String detail;
}

/// Stable identity for deduplicating repeat product scans.
String productKeyFor(ProductIdentification product) {
  final gtin = _clean(product.gtin);
  if (gtin.isNotEmpty) return 'gtin:$gtin';
  final catalogId = _clean(product.catalogProductId);
  if (catalogId.isNotEmpty) return 'catalog:$catalogId';
  final parts = [
    ('name', product.productName),
    ('brand', product.brand),
    ('variant', product.variant),
    ('size', product.packageSize),
  ].map((e) => '${e.$1}:${_normalize(e.$2 ?? '')}').toList();
  return parts.join('|');
}

String _clean(String? value) => value?.trim() ?? '';
String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// Produces grounded, deterministic spoken scan guidance.
///
/// Recommendations, profile constraints, nutrient status, alerts and
/// declined swaps are owned by [FoodRecommendationService]. This class only
/// renders those decisions and resolves optional image cards.
class ProductBriefingService {
  ProductBriefingService({
    required this.userId,
    FoodRecommendationService? recommendations,
    Future<AssistantImage?> Function(String name)? imageLoader,
    Future<Map<String, dynamic>?> Function(String uid)? profileLoader,
  }) : _recommendations = recommendations ?? FoodRecommendationService(),
       _imageLoader = imageLoader ?? _loadImage,
       _profileLoader = profileLoader ?? _loadProfile;

  final String userId;
  final FoodRecommendationService _recommendations;
  final Future<AssistantImage?> Function(String name) _imageLoader;
  final Future<Map<String, dynamic>?> Function(String uid) _profileLoader;

  Future<ProductBriefing> describe(ProductIdentification product) async {
    final name = product.displayName.trim().isEmpty
        ? product.productName?.trim() ?? 'Unidentified product'
        : product.displayName.trim();
    final key = productKeyFor(product);
    final lookupName = _lookupName(product);
    if (lookupName.isEmpty || product.status == 'unreadable') {
      return ProductBriefing(
        key: key,
        name: name,
        text: 'I could not identify this product clearly. I can’t assess its suitability from the scan.',
        facts: {'product': name, 'verdict': 'unidentified'},
      );
    }

    final FoodRecommendation recommendation;
    final List<String> unknownConstraints;
    try {
      final results = await (
        _recommendations.recommendFor(uid: userId, foodName: lookupName),
        _profileLoader(userId),
      ).wait;
      recommendation = results.$1;
      unknownConstraints = _unknownConstraints(results.$2);
    } catch (_) {
      return ProductBriefing(
        key: key,
        name: name,
        text:
            'I could not load the stored food and profile data for $name. I can’t assess its suitability right now.',
        facts: {'product': name, 'verdict': 'unavailable'},
      );
    }
    if (!recommendation.found) {
      return ProductBriefing(
        key: key,
        name: name,
        text:
            'I could not match $name to the food catalog. I can’t assess its suitability from the available data.',
        facts: {'product': name, 'verdict': 'not_in_catalog'},
      );
    }

    final ambiguous = product.status != 'identified';
    final reason = _reason(recommendation);
    final alternatives = <CompanionAlternative>[];
    if (recommendation.shouldAvoid && !recommendation.swapDeclined) {
      for (final candidate in recommendation.alternatives) {
        if (alternatives.length >= 3) break;
        try {
          final check = await _recommendations.recommendFor(
            uid: userId,
            foodName: candidate,
          );
          if (!check.found ||
              check.shouldAvoid ||
              check.profile.declinedSwaps.contains(
                FoodRecommendationService.swapKey(candidate),
              )) {
            continue;
          }
          AssistantImage? image;
          try {
            image = await _imageLoader(candidate);
          } catch (_) {
            // Missing image metadata never blocks spoken guidance.
          }
          alternatives.add(
            CompanionAlternative(
              name: candidate,
              image: image,
              detail: _alternativeDetail(check, unknownConstraints),
            ),
          );
        } catch (_) {
          // An unavailable candidate cannot be presented as compatible.
        }
      }
    }

    final text = _spokenSummary(
      name: name,
      matchedName: recommendation.food,
      ambiguous: ambiguous,
      confidence: product.confidence,
      recommendation: recommendation,
      reason: reason,
      alternatives: alternatives,
      unknownConstraints: unknownConstraints,
    );
    return ProductBriefing(
      key: key,
      name: name,
      text: text,
      alternatives: alternatives,
      facts: _facts(
        name: name,
        product: product,
        recommendation: recommendation,
        alternatives: alternatives,
        unknownConstraints: unknownConstraints,
      ),
    );
  }

  static Map<String, Object?> _facts({
    required String name,
    required ProductIdentification product,
    required FoodRecommendation recommendation,
    required List<CompanionAlternative> alternatives,
    required List<String> unknownConstraints,
  }) {
    final profile = recommendation.profile;
    final info = recommendation.generalInfo?.trim() ?? '';
    final news = recommendation.news?.trim() ?? '';
    return {
      'product': name,
      'matchedFood': recommendation.food,
      'identificationCertain': product.status == 'identified',
      'verdict': recommendation.shouldAvoid ? 'avoid' : 'good',
      'reasonsToAvoid': {
        if (news.isNotEmpty) 'foodAlert': news,
        if (recommendation.hasGeneralInfo && info.isNotEmpty)
          'healthNote': info,
        if (recommendation.clashingPrefs.isNotEmpty)
          'conflictsWithUserPreferences': [
            for (final v in recommendation.clashingPrefs) v.label,
          ],
        if (recommendation.clashingConditions.isNotEmpty)
          'conflictsWithUserHealthConditions': [
            for (final v in recommendation.clashingConditions) v.label,
          ],
        if (recommendation.excessNutrients.isNotEmpty)
          'highInNutrientsUserIsAlreadyOver': [
            for (final v in recommendation.excessNutrients) v.label,
          ],
      },
      if (recommendation.boostsNutrients.isNotEmpty)
        'richInNutrientsUserIsLowOn': [
          for (final v in recommendation.boostsNutrients) v.label,
        ],
      'user': {
        'preferences': [for (final v in profile.prefs) v.label],
        'healthConditions': [for (final v in profile.conditions) v.label],
        'lowNutrients': [for (final v in profile.lowNutrients) v.label],
        'overNutrients': [for (final v in profile.highNutrients) v.label],
        if (unknownConstraints.isNotEmpty)
          'unassessedConstraints': unknownConstraints,
      },
      if (recommendation.swapDeclined) 'userDeclinedSwapsForThisFood': true,
      'verifiedAlternatives': [
        for (final a in alternatives) {'name': a.name, 'why': a.detail},
      ],
    };
  }

  static String _lookupName(ProductIdentification product) {
    final name = product.productName?.trim() ?? '';
    final candidate = name.isNotEmpty ? name : product.displayName.trim();
    return (matchKnownFood(candidate) ?? matchKnownFood(product.displayName))
            ?.food
            .name ??
        candidate;
  }

  static String _reason(FoodRecommendation recommendation) {
    final info = _conciseInfo(recommendation.generalInfo ?? '');
    final prefs = recommendation.clashingPrefs
        .map((p) => p.label)
        .take(2)
        .toList();
    final conditions = recommendation.clashingConditions
        .map((c) => c.label)
        .take(2)
        .toList();
    final nutrients = recommendation.excessNutrients
        .map((n) => n.label.toLowerCase())
        .take(2)
        .toList();
    final reasons = <String>[
      if (recommendation.hasNews) 'there is a stored food alert',
      if (prefs.isNotEmpty)
        'it conflicts with ${prefs.join(' and ')}${recommendation.clashingPrefs.length > prefs.length ? ' and other preferences' : ''}',
      if (conditions.isNotEmpty)
        'it conflicts with ${conditions.join(' and ')}${recommendation.clashingConditions.length > conditions.length ? ' and other health conditions' : ''}',
      if (nutrients.isNotEmpty)
        'it is high in ${nutrients.join(' and ')}, which your recent diet is already over the limit for',
      if (recommendation.hasGeneralInfo && info.isNotEmpty) info,
    ];
    return _boundedSpeech(reasons.join('; '), max: 260);
  }

  static String _spokenSummary({
    required String name,
    required String matchedName,
    required bool ambiguous,
    required int confidence,
    required FoodRecommendation recommendation,
    required String reason,
    required List<CompanionAlternative> alternatives,
    required List<String> unknownConstraints,
  }) {
    final confidenceText = confidence > 0 ? ' ($confidence% match)' : '';
    final subject = ambiguous
        ? 'The scanned product $name may match $matchedName$confidenceText, but the identification is uncertain. '
        : '';
    if (recommendation.shouldAvoid) {
      final core = reason.isEmpty
          ? 'stored information flags this food'
          : reason;
      final prefix = ambiguous ? subject : '$name: ';
      if (alternatives.isEmpty) {
        final declined = recommendation.swapDeclined
            ? ' You have turned off substitute suggestions for this food.'
            : ' I could not verify a suitable substitute in the stored catalog.';
        final unknown = unknownConstraints.isEmpty
            ? ''
            : ' Compatibility with ${unknownConstraints.join(', ')} is unknown.';
        return _boundedSpeech('$prefix$core.$declined$unknown');
      }
      final names = alternatives.take(2).map((a) => a.name).toList();
      final unknown = unknownConstraints.isEmpty
          ? ''
          : ' Their compatibility with ${unknownConstraints.join(', ')} is unknown.';
      return _boundedSpeech(
        '$prefix$core. You could try ${names.join(' or ')} instead.$unknown',
      );
    }

    if (ambiguous) {
      final custom = unknownConstraints.isEmpty
          ? ''
          : ' Stored custom constraints are not mapped: ${unknownConstraints.join(', ')}.';
      return _boundedSpeech(
        '$subject The possible catalog match has no conflicts in known profile data, but I can’t confirm it describes this exact product.$custom',
      );
    }
    if (unknownConstraints.isNotEmpty) {
      return _boundedSpeech(
        '$name has no conflicts with recognized profile data, but compatibility with ${unknownConstraints.join(', ')} is unknown.',
      );
    }
    final boosts = recommendation.boostsNutrients;
    if (boosts.isNotEmpty) {
      return _boundedSpeech(
        '$name has no known stored conflicts. It may help with ${boosts.take(2).map((n) => n.label.toLowerCase()).join(' and ')}, which are low in your recent diet.',
      );
    }
    return _boundedSpeech(
      '$name has no known alerts or conflicts in the stored food and profile data.',
    );
  }

  static String _alternativeDetail(
    FoodRecommendation recommendation,
    List<String> unknownConstraints,
  ) {
    final detail = recommendation.boostsNutrients.isEmpty
        ? 'No known conflicts in the stored profile and food data.'
        : 'May help with ${recommendation.boostsNutrients.map((n) => n.label.toLowerCase()).join(' and ')}, which are low in your recent diet.';
    if (unknownConstraints.isEmpty) return detail;
    return '$detail Compatibility with ${unknownConstraints.join(', ')} is unknown.';
  }

  static List<String> _unknownConstraints(Map<String, dynamic>? profile) {
    if (profile == null) return const [];
    List<String> values(String field) =>
        profile[field] is List ? List<String>.from(profile[field]) : const [];
    final unknown = <String>{
      for (final value in [...values('religion'), ...values('dietary')])
        if (Preference.fromLabel(value) == null &&
            Preference.fromId(value) == null &&
            !Preference.otherBeliefs.any(
              (b) => b.toLowerCase() == value.toLowerCase(),
            ))
          value,
      for (final value in values('health_conditions'))
        if (HealthCondition.fromId(value) == null) value,
    };
    return (unknown.toList()..sort()).take(3).toList();
  }

  static String _conciseInfo(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return '';
    final firstSentence = normalized.split(RegExp(r'(?<=[.!?])\s+')).first;
    return _boundedSpeech(
      firstSentence,
      max: 100,
    ).replaceFirst(RegExp(r'[.!?]+$'), '');
  }

  static String _boundedSpeech(String value, {int max = 480}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= max) return normalized;
    var end = normalized.lastIndexOf(' ', max - 1);
    if (end < max ~/ 2) end = max - 1;
    return '${normalized.substring(0, end).trimRight()}…';
  }

  static Future<Map<String, dynamic>?> _loadProfile(String uid) async =>
      (await FirebaseFirestore.instance.collection('users').doc(uid).get())
          .data();

  static Future<AssistantImage?> _loadImage(String name) async {
    final id = Food.idFor(name);
    final data =
        (await FirebaseFirestore.instance
                .collection('food_images')
                .doc(id)
                .get())
            .data();
    if (data == null ||
        Food.idFor(data['name'] is String ? data['name'] as String : '') !=
            id) {
      return null;
    }
    final url = data['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri?.scheme != 'https' || uri?.host.isNotEmpty != true) return null;
    final page = data['page'];
    final pageUri = page is String ? Uri.tryParse(page) : null;
    return AssistantImage(
      foodId: id,
      name: data['name'] as String,
      url: url as String,
      sourcePage: pageUri?.scheme == 'https' && pageUri!.host.isNotEmpty
          ? page as String
          : '',
    );
  }
}
