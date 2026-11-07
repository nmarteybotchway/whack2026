/// Fills the Firestore `food` collection from a list of food names.
///
/// ```sh
/// dart run tool/fill_food.dart food.txt            # write to Firestore
/// dart run tool/fill_food.dart food.txt --dry-run  # print only
/// dart run tool/fill_food.dart food.txt --full     # regenerate every field
/// ```
///
/// `food.txt` holds one food per line; blank lines and `#` comments are
/// skipped. New foods get health conditions, personal prefs, general info and
/// local news from OpenRouter with web search, then a second call (without
/// search) fills the alternatives for each condition/preference pair, and a
/// third fills the vitamins and minerals per 100 g. Foods already stored
/// only have their local news refreshed (and their nutrients filled if they
/// have none yet), unless `--full` regenerates them completely (e.g. after
/// the document format changes).
///
/// Step 1 of tool/fill_food_db.dart, which runs the whole pipeline.
library;

import 'dart:io';

import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/health_condition.dart';
import 'package:hackathon/food/nutrient.dart';
import 'package:hackathon/food/preference.dart';
import 'package:hackathon/openrouter.dart';

import 'src/food_store.dart';

/// Web-search replies typically take 2-6 minutes.
const _aiTimeout = Duration(minutes: 10);

/// Where `local_news` is about; the app's users are in Coventry.
const _area = 'Coventry and the UK';

/// How far back `local_news` looks; older events are left out.
const _newsDays = 30;

const _newsRules =
    '''
"local_news" is ONLY an active food-safety event affecting this food for
people in $_area, such as a pathogen outbreak (Salmonella, E. coli, Listeria,
norovirus, etc.), a contamination or allergen recall, or an animal disease
such as BSE (mad cow disease) or avian flu. It must have been reported within
the last $_newsDays days, and it must affect Coventry, the West Midlands or
the UK as a whole: UK outbreaks, Food Standards Agency (FSA) alerts and
recalls, or products sold in UK shops. Prefer events in Coventry or the West
Midlands, then UK-wide ones. Ignore events elsewhere unless the affected
product is sold in the UK. Write one or two plain sentences naming the
problem, where in the UK it applies, and the date it was reported, with no
links or citations. General nutrition news, studies and diet advice do not
count. If nothing recent qualifies, or you cannot confirm it from search
results, return an empty string. Never invent an event.''';

final _newsSchema = {
  'type': 'object',
  'properties': {
    'local_news': {'type': 'string'},
  },
  'required': ['local_news'],
  'additionalProperties': false,
};

final _fullSchema = {
  'type': 'object',
  'properties': {
    'health_conditions': {
      'type': 'array',
      'items': {
        'type': 'string',
        'enum': [for (final c in HealthCondition.conditions) c.id],
      },
    },
    'personal_prefs': {
      'type': 'array',
      'items': {
        'type': 'string',
        'enum': [for (final p in Preference.preferences) p.id],
      },
    },
    'general_info': {'type': 'string'},
    'local_news': {'type': 'string'},
  },
  'required': [
    'health_conditions',
    'personal_prefs',
    'general_info',
    'local_news',
  ],
  'additionalProperties': false,
};

final _nutrientsSchema = {
  'type': 'object',
  'properties': {
    for (final n in Nutrient.values) n.id: {'type': 'number'},
  },
  'required': [for (final n in Nutrient.values) n.id],
  'additionalProperties': false,
};

// Strict schemas cannot have dynamic keys, so the nested alternatives map
// comes back as a list of {health, pref, items} cells.
final _alternativesSchema = {
  'type': 'object',
  'properties': {
    'alternatives': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'health': {
            'type': 'string',
            'enum': [for (final c in HealthCondition.values) c.id],
          },
          'pref': {
            'type': 'string',
            'enum': [for (final p in Preference.values) p.id],
          },
          'items': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['health', 'pref', 'items'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['alternatives'],
  'additionalProperties': false,
};

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final dryRun = args.remove('--dry-run');
  final full = args.remove('--full');
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/fill_food.dart <food.txt> [--dry-run] [--full]',
    );
    exit(64);
  }

  final names = <String, String>{};
  for (final line in await File(args.single).readAsLines()) {
    final name = line.trim();
    if (name.isEmpty || name.startsWith('#')) continue;
    names.putIfAbsent(Food.idFor(name), () => name);
  }

  final store = await FoodStore.signIn();
  final ai = OpenRouterService();
  final failed = <String>[];
  try {
    // Web-search calls are slow, so run a few foods at once.
    final queue = names.values.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final name = queue.removeAt(0);
        stdout.writeln('… $name');
        try {
          await _fill(name, store, ai, dryRun: dryRun, full: full);
        } catch (e) {
          failed.add(name);
          stderr.writeln('✗ $name: $e');
        }
      }
    }

    await Future.wait([for (var i = 0; i < 5; i++) worker()]);
  } finally {
    ai.close();
  }

  stdout.writeln(
    '\n${names.length - failed.length}/${names.length} foods done'
    '${dryRun ? ' (dry run, nothing written)' : ''}.',
  );
  if (failed.isNotEmpty) {
    stderr.writeln('Failed: ${failed.join(', ')}');
    exitCode = 1;
  }
}

