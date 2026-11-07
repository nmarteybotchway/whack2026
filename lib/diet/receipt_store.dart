import 'package:cloud_firestore/cloud_firestore.dart';

import 'receipt_parser.dart';

/// Stores scanned receipts in the signed-in user's Firestore account.
class ReceiptStore {
  ReceiptStore(this.userId);

  final String userId;

  CollectionReference<Map<String, dynamic>> get _receipts => FirebaseFirestore
      .instance.collection('users')
      .doc(userId)
      .collection('receipts');

  /// Latest scanned receipts, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> history() =>
      _receipts.orderBy('scannedAt', descending: true).limit(50).snapshots();

  /// Saves one scanned receipt with its items.
  Future<void> save(List<ReceiptItem> items) async {
    final total = items.fold<double>(0, (acc, item) => acc + item.lineTotal);
    await _receipts.add({
      'scannedAt': FieldValue.serverTimestamp(),
      'items': [for (final item in items) item.toMap()],
      'total': double.parse(total.toStringAsFixed(2)),
    });
  }

  /// Deletes a single scanned receipt.
  Future<void> delete(String receiptId) => _receipts.doc(receiptId).delete();
}
