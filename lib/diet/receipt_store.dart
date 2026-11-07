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
      .instance.collection('users')
      .doc(userId)
      .collection('diet');

  /// Stored diet days, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> history() =>
      _diet.orderBy('date', descending: true).limit(90).snapshots();

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
      for (final entry
          in (current.data()?['nutrition'] as Map? ?? {}).entries)
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

  /// Deletes one stored day.
  Future<void> delete(String dayId) => _diet.doc(dayId).delete();

  String _dateId(DateTime day) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }
}
