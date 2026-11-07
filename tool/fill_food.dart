/// Fills the Firestore `food` collection from a list of food names.
///
/// ```sh
/// dart run tool/fill_food.dart food.txt            # write to Firestore
/// dart run tool/fill_food.dart food.txt --dry-run  # print only
/// ```
///
/// `food.txt` holds one food per line; blank lines and `#` comments are
/// skipped. New foods get health conditions, personal prefs, alternatives,
/// general info and local news from OpenRouter; foods already stored only have
/// their local news refreshed.
///
/// Step 1 of tool/fill_food_db.dart, which runs the whole pipeline.
library;

import 'dart:io';

import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/health_condition.dart';
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
        'enum': [for (final c in HealthCondition.values) c.id],
      },
    },
    'personal_prefs': {
      'type': 'array',
      'items': {
        'type': 'string',
        'enum': [for (final p in Preference.values) p.id],
      },
    },
    'alternatives': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'general_info': {'type': 'string'},
    'local_news': {'type': 'string'},
  },
  'required': [
    'health_conditions',
    'personal_prefs',
    'alternatives',
    'general_info',
    'local_news',
  ],
  'additionalProperties': false,
};

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final dryRun = args.remove('--dry-run');
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/fill_food.dart <food.txt> [--dry-run]',
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
          await _fill(name, store, ai, dryRun);
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
  OpenRouterService ai,
  bool dryRun,
) async {
  final id = Food.idFor(name);
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final existing = await store.exists(id);

  if (existing) {
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

  final conditions = HealthCondition.values
      .map((c) => '- ${c.id}: ${c.label}')
      .join('\n');
  final preferences = Preference.values
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
    '"alternatives": 3 to 5 common, widely available foods that can replace '
    'it and avoid those health and preference clashes. Short names only.\n\n'
    '"general_info": two or three plain sentences on what the food is and its '
    'main nutritional points (e.g. high in protein, salt or sugar).\n\n'
    '$_newsRules\n\nReply as JSON.',
    _fullSchema,
  );

  final food = Food(
    name: name,
    healthConditions: {
      for (final c in reply['health_conditions'] as List)
        ?HealthCondition.fromId(c as String),
    },
    personalPrefs: {
      for (final p in reply['personal_prefs'] as List)
        ?Preference.fromId(p as String),
    },
    alternatives: [
      for (final a in reply['alternatives'] as List)
        if ((a as String).trim() case final alt
            when alt.isNotEmpty && Food.idFor(alt) != id)
          alt,
    ],
    generalInfo: (reply['general_info'] as String).trim(),
    localNews: (reply['local_news'] as String).trim(),
  );
  stdout.writeln(
    '+ $name: ${food.healthConditions.map((c) => c.id).join(', ')}'
    ' | personal_prefs: ${food.personalPrefs.map((p) => p.id).join(', ')}'
    ' | alternatives: ${food.alternatives.join(', ')}'
    ' | local_news: ${food.hasNews ? '"${food.localNews}"' : '(none)'}',
  );
  if (!dryRun) await store.write(id, food.toMap(), create: true);
}

Future<Map<String, dynamic>> _ask(
  OpenRouterService ai,
  String prompt,
  Map<String, Object?> schema,
) => askJson(ai, prompt, schema, webSearch: true, timeout: _aiTimeout);
