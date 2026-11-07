// Dumps every food & drink product Tesco lists for the store nearest a
// location to a JSON file.
//
//   dart run tool/tesco_food_dump.dart "CV4 7AL" [out.json] [--details]
//       [--large]
//
// The location can be a postcode, town, or "lat,lng". --large only considers
// Superstores/Extras. --details also fetches ingredients/allergens/nutrition
// per product (one request each, slow).
import 'dart:convert';
import 'dart:io';

import 'package:hackathon/tesco/tesco_api.dart';

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final withDetails = args.remove('--details');
  final largeOnly = args.remove('--large');
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/tesco_food_dump.dart <location> [out.json] '
      '[--details] [--large]',
    );
    exit(64);
  }
  final location = args[0];
  final outPath = args.length > 1 ? args[1] : 'tesco_food.json';

  final tesco = TescoApi();
  try {
    final directory = TescoStoreDirectory.parse(
      await File(TescoStoreDirectory.assetPath).readAsString(),
    );
    final (lat, lng) = await tesco.geocode(location);
    final stores = directory.nearest(
      lat,
      lng,
      limit: 1,
      formats: largeOnly ? {'Superstore', 'Extra'} : null,
    );
    if (stores.isEmpty) {
      stderr.writeln('No Tesco stores found near "$location".');
      exit(1);
    }
    final store = stores.first;
    stdout.writeln(
      'Nearest store: ${store.name} (${store.format}, branch '
      '${store.branchNumber}) - ${store.address}, '
      '${store.distanceMiles?.toStringAsFixed(1)} mi',
    );

    final products = await tesco.fetchFoodProducts(
      storeId: store.branchNumber,
      onProgress: (department, fetched, total) =>
          stdout.write('\r  $department: $fetched / $total          '),
    );
    stdout.writeln('\nFetched ${products.length} products.');

    final details = <String, Map<String, dynamic>>{};
    if (withDetails) {
      for (final (i, p) in products.indexed) {
        final d = await tesco.fetchDetails(p.id);
        if (d != null) details[p.id] = d.toJson();
        stdout.write('\r  details: ${i + 1} / ${products.length}');
        await Future<void>.delayed(tesco.requestDelay);
      }
      stdout.writeln();
    }

    final json = {
      'location': location,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'store': store.toJson(),
      'productCount': products.length,
      'products': [
        for (final p in products)
          {...p.toJson(), if (details[p.id] != null) 'details': details[p.id]},
      ],
    };
    await File(outPath)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    stdout.writeln('Wrote $outPath');
  } on TescoException catch (e) {
    stderr.writeln(e);
    exit(1);
  } finally {
    tesco.close();
  }
}
