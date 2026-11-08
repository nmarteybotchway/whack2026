import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/receipt_parser.dart';
import 'package:hackathon/diet/receipt_store.dart';

void main() {
  final day = DateTime(2026, 11, 7, 15, 30);

  test('dayWrite increments each nutrient so same-day receipts add up', () {
    final write = ReceiptStore.dayWrite(
      const [ReceiptItem(name: 'Milk', price: 1.65)],
      {'CA': 120.456, 'K': 150},
      day,
    );

    expect(write['date'], Timestamp.fromDate(DateTime(2026, 11, 7)));
    expect(write['foods'], FieldValue.arrayUnion(['Milk']));
    expect(write['nutrition'], {
      'CA': FieldValue.increment(120.46),
      'K': FieldValue.increment(150.0),
    });
  });

  test('dayWrite leaves nutrition out when there is nothing to add', () {
    // Merging `nutrition: {}` would wipe the day's existing totals.
    final write = ReceiptStore.dayWrite(
      const [ReceiptItem(name: 'Mystery item', price: 2)],
      const {},
      day,
    );

    expect(write.containsKey('nutrition'), isFalse);
    expect(write['foods'], FieldValue.arrayUnion(['Mystery item']));
  });

  test('dayWrite increments quantity and spend per food, merging repeats', () {
    final write = ReceiptStore.dayWrite(
      const [
        ReceiptItem(name: 'Yoghurt', price: 1.2, quantity: 3),
        ReceiptItem(name: 'Bread', price: 1.4),
        ReceiptItem(name: 'Yoghurt', price: 1.2),
      ],
      const {},
      day,
    );

    expect(write['foods'], FieldValue.arrayUnion(['Yoghurt', 'Bread']));
    expect(write['items'], {
      'Yoghurt': {
        'quantity': FieldValue.increment(4),
        'spent': FieldValue.increment(4.8),
      },
      'Bread': {
        'quantity': FieldValue.increment(1),
        'spent': FieldValue.increment(1.4),
      },
    });
  });
}