Future<void> _fill(
  String name,
  FoodStore store,
  OpenRouterService ai, {
  required bool dryRun,
  required bool full,
}) async {
  final id = Food.idFor(name);
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final stored = await store.get(id);
  final existing = stored != null;

  if (existing && !full) {
    if (stored.nutrients.isEmpty) {
      final nutrients = await _nutrients(ai, name);
      stdout.writeln('↻ $name: nutrients ${_describe(nutrients)}');
      if (!dryRun) {
        await store.write(id, {
          'nutrients': {
            for (final MapEntry(:key, :value) in nutrients.entries)
              key.id: value,
          },
        }, create: false);
      }
    }
    final reply = await _ask(
      ai,
      'Today is $today. Search for current food-safety news about "$name" '
      'affecting $_area.\n'
      '$_newsRules\nReply as JSON.',
      _newsSchema,
    );
    final news = (reply['local_news'] as String).trim();
    stdout.writeln('↻ $name: news ${news.isEmpty ? '(none)' : '"$news"'}');
    if (!dryRun) await store.write(id, {'local_news': news}, create: false);
    return;
  }

  final conditions = HealthCondition.conditions
      .map((c) => '- ${c.id}: ${c.label}')
      .join('\n');
  final preferences = Preference.preferences
      .map((p) => '- ${p.id}: ${p.label}')
      .join('\n');
  final reply = await _ask(
    ai,
    'You are filling a food-safety database. Today is $today. Food: "$name".\n\n'
    '"health_conditions": the conditions below for which people should avoid '
    'or strictly limit this food. Include only well-established clashes '
    '(allergens it normally contains, gluten, lactose, high salt, sugar, '
    'saturated fat, purines, potassium, pregnancy food-safety advice, etc.). '
    'Use an empty list if none apply.\n$conditions\n\n'
    '"personal_prefs": the religious or dietary preferences below that this '
    'food, as normally prepared, does not meet (e.g. pork for islam, judaism, '
    'halal and kosher; beef for hinduism; any meat for vegetarian; any animal '
    'product for vegan; gluten for gluten_free). For religions use their '
    'mainstream dietary rules. Use an empty list if none apply.\n'
    '$preferences\n\n'
    '"general_info": a reason why even a healthy person with no health '
    'conditions or dietary preferences should avoid or limit this food, in one '
    'or two plain sentences (e.g. bacon: processed meat classed as a cause of '
    'cancer, high in saturated fat and salt). Use an empty string if the food '
    'is fine for a healthy person as part of a normal diet (e.g. apples, '
    'cabbage, eggs). Do not describe the food or its benefits.\n\n'
    '$_newsRules\n\nReply as JSON.',
    _fullSchema,
  );

  final healthConditions = {
    for (final c in reply['health_conditions'] as List)
      if (HealthCondition.fromId(c as String) case final c?
          when c != HealthCondition.none)
        c,
  };
  final personalPrefs = {
    for (final p in reply['personal_prefs'] as List)
      if (Preference.fromId(p as String) case final p?
          when p != Preference.none)
        p,
  };
  final generalInfo = (reply['general_info'] as String).trim();
  final food = Food(
    name: name,
    alternatives: await _alternatives(
      ai,
      name,
      healthConditions,
      personalPrefs,
      generalInfo,
    ),
    healthConditions: healthConditions,
    personalPrefs: personalPrefs,
    generalInfo: generalInfo,
    localNews: (reply['local_news'] as String).trim(),
    nutrients: await _nutrients(ai, name),
  );
  stdout.writeln(
    '${existing ? '↻' : '+'} $name: ${food.healthConditions.map((c) => c.id).join(', ')}'
    ' | personal_prefs: ${food.personalPrefs.map((p) => p.id).join(', ')}'
    ' | alternatives: ${food.toMap()['alternatives']}'
    ' | general_info: ${food.generalInfo.isEmpty ? '(none)' : '"${food.generalInfo}"'}'
    ' | local_news: ${food.hasNews ? '"${food.localNews}"' : '(none)'}'
    ' | nutrients: ${_describe(food.nutrients)}',
  );
  if (dryRun) return;
  existing
      ? await store.replace(food, const [])
      : await store.write(id, food.toMap(), create: true);
}

