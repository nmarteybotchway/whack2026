/// Finds an image for every food and alternative in the Firestore `food`
/// collection and stores it in `food_images/{id}`, where `id` is
/// `Food.idFor(name)`.
///
/// ```sh
/// dart run tool/fill_food_images.dart            # write to Firestore
/// dart run tool/fill_food_images.dart --dry-run  # print only
/// dart run tool/fill_food_images.dart --retry    # retry names with no image
/// ```
///
/// Images come from English Wikipedia: OpenRouter picks the article that best
/// shows each name (`Grilled halal chicken` → `Chicken as food`), whose lead
/// image is used, falling back to a Wikipedia search for that title. Logos
/// and other SVGs are rejected. Only the image URL and its article (for
/// attribution) are stored. Names already looked up are skipped, including
/// ones with no image, which are stored with an empty `url`, unless
/// `--retry` is given. Names the model gives no title for are left unstored
/// so the next run tries again, since searching Wikipedia for a raw name
/// like "eggs on wholegrain toast" finds brand pages and logos.
///
/// Step 3 of tool/fill_food_db.dart, which runs the whole pipeline.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hackathon/food/food.dart';
import 'package:hackathon/openrouter.dart';
import 'package:http/http.dart' as http;

import 'src/food_store.dart';

/// Names per OpenRouter call.
const _batchSize = 20;

/// Wikipedia lookups at once; Wikimedia asks for modest request rates.
const _concurrency = 4;

/// Wikimedia blocks requests without a descriptive User-Agent.
const _userAgent =
    'whack2026-food-tool/1.0 (https://github.com/nmarteybotchway/whack2026)';

const _thumbnailWidth = 400;

final _schema = {
  'type': 'object',
  'properties': {
    'titles': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'title': {'type': 'string'},
        },
        'required': ['name', 'title'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['titles'],
  'additionalProperties': false,
};

Future<void> main(List<String> arguments) async {
  final dryRun = arguments.contains('--dry-run');
  final retry = arguments.contains('--retry');
  final store = await FoodStore.signIn();
  final foods = await store.all();
  final stored = await store.imageUrls();

  // Every food and alternative name not looked up yet, by document ID.
  final names = <String, String>{};
  for (final food in foods.values) {
    for (final name in [
      food.name,
      for (final row in food.alternatives.values)
        for (final alts in row.values) ...alts,
    ]) {
      final id = Food.idFor(name);
      if (stored[id] case final url? when url.isNotEmpty || !retry) continue;
      names.putIfAbsent(id, () => name);
    }
  }
  if (names.isEmpty) {
    stdout.writeln('Every food and alternative has been looked up already.');
    return;
  }
  stdout.writeln('Finding images for ${names.length} name(s)…');

  final ai = OpenRouterService();
  final client = http.Client();
  var found = 0;
  final failed = <String>[];
  try {
    final entries = names.entries.toList();
    for (var i = 0; i < entries.length; i += _batchSize) {
      final batch = entries.sublist(i, min(i + _batchSize, entries.length));
      final Map<String, String> titles;
      try {
        titles = await _titles(ai, [for (final e in batch) e.value]);
      } catch (e) {
        failed.addAll([for (final e in batch) e.value]);
        stderr.writeln('✗ Wikipedia titles for ${batch.length} name(s): $e');
        continue;
      }

      final queue = [
        for (final e in batch)
          if (titles.containsKey(e.key)) e else ?_skip(e.value, failed),
      ];
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final MapEntry(key: id, value: name) = queue.removeAt(0);
          try {
            final image = await _image(client, titles[id]!);
            stdout.writeln(
              image == null ? '∅ $name: no image' : '🖼 $name: ${image.url}',
            );
            if (image != null) found++;
            if (!dryRun) {
              await store.writeImage(
                id,
                name: name,
                url: image?.url ?? '',
                page: image?.page ?? '',
              );
            }
          } catch (e) {
            // Not stored, so the next run tries again.
            failed.add(name);
            stderr.writeln('✗ $name: $e');
          }
        }
      }

      await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
    }
  } finally {
    ai.close();
    client.close();
  }

  stdout.writeln(
    '\nImages for $found/${names.length} name(s)'
    '${dryRun ? ' (dry run, nothing written)' : ''}.',
  );
  if (failed.isNotEmpty) stderr.writeln('Failed: ${failed.join(', ')}');
}

