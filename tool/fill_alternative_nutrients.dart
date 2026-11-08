/// Fills nutrients for stored alternatives that are not in the `food`
/// collection, so the scan sheet can say which low nutrients a substitute
/// provides.
///
/// ```sh
/// dart run tool/fill_alternative_nutrients.dart            # write to Firestore
/// dart run tool/fill_alternative_nutrients.dart --dry-run  # print only
/// ```
///
/// Every alternative name referenced by any stored food's `alternatives` map
/// that has no document yet gets one with just a name and the typical
/// vitamins and minerals per 100 g. The amounts come from the USDA FoodData
/// Central API (free, no LLM): the first search hit's SR Legacy / Foundation
/// / SR Commercial record, per 100 g, mapped to the tracked nutrients.
/// Nothing else about the new foods is filled: news and alternatives for
/// the alternatives come from a later full run of tool/fill_food.dart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/nutrient.dart';
import 'package:hackathon/secrets.dart';

import 'src/food_store.dart';

const _apiKey = usdaApiKey;
const _searchUrl = 'https://api.nal.usda.gov/fdc/v1/foods/search';

const _httpTimeout = Duration(seconds: 30);

/// Maps USDA nutrient numbers to the tracked ones. See
/// https://fdc.nal.usda.gov/docs/fdc_api.html for the numbering.
const _usdaIds = {
  Nutrient.calcium: 1092, // Calcium, Ca (mg)
  Nutrient.sodium: 1093, // Sodium, Na (mg)
  Nutrient.iron: 303, // Iron, Fe (mg)
  Nutrient.potassium: 1094, // Potassium, K (mg)
  Nutrient.magnesium: 1090, // Magnesium, Mg (mg)
  Nutrient.zinc: 305, // Zinc, Zn (mg)
  Nutrient.vitaminA: 1106, // Vitamin A, RAE (mcg)
  Nutrient.vitaminB6: 1175, // Vitamin B-6 (mg)
  Nutrient.vitaminB12: 1178, // Vitamin B-12 (mcg)
  Nutrient.vitaminC: 1162, // Vitamin C, total ascorbic acid (mg)
  Nutrient.vitaminD: 1114, // Vitamin D (D2 + D3), international units -> use 1110 mcg D2+D3
  Nutrient.vitaminE: 1109, // Vitamin E (alpha-tocopherol) (mg)
  Nutrient.vitaminK: 1185, // Vitamin K (phylloquinone) (mcg)
  Nutrient.folate: 1177, // Folate, total (mcg)  (1176 is food folate, 1187 DFE)
};

Future<void> main(List<String> arguments) async {
  final dryRun = arguments.contains('--dry-run');
  final store = await FoodStore.signIn();
  final foods = await store.all();

  // Every alternative referenced anywhere that has no stored document.
  final missing = <String, String>{};
  for (final food in foods.values) {
    for (final row in food.alternatives.values) {
      for (final alts in row.values) {
        for (final alt in alts) {
          final id = Food.idFor(alt);
          if (!foods.containsKey(id) && !missing.containsKey(id)) {
            missing[id] = alt;
          }
        }
      }
    }
  }
  stdout.writeln(
    '${foods.length} foods, ${missing.length} referenced alternatives '
    'missing${dryRun ? ' (dry run, nothing written)' : ''}.',
  );
  if (missing.isEmpty) return;

  final failed = <String>[];
  final queue = missing.values.toList();
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final name = queue.removeAt(0);
      stdout.writeln('… $name');
      try {
        final nutrients = await _nutrients(name);
        if (!dryRun) {
          await store.write(
            Food.idFor(name),
            {
              'food': name,
              'nutrients': {
                for (final MapEntry(:key, :value) in nutrients.entries)
                  key.id: value,
              },
            },
            create: true,
          );
        }
        stdout.writeln('+ $name: ${_describe(nutrients)}');
      } catch (e) {
        failed.add(name);
        stderr.writeln('✗ $name: $e');
      }
    }
  }

  await Future.wait([for (var i = 0; i < 4; i++) worker()]);

  stdout.writeln(
    '\n${missing.length - failed.length}/${missing.length} filled'
    '${dryRun ? ' (dry run, nothing written)' : ''}.',
  );
  if (failed.isNotEmpty) {
    stderr.writeln('Failed: ${failed.join(', ')}');
    exitCode = 1;
  }
}

