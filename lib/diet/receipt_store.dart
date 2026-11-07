import 'package:cloud_firestore/cloud_firestore.dart';

import 'receipt_parser.dart';

/// Stores the user's diet in Firestore, organised by date.
///
/// Each day is one document at `users/{uid}/diet/{yyyy-MM-dd}` holding only
/// the food names from that day's receipts — prices and quantities are not
/// kept. Scanning another receipt for the same day appends to that day's
/// foods.
class ReceiptStore {
  ReceiptStore(this.userId);

  final String userId;

  CollectionReference<Map<String, dynamic>> get _diet => FirebaseFirestore
      .instance.collection('users')
      .doc(userId)
      .collection('diet');

  /// Stored diet days, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> history() =>
      _diet.orderBy('date', descending: true).limit(90).snapshots();

  /// Saves the food [items] from a receipt under [day].
  Future<void> save(List<ReceiptItem> items, DateTime day) async {
    final dateId = _dateId(day);
    final names = items.map((item) => item.name).toList();
    await _diet.doc(dateId).set({
      'date': Timestamp.fromDate(DateTime(day.year, day.month, day.day)),
      'foods': FieldValue.arrayUnion(names),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deletes one stored day.
  Future<void> delete(String dayId) => _diet.doc(dayId).delete();

  String _dateId(DateTime day) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }
}