/// Asks for substitutes for every pair of (one of [conditions] or none) and
/// (one of [prefs] or none). The none/none pair, healthier substitutes for
/// anyone, is only asked for when [generalInfo] gives a reason to avoid the
/// food.
Future<Map<HealthCondition, Map<Preference, List<String>>>> _alternatives(
  OpenRouterService ai,
  String name,
  Set<HealthCondition> conditions,
  Set<Preference> prefs,
  String generalInfo,
) async {
  final pairs = [
    for (final c in [HealthCondition.none, ...conditions])
      for (final p in [Preference.none, ...prefs])
        if (c != HealthCondition.none ||
            p != Preference.none ||
            generalInfo.isNotEmpty)
          (c, p),
  ];
  if (pairs.isEmpty) return const {};

  String describe(HealthCondition c, Preference p) => [
    if (c != HealthCondition.none) 'has ${c.label.toLowerCase()}',
    if (p != Preference.none) 'follows ${p.label}',
    if (c == HealthCondition.none && p == Preference.none)
      'is healthy (avoiding: $generalInfo)',
  ].join(' and ');

  final reply = await askJson(
    ai,
    'Suggest substitutes for "$name". For EACH line below, give 1 to 3 '
    'common, widely available foods that can replace it and are safe and '
    'suitable for that person, considering BOTH their health condition and '
    'their preference. Short names only. Return one {health, pref, items} '
    'entry per line, using the keys exactly as given.\n\n'
    '${pairs.map((e) => '- health "${e.$1.id}", pref "${e.$2.id}": '
        'someone who ${describe(e.$1, e.$2)}').join('\n')}'
    '\n\nReply as JSON.',
    _alternativesSchema,
    timeout: const Duration(minutes: 3),
  );

  // Asked for a list of cells, but models sometimes return the nested map
  // itself ({health: {pref: items}}); accept either.
  final cells = switch (reply['alternatives']) {
    // Skip malformed cells rather than failing the whole food.
    List l => [
      for (final e in l)
        if (e case {'health': String h, 'pref': String p, 'items': List items})
          (h, p, items),
    ],
    Map m => [
      for (final row in m.entries)
        if (row.value is Map)
          for (final cell in (row.value as Map).entries)
            if (cell.value is List)
              (row.key as String, cell.key as String, cell.value as List),
    ],
    final other => throw FormatException('Bad alternatives: $other'),
  };
  final wanted = {for (final (c, p) in pairs) (c.id, p.id)};
  final id = Food.idFor(name);
  final result = <HealthCondition, Map<Preference, List<String>>>{};
  for (final (h, p, items) in cells) {
    // Only keep pairs that were asked for, which also enforces the none/none
    // rule.
    if (!wanted.contains((h, p))) continue;
    final alts = [
      for (final a in items)
        if ((a as String).trim() case final alt
            when alt.isNotEmpty && Food.idFor(alt) != id)
          alt,
    ];
    if (alts.isEmpty) continue;
    // Known IDs, since only pairs that were asked for get this far.
    (result[HealthCondition.fromId(h)!] ??= {})[Preference.fromId(p)!] = alts;
  }
  final missing = wanted.length - result.values.expand((r) => r.keys).length;
  if (missing > 0) {
    stderr.writeln('  $name: $missing pair(s) got no alternatives');
  }
  return result;
}

/// Typical vitamins and minerals per 100 g of [name], in each
/// [Nutrient.unit]; negligible ones are left out.
Future<Map<Nutrient, double>> _nutrients(
  OpenRouterService ai,
  String name,
) async {
  final reply = await askJson(
    ai,
    'Give the typical amount of each nutrient below in 100 g of "$name" as '
    'normally sold in UK shops (raw unless it is usually sold cooked or '
    'prepared), based on standard food composition tables such as USDA '
    'FoodData Central or the UK CoFID. Use exactly the unit given for each '
    '(MG milligrams, UG micrograms). Use 0 when the food has none or a '
    'negligible amount; never guess wildly.\n'
    '${Nutrient.values.map((n) => '- ${n.id}: ${n.label} (${n.unit})').join('\n')}'
    '\n\nReply as JSON.',
    _nutrientsSchema,
  );
  return Nutrient.parseAmounts(reply);
}

String _describe(Map<Nutrient, double> nutrients) => nutrients.isEmpty
    ? '(none)'
    : nutrients.entries.map((e) => '${e.key.id} ${e.value}').join(', ');

Future<Map<String, dynamic>> _ask(
  OpenRouterService ai,
  String prompt,
  Map<String, Object?> schema,
) => askJson(ai, prompt, schema, webSearch: true, timeout: _aiTimeout);
