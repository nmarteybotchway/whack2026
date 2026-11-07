import 'package:cloud_firestore/cloud_firestore.dart';

import 'nutrition_service.dart';
import 'receipt_parser.dart';

/// Stores the user's diet in Firestore, organised by date.
///
/// Each day is one document at `users/{uid}/diet/{yyyy-MM-dd}` holding only
/// the food names from that day's receipts — prices and quantities are not
/// kept. Scanning another receipt for the same day appends to that day's
/// foods. Alongside the foods, the day accumulates the aggregated vitamins
/// and minerals of everything bought, looked up via [NutritionService].
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
    await _diet.doc(dateId).set({
      'date': Timestamp.fromDate(DateTime(day.year, day.month, day.day)),
      'foods': FieldValue.arrayUnion(names),
      'nutrition': <String, double>{},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (totals.isEmpty) return;

    // Merge into whatever the day already accumulated.
    final current = await _diet.doc(dateId).get();
    final existing = <String, double>{
      for (final entry in (current.data()?['nutrition'] as Map? ?? {}).entries)
        if (entry.value is num) '${entry.key}': (entry.value as num).toDouble(),
    };
    totals.forEach((key, value) {
      existing[key] = (existing[key] ?? 0) + value;
    });
    await _diet.doc(dateId).update({
      'nutrition': {
        for (final entry in existing.entries)
          entry.key: double.parse(entry.value.toStringAsFixed(2)),
      },
    });
  }

  /// Nutrient totals per day since [start]: receipt days plus foods logged
  /// through the assistant (eaten or purchased), looked up individually.
  Future<Map<DateTime, Map<String, double>>> intakeSince(DateTime start) async {
    final intake = <DateTime, Map<String, double>>{};
    void add(DateTime date, Map<String, double> values) {
      final into = intake.putIfAbsent(
        DateTime(date.year, date.month, date.day),
        () => {},
      );
      values.forEach((k, v) => into[k] = (into[k] ?? 0) + v);
    }

    final days = await _diet
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .get();
    for (final doc in days.docs) {
      final date = (doc.data()['date'] as Timestamp?)?.toDate().toLocal();
      if (date == null) continue;
      add(date, {
        for (final entry in (doc.data()['nutrition'] as Map? ?? {}).entries)
          if (entry.value is num)
            '${entry.key}': (entry.value as num).toDouble(),
      });
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
