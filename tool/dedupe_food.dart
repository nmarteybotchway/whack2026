/// Merges duplicate foods in the Firestore `food` collection.
///
/// ```sh
/// dart run tool/dedupe_food.dart            # merge in Firestore
/// dart run tool/dedupe_food.dart --dry-run  # print only
/// ```
///
/// OpenRouter groups names that mean the same food (`Apple` / `Apples`,
/// `Toast` / `Bread (Toast)`). Each group becomes one document under the
/// chosen name, combining health conditions, personal prefs, alternatives,
/// general info and local news; the other documents are deleted in the same
/// atomic commit.
///
/// Step 2 of tool/fill_food_db.dart, which runs the whole pipeline.
library;

import 'dart:io';

import 'package:hackathon/food/food.dart';
import 'package:hackathon/openrouter.dart';

import 'src/food_store.dart';

final _schema = {
  'type': 'object',
  'properties': {
    'groups': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'ids': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['name', 'ids'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['groups'],
  'additionalProperties': false,
};

Future<void> main(List<String> arguments) async {
  final dryRun = arguments.contains('--dry-run');
  final store = await FoodStore.signIn();
  final foods = await store.all();
  if (foods.length < 2) {
    stdout.writeln('${foods.length} foods; nothing to dedupe.');
    return;
  }

  final ai = OpenRouterService();
  final List<({String name, List<String> ids})> groups;
  try {
    groups = await findDuplicates(ai, {
      for (final e in foods.entries) e.key: e.value.name,
    });
  } finally {
    ai.close();
  }

  for (final (:name, :ids) in groups) {
    final food = _merge(name, [for (final id in ids) foods[id]!]);
    stdout.writeln(
      '⇢ ${ids.map((id) => foods[id]!.name).join(' + ')} → ${food.name}',
    );
    if (!dryRun) await store.replace(food, ids);
  }
  stdout.writeln(
    groups.isEmpty
        ? 'No duplicates found.'
        : '${groups.length} group(s) merged${dryRun ? ' (dry run, nothing written)' : ''}.',
  );
}

/// Asks OpenRouter which of [names] (document ID → name) are the same food.
///
/// Each group has at least two known IDs, and no ID is in two groups.
Future<List<({String name, List<String> ids})>> findDuplicates(
  OpenRouterService ai,
  Map<String, String> names,
) async {
  final reply = await askJson(
    ai,
    'Below are the IDs and names of foods in a food database. Find '
    'duplicates: entries that mean the same food and differ only in '
    'plural/singular, spelling, capitalisation, word order or a '
    'parenthetical detail (e.g. "Apple" and "Apples", "Toast" and "Bread '
    '(Toast)"). Different foods that are merely related are NOT duplicates '
    '(e.g. "Bread" and "Toast" if both are listed separately as bread and '
    'toast, "Milk" and "Milk chocolate", "Bacon" and "Pork").\n\n'
    'Return one group per set of duplicates, with every ID in that group '
    'and the clearest, most common display name for the merged food. '
    'Leave out foods that have no duplicate. Return an empty list if there '
    'are none.\n\n'
    '${names.entries.map((e) => '- ${e.key}: ${e.value}').join('\n')}'
    '\n\nReply as JSON.',
    _schema,
  );

  final seen = <String>{};
  return [
    for (final group in reply['groups'] as List)
      // Ignore IDs the model invented or already used in another group.
      if ((
            name: (group['name'] as String).trim(),
            ids: [
              for (final id in group['ids'] as List)
                if (names.containsKey(id) && seen.add(id as String)) id,
            ],
          )
          case final g when g.ids.length >= 2 && g.name.isNotEmpty)
        g,
  ];
}

/// Combines [parts] into one food called [name]: sets are unioned,
/// alternatives keep their first-seen order, the first general info is kept,
/// and distinct news is joined.
Food _merge(String name, List<Food> parts) {
  final ids = {Food.idFor(name), for (final f in parts) f.id};
  final alternatives = <String, String>{};
  for (final f in parts) {
    for (final alt in f.alternatives) {
      final id = Food.idFor(alt);
      if (!ids.contains(id)) alternatives.putIfAbsent(id, () => alt);
    }
  }
  return Food(
    name: name,
    alternatives: alternatives.values.toList(),
    healthConditions: {for (final f in parts) ...f.healthConditions},
    personalPrefs: {for (final f in parts) ...f.personalPrefs},
    generalInfo: parts
        .map((f) => f.generalInfo)
        .firstWhere((i) => i.isNotEmpty, orElse: () => ''),
    localNews: {
      for (final f in parts)
        if (f.hasNews) f.localNews,
    }.join('\n\n'),
  );
}
