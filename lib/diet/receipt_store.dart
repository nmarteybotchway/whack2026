import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'nutrition_service.dart';
import 'receipt_parser.dart';

/// Stores the user's diet in Firestore, organised by date.
///
/// Each day is one document at `users/{uid}/diet/{yyyy-MM-dd}` holding the
/// food names from that day's receipts, plus the quantity bought and amount
/// spent per food. Scanning another receipt for the same day appends to that
/// day's foods and adds to its quantities. Alongside the foods, the day
/// accumulates the aggregated vitamins and minerals of everything bought,
/// looked up via [NutritionService].
class ReceiptStore {
  ReceiptStore(this.userId, {NutritionService? nutrition})
    : nutrition = nutrition ?? NutritionService();

  final String userId;

  final NutritionService nutrition;

  CollectionReference<Map<String, dynamic>> get _diet => FirebaseFirestore
      .instance
      .collection('users')
      .doc(userId)
      .collection('diet');

  /// Stored diet days, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> history() =>
      _diet.orderBy('date', descending: true).limit(90).snapshots();

  /// Deletes every day strictly older than [cutoff] in one batch and
  /// returns the day ids that were removed.
  Future<List<String>> deleteOlderThan(DateTime cutoff) async {
    final old = await _diet
        .where('date', isLessThan: Timestamp.fromDate(cutoff))
        .get();
    if (old.docs.isEmpty) return const [];
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in old.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return [for (final doc in old.docs) doc.id];
  }

  /// Saves the food [items] from a receipt under [day], enriching the day
  /// with the aggregated nutrients of the new foods.
  Future<void> save(List<ReceiptItem> items, DateTime day) async {
    final dateId = _dateId(day);
    final names = items.map((item) => item.name).toList();
    final totals = await nutrition.totalsFor(names);
    await _diet.doc(dateId).set(
      dayWrite(items, totals, day),
      SetOptions(merge: true),
    );
  }

  /// The merge write [save] sends for one receipt on [day].
  ///
  /// Each nutrient, quantity, and spend is incremented server-side so
  /// earlier receipts for the same day keep their totals. The `nutrition`
  /// key is omitted when there is nothing to add, because merging an empty
  /// map would replace the day's existing nutrition with `{}`.
  @visibleForTesting
  static Map<String, Object> dayWrite(
    List<ReceiptItem> items,
    Map<String, double> totals,
    DateTime day,
  ) {
    // The same food can appear on several receipt lines; merge them first
    // so each name gets one increment.
    final quantities = <String, int>{};
    final spent = <String, double>{};
    for (final item in items) {
      quantities[item.name] = (quantities[item.name] ?? 0) + item.quantity;
      spent[item.name] = (spent[item.name] ?? 0) + item.lineTotal;
    }
    return {
      'date': Timestamp.fromDate(DateTime(day.year, day.month, day.day)),
      'foods': FieldValue.arrayUnion(quantities.keys.toList()),
      if (quantities.isNotEmpty)
        'items': {
          for (final name in quantities.keys)
            name: {
              'quantity': FieldValue.increment(quantities[name]!),
              'spent': FieldValue.increment(
                double.parse(spent[name]!.toStringAsFixed(2)),
              ),
            },
        },
      if (totals.isNotEmpty)
        'nutrition': {
          for (final entry in totals.entries)
            entry.key: FieldValue.increment(
              double.parse(entry.value.toStringAsFixed(2)),
            ),
        },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Nutrient totals per day since [start] for foods logged through the
  /// assistant (eaten or purchased), looked up individually. Receipt days
  /// come from `DietWindowService` instead.
  Future<Map<DateTime, Map<String, double>>> loggedIntakeSince(
    DateTime start,
  ) async {
    final intake = <DateTime, Map<String, double>>{};
    void add(DateTime date, Map<String, double> values) {
      final into = intake.putIfAbsent(
        DateTime(date.year, date.month, date.day),
        () => {},
      );
      values.forEach((k, v) => into[k] = (into[k] ?? 0) + v);
    }

    final entries = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('foodEntries')
        .where('localDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .get();
    for (final doc in entries.docs) {
      final name = doc.data()['name'];
      final date = (doc.data()['localDate'] as Timestamp?)?.toDate().toLocal();
      if (name is! String || date == null) continue;
      try {
        add(date, await nutrition.nutrientsFor(name));
      } on Exception {
        continue;
      }
    }
    return intake;
  }

  /// Deletes one stored day.
  Future<void> delete(String dayId) => _diet.doc(dayId).delete();

  String _dateId(DateTime day) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }
}