/// USDA per-100 g amounts for [name], in each [Nutrient.unit].
///
/// Searches FoodData Central and takes the first result of a wanted data
/// type (the search ranks by match quality). Zero/absent nutrients are left
/// out, matching how the app treats unknown-or-negligible amounts.
Future<Map<Nutrient, double>> _nutrients(String name) async {
  final response = await http
      .post(
        Uri.parse('$_searchUrl?api_key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': name,
          'dataType': ['SR Legacy', 'Foundation Foods'],
          'pageSize': 5,
        }),
      )
      .timeout(_httpTimeout);
  if (response.statusCode != 200) {
    throw HttpException('USDA ${response.statusCode}: ${response.body}');
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final hits = body['foods'] as List? ?? const [];
  if (hits.isEmpty) {
    throw StateError('no USDA result for "$name"');
  }
  // The search ranks oddly (a juice drink for "kiwi"), so prefer a hit
  // whose description names the query's main word(s).
  final words = name
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((w) => w.length > 2)
      .toSet();
  final food = hits.map((h) => h as Map<String, dynamic>).firstWhere(
    (h) =>
        words
            .intersection(
              (h['description'] as String? ?? '').toLowerCase().split(' ').toSet(),
            )
            .isNotEmpty,
    orElse: () => hits.first as Map<String, dynamic>,
  );

  final amounts = <Nutrient, double>{};
  for (final fn in food['foodNutrients'] as List) {
    final detail = fn as Map<String, dynamic>;
    // USDA numbers are unique per nutrient; unitName casing varies.
    final id = _usdaIdOf[detail['nutrientNumber'] as String? ?? ''];
    if (id == null) continue;
    final v = (detail['value'] as num?)?.toDouble();
    if (v != null && v > 0) amounts[id] = v;
  }
  return amounts;
}

/// USDA nutrient numbers (fdc_api.html numbering) to the tracked nutrients,
/// verified against a live kiwifruit response: 301 Ca, 303 Fe, 304 Mg,
/// 306 K, 307 Na, 309 Zn, 320 A-RAE, 401 C, 415 B6, 417 folate, 430 K1.
/// B12 (418) and D (1114 mcg / 1110?) are sparse in SR Legacy and left to
/// chance when present.
const _usdaIdOf = {
  '301': Nutrient.calcium,
  '303': Nutrient.iron,
  '304': Nutrient.magnesium,
  '306': Nutrient.potassium,
  '307': Nutrient.sodium,
  '309': Nutrient.zinc,
  '320': Nutrient.vitaminA, // Vitamin A, RAE (mcg)
  '401': Nutrient.vitaminC, // Vitamin C, total ascorbic acid (mg)
  '415': Nutrient.vitaminB6, // Vitamin B-6 (mg)
  '417': Nutrient.folate, // Folate, total (mcg)
  '430': Nutrient.vitaminK, // Vitamin K (phylloquinone) (mcg)
  '418': Nutrient.vitaminB12, // Vitamin B-12 (mcg), when present
  '1114': Nutrient.vitaminD, // Vitamin D2+D3 (mcg), when present
  '323': Nutrient.vitaminE, // Vitamin E (alpha-tocopherol) (mg)
};

String _describe(Map<Nutrient, double> nutrients) => nutrients.isEmpty
    ? '(none)'
    : nutrients.entries.map((e) => '${e.key.id} ${e.value}').join(', ');
