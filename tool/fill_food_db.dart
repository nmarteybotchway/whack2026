/// Runs the whole food pipeline for a list of food names:
///
/// 1. `fill_food`: add new foods, refresh news on existing ones.
/// 2. `dedupe_food`: merge foods that are the same under different names.
/// 3. `generate_food`: regenerate `lib/food/known_foods.g.dart`.
///
/// ```sh
/// dart run tool/fill_food_db.dart food.txt            # update Firestore
/// dart run tool/fill_food_db.dart food.txt --dry-run  # print only
/// dart run tool/fill_food_db.dart food.txt --full     # regenerate all fields
/// ```
///
/// Foods that fail in step 1 are reported but do not stop the later steps.
/// A dry run skips step 3, since nothing in Firestore changed. `--full`
/// regenerates existing foods instead of only refreshing their news.
library;

import 'dart:io';

import 'dedupe_food.dart' as dedupe;
import 'fill_food.dart' as fill;
import 'generate_food.dart' as generate;

Future<void> main(List<String> arguments) async {
  final dryRun = arguments.contains('--dry-run');
  final files = arguments.where((a) => !a.startsWith('--')).toList();
  if (files.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/fill_food_db.dart <food.txt> [--dry-run] [--full]',
    );
    exit(64);
  }

  stdout.writeln('== 1/3 Fill ==');
  await fill.main(arguments);
  // fill_food sets exitCode when some foods fail; keep it for the end.
  final fillFailed = exitCode != 0;

  stdout.writeln('\n== 2/3 Dedupe ==');
  await dedupe.main([if (dryRun) '--dry-run']);

  stdout.writeln('\n== 3/3 Generate ==');
  if (dryRun) {
    stdout.writeln('Skipped (dry run).');
  } else {
    await generate.main();
  }

  if (fillFailed) exitCode = 1;
}
