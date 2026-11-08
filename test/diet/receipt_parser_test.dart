import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/receipt_parser.dart';

void main() {
  test('pairs price-only lines with the preceding item name', () {
    final items = parseReceiptItems(
      'WHOLE MILK 1L\n2.49\nBREAD WHITE\n1.19\n',
    );
    expect(items, hasLength(2));
    expect(items[0].name, 'WHOLE MILK 1L');
    expect(items[0].price, 2.49);
    expect(items[0].quantity, 1);
    expect(items[1].name, 'BREAD WHITE');
    expect(items[1].price, 1.19);
  });

  test('reads name and price on a single line', () {
    final items = parseReceiptItems('COKE 1.5L 2.50\n');
    expect(items.single.name, 'COKE 1.5L');
    expect(items.single.price, 2.50);
  });

  test('skips totals, tax, and payment lines', () {
    final items = parseReceiptItems(
      'MILK 2.49\nSUBTOTAL 2.49\nTAX 0.15\nTOTAL 2.64\nCASH 10.00\nCHANGE 7.36\n',
    );
    expect(items, hasLength(1));
    expect(items.single.name, 'MILK');
  });

  test('does not skip products containing skip keywords mid-name', () {
    final items = parseReceiptItems('CARDAMOM BREAD 3.10\n');
    expect(items.single.name, 'CARDAMOM BREAD');
  });

  test('reads a quantity prefix', () {
    final items = parseReceiptItems('2 X YOGHURT\n1.20\n');
    expect(items.single.name, 'YOGHURT');
    expect(items.single.quantity, 2);
    expect(items.single.lineTotal, closeTo(2.40, 0.001));
  });

  test('handles comma decimals and currency symbols', () {
    final items = parseReceiptItems('€ CHEESE, 3,90\n');
    expect(items.single.price, closeTo(3.90, 0.001));
  });

  test('discards trailing names with no price', () {
    final items = parseReceiptItems('MILK 2.49\nTHANK YOU FOR SHOPPING\n');
    expect(items, hasLength(1));
  });

  test('round-trips through Firestore maps', () {
    const item = ReceiptItem(name: 'MILK', price: 2.49, quantity: 3);
    final restored = ReceiptItem.fromMap(item.toMap());
    expect(restored.name, 'MILK');
    expect(restored.price, 2.49);
    expect(restored.quantity, 3);
  });

  test('tolerates a tax flag letter after the price', () {
    final items = parseReceiptItems('MILK 2.49 F\nBREAD 1.19 N\n');
    expect(items, hasLength(2));
    expect(items[0].price, 2.49);
    expect(items[1].price, 1.19);
  });

  test('reads price glued to the name', () {
    final items = parseReceiptItems('MILK2.49\n');
    expect(items.single.name, 'MILK');
    expect(items.single.price, 2.49);
  });

  test('reads quantity-at-unit-price lines with a line total', () {
    final items = parseReceiptItems('YOGHURT 2 @ 1.50 3.00\n');
    expect(items.single.name, 'YOGHURT');
    expect(items.single.price, 1.50);
    expect(items.single.quantity, 2);
    expect(items.single.lineTotal, closeTo(3.00, 0.001));
  });
}
