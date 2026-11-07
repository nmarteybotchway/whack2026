import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/receipt_store.dart';

void main() {
  final day = DateTime(2026, 11, 7, 15, 30);

  test('dayWrite increments each nutrient so same-day receipts add up', () {
    final write = ReceiptStore.dayWrite(['Milk'], {'CA': 120.456, 'K': 150}, day);

    expect(write['date'], Timestamp.fromDate(DateTime(2026, 11, 7)));
    expect(write['foods'], FieldValue.arrayUnion(['Milk']));
    expect(write['nutrition'], {
      'CA': FieldValue.increment(120.46),
      'K': FieldValue.increment(150.0),
    });
  });

  test('dayWrite leaves nutrition out when there is nothing to add', () {
    // Merging `nutrition: {}` would wipe the day's existing totals.
    final write = ReceiptStore.dayWrite(['Mystery item'], const {}, day);

    expect(write.containsKey('nutrition'), isFalse);
    expect(write['foods'], FieldValue.arrayUnion(['Mystery item']));
  });
}
