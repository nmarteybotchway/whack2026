import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../food/nutrient.dart';
import '../secrets.dart' show usdaApiKey;

/// The nutrients we track, as shorthand keys used in Firestore and the UI,
/// mapped to the standard unit values are normalised to before being summed
/// and stored. See [Nutrient] for what each shorthand means.
final nutrientUnits = <String, String>{
  for (final n in Nutrient.values) n.id: n.unit,
};
/// Looks up vitamins and minerals for a food via the USDA FoodData Central
/// search API, with a shared Firestore cache so repeat scans of the same
/// food cost no quota.
///
/// Values are normalised to the units in [nutrientUnits] (vitamin IU entries
/// are converted) so totals can simply be summed across foods.
class NutritionService {
  NutritionService({
    http.Client? client,
    String? apiKey,
    FirebaseFirestore? firestore,
  }) : _client = client ?? http.Client(),
       apiKey = apiKey ?? usdaApiKey,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final http.Client _client;
  final FirebaseFirestore _firestore;

  /// USDA API key; defaults to `usdaApiKey` from the git-ignored
  /// `lib/secrets.dart` (DEMO_KEY is rate-limited to 30 req/hour).
  final String apiKey;

  /// Total vitamins and minerals across all [foods].
  ///
  /// Foods with no USDA match (or failed lookups) are skipped silently —
  /// nutrition enrichment is best-effort.
  Future<Map<String, double>> totalsFor(List<String> foods) async {
    final totals = <String, double>{};
    for (final food in foods) {
      try {
        final nutrients = await nutrientsFor(food);
        nutrients.forEach((key, value) {
          totals[key] = (totals[key] ?? 0) + value;
        });
      } on Exception {
        continue;
      }
    }
    return totals;
  }

  /// Nutrients for one food, from the cache when present.
  Future<Map<String, double>> nutrientsFor(String food) async {
    final name = food.trim().toLowerCase();
    if (name.isEmpty) return const {};

    final cache = _firestore.collection('nutritionCache').doc(name);
    try {
      final cached = await cache.get();
      if (cached.exists) {
        return _mapFrom(cached.data()?['nutrition']);
      }
    } on Exception {
      // Cache read failures just mean we go to the network.
    }

    final nutrients = await _lookupUsda(food);
    try {
      await cache.set({
        'nutrition': nutrients,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on Exception {
      // A failed cache write still leaves us with a usable result.
    }
    return nutrients;
  }

  Future<Map<String, double>> _lookupUsda(String food) async {
    final uri = Uri.https(
      'api.nal.usda.gov',
      '/fdc/v1/foods/search',
      {
        'api_key': apiKey,
        'query': food,
        'dataType': 'Foundation,SR Legacy',
        'pageSize': '1',
      },
    );
    final response = await _client.get(uri).timeout(
      const Duration(seconds: 15),
    );
    if (response.statusCode != 200) {
      throw Exception('USDA request failed (${response.statusCode}).');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final foods = body['foods'];
    if (foods is! List || foods.isEmpty) return const {};
    return nutrientsFromUsda((foods.first as Map)['foodNutrients'] as List?);
  }

  /// Extracts our tracked nutrients from a USDA `foodNutrients` array.
  static Map<String, double> nutrientsFromUsda(List<dynamic>? entries) {
    final result = <String, double>{};
    if (entries == null) return result;

    double? folateFallback;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final name = '${entry['nutrientName']}';
      final unit = '${entry['unitName']}'.toUpperCase();
      final value = (entry['value'] as num?)?.toDouble() ?? 0;
      if (value <= 0) continue;

      final shorthand = _shorthandFor(name, unit);
      if (shorthand == null) {
        // Folate has several variants; prefer DFE, fall back to food folate.
        if (name.startsWith('Folate, DFE')) {
          folateFallback = _toUnit(value, 'UG', unit);
        } else if (name.startsWith('Folate, food') && folateFallback == null) {
          folateFallback = _toUnit(value, 'UG', unit);
        }
        continue;
      }
      result[shorthand] = _toUnit(value, nutrientUnits[shorthand]!, unit);
    }
    if (folateFallback != null && !result.containsKey('FOL')) {
      result['FOL'] = folateFallback;
    }
    return result;
  }

  /// Maps a USDA nutrient name onto our shorthand, or null when we don't
  /// track it. "Added" variants are ignored so fortification doesn't double
  /// count, and vitamin D only counts the UG entry (not the duplicate IU).
  static String? _shorthandFor(String name, String unit) {
    if (name.contains('added')) return null;
    if (name.startsWith('Calcium')) return 'CA';
    if (name.startsWith('Sodium')) return 'NA';
    if (name.startsWith('Iron')) return 'FE';
    if (name.startsWith('Potassium')) return 'K';
    if (name.startsWith('Magnesium')) return 'MG';
    if (name.startsWith('Zinc')) return 'ZN';
    if (name.startsWith('Vitamin A, RAE')) return 'VITA';
    if (name.startsWith('Vitamin A')) return null; // IU duplicate of RAE.
    if (name.startsWith('Vitamin B-6')) return 'VITB6';
    if (name.startsWith('Vitamin B-12')) return 'VITB12';
    if (name.startsWith('Vitamin C')) return 'VITC';
    if (name.startsWith('Vitamin D (D2 + D3)')) {
      return unit == 'UG' ? 'VITD' : null;
    }
    if (name.startsWith('Vitamin D')) return null; // D3/IU duplicates.
    if (name.startsWith('Vitamin E (alpha-tocopherol)')) return 'VITE';
    if (name.startsWith('Vitamin K (phylloquinone)')) return 'VITK';
    if (name.startsWith('Vitamin K')) return null; // Other K variants.
    return null;
  }

  /// Converts [value] from its USDA unit into the [target] unit. IU values
  /// use the standard retinol/alpha-tocopherol factors.
  static double _toUnit(double value, String target, String unit) {
    switch (unit) {
      case 'IU':
        switch (target) {
          case 'UG':
            return value * 0.3; // Vitamin A retinol.
          case 'MG':
            return value * 0.67; // Vitamin E alpha-tocopherol.
        }
        return value;
      case 'MG':
        return target == 'UG' ? value * 1000 : value;
      case 'UG':
        return target == 'MG' ? value / 1000 : value;
    }
    return value;
  }

  Map<String, double> _mapFrom(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num && nutrientUnits.containsKey('${entry.key}'))
          '${entry.key}': (entry.value as num).toDouble(),
    };
  }
}