/// Records [name] as failed because the model gave it no title.
MapEntry<String, String>? _skip(String name, List<String> failed) {
  failed.add(name);
  stderr.writeln('✗ $name: no Wikipedia title');
  return null;
}

/// Asks OpenRouter for the Wikipedia article title that best shows each of
/// [names], keyed by `Food.idFor(name)`; tries twice before giving up.
Future<Map<String, String>> _titles(
  OpenRouterService ai,
  List<String> names,
) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final reply = await askJson(
        ai,
        'For each food below, give the title of the English Wikipedia '
        'article whose main photo best shows that food, so it can be used as '
        'a picture of it. Prefer the article about the food itself; for a '
        'dish or variant without its own article use its main ingredient '
        '(e.g. "Grilled halal chicken" → "Chicken as food", "Smoked tofu" → '
        '"Tofu", "Eggs on wholegrain toast" → "Eggs as food", "Vegan dark '
        'chocolate" → "Dark chocolate"). Never pick an article about a '
        'religion, diet, brand, company, person or place. Use the exact '
        'article title. Return one {name, title} entry per food, with the '
        'name exactly as given.\n\n'
        '${names.map((n) => '- $n').join('\n')}\n\nReply as JSON.',
        _schema,
        timeout: const Duration(minutes: 3),
      );
      return {
        for (final e in reply['titles'] as List)
          if (e case {'name': String name, 'title': String title}
              when title.trim().isNotEmpty)
            Food.idFor(name): title.trim(),
      };
    } catch (e) {
      if (attempt == 2) rethrow;
      stderr.writeln('  Wikipedia titles failed, retrying: $e');
    }
  }
}

/// The lead image of the Wikipedia article [title], else of the first of
/// the top search results for it that has a usable image, with the
/// article's URL; null if none has one.
Future<({String url, String page})?> _image(
  http.Client client,
  String title,
) async {
  final summary = await _get(
    client,
    Uri.https(
      'en.wikipedia.org',
      '/api/rest_v1/page/summary/${title.replaceAll(' ', '_')}',
    ),
  );
  if (summary
      case {
        'type': != 'disambiguation',
        'thumbnail': {'source': String url},
        'content_urls': {'desktop': {'page': String page}},
      }
      when _usable(url)) {
    return (url: url, page: page);
  }

  final search = await _get(
    client,
    Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'generator': 'search',
      'gsrsearch': title,
      'gsrlimit': '3',
      'prop': 'pageimages|info',
      'piprop': 'thumbnail',
      'pithumbsize': '$_thumbnailWidth',
      'inprop': 'url',
      'redirects': '1',
    }),
  );
  final pages = switch (search) {
    {'query': {'pages': List pages}} =>
      [...pages]
        // Generator results come back unordered; `index` is the search rank.
        ..sort((a, b) => (a['index'] as int) - (b['index'] as int)),
    _ => const [],
  };
  for (final page in pages) {
    if (page case {'thumbnail': {'source': String url}, 'fullurl': String page}
        when _usable(url)) {
      return (url: url, page: page);
    }
  }
  return null;
}

/// False for logos and other SVG drawings, which are not photos of food.
bool _usable(String url) {
  final path = Uri.parse(url).path.toLowerCase();
  return !path.contains('.svg') && !path.contains('logo');
}

/// Decoded JSON from [uri], or null if it is not found.
Future<Object?> _get(http.Client client, Uri uri) async {
  final response = await client
      .get(uri, headers: {'User-Agent': _userAgent})
      .timeout(const Duration(seconds: 30));
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode} from ${uri.host}');
  }
  return jsonDecode(response.body);
}
