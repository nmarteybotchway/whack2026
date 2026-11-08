/// Formats a receipt amount for display, e.g. `£1.65`.
String formatPrice(double amount) => '£${amount.toStringAsFixed(2)}';

/// An item extracted from a scanned receipt.
class ReceiptItem {
  const ReceiptItem({required this.name, required this.price, this.quantity = 1});

  final String name;

  /// Unit price as printed on the receipt.
  final double price;
  final int quantity;

  double get lineTotal => price * quantity;

  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'quantity': quantity,
  };

  factory ReceiptItem.fromMap(Map<String, dynamic> map) => ReceiptItem(
    name: map['name'] as String,
    price: (map['price'] as num).toDouble(),
    quantity: (map['quantity'] as num? ?? 1).toInt(),
  );
}

/// Header, payment and other receipt lines that are never products.
final _skipLine = RegExp(
  r'^(sub\s*total|total|amount\s+due|balance|tax(es)?|vat|gst|hst|pst|qst|'
  r'change|cash|card\b|visa|master\s*card|amex|debit|credit|tender|payment|'
  r'paid|tip|gratuity|discount|savings?|saved|coupon|promo|offer|multibuy|'
  r'loyalty|points?|rewards?|member|cashier|register|terminal|invoice|'
  r'receipt|order|date|time|phone|tel\.?|www\.|https?|thank|thanks|come\s+again|'
  r'item\s+count|#\s*items|approx|approval|auth(?:orization)?|ref\b|seq|'
  r'trans?(?:action)?|merchant|customer|account|survey|feedback)',
  caseSensitive: false,
);

/// A line that is nothing but a price, e.g. "2.49" or "$12.90-".
///
/// OCR often keeps the tax flag receipts print after the price ("2.49 F"),
/// so a single trailing flag letter is tolerated.
final _priceOnly = RegExp(r'^[$€£]?\s*(\d{1,5})[.,](\d{2})\s*-?[A-Za-z]?$');

/// A name and a price on the same line, e.g. "WHOLE MILK 2.49" or the
/// space-less "MILK2.49" some OCR runs produce.
final _nameAndPrice = RegExp(
  r'^(.+?)(?:\s*|\s)(?:[$€£]\s*)?(\d{1,5})[.,](\d{2})\s*-?[A-Za-z]?$',
);

/// "MILK 2 @ 1.50 3.00": unit price with a quantity, and an optional line
/// total after it.
final _qtyAtUnitPrice = RegExp(
  r'^(.+?)\s+(\d{1,3})\s*@\s*[$€£]?(\d{1,5})[.,](\d{2})(?:\s+[$€£]?\d{1,5}[.,]\d{2})?\s*$',
);

/// A leading quantity, e.g. "2 X WHOLE MILK" or "3 @ 1.20".
final _qtyPrefix = RegExp(r'^(\d{1,3})\s*[xX*@]\s*(.+)$');

/// A trailing quantity, e.g. "WHOLE MILK 2 X".
final _qtySuffix = RegExp(r'^(.+?)\s+(\d{1,3})\s*[xX*@]$');

final _digitsOnly = RegExp(r'^\d+$');
final _whitespace = RegExp(r'\s+');

/// Parses the raw text [TextRecognizer] read off a receipt into items.
///
/// Receipts put the price after the item name, often on the next line, so
/// name-only lines are held back until a price line completes them. Anything
/// that cannot be attached to a price is discarded — better to miss an item
/// than to store garbage.
List<ReceiptItem> parseReceiptItems(String text) {
  final items = <ReceiptItem>[];
  String? pendingName;
  int pendingQty = 1;

  void complete(String name, double price, int quantity) {
    final cleaned = _cleanName(name);
    if (cleaned.isEmpty) return;
    items.add(ReceiptItem(name: cleaned, price: price, quantity: quantity));
  }

  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim().replaceAll(_whitespace, ' ');
    if (line.isEmpty) continue;
    if (_skipLine.hasMatch(line) || _digitsOnly.hasMatch(line)) {
      pendingName = null;
      pendingQty = 1;
      continue;
    }

    // "2 X MILK 1.50", "3 @ 1.20": a quantity may prefix the rest of the line.
    var rest = line;
    var quantity = 1;
    final qty = _qtyPrefix.firstMatch(line);
    if (qty != null) {
      quantity = int.tryParse(qty.group(1)!) ?? 1;
      rest = qty.group(2)!;
      if (quantity < 1 || quantity > 99) quantity = 1;
    }

    final priceOnly = _priceOnly.firstMatch(rest);
    if (priceOnly != null) {
      // A bare price completes the item named on the previous line(s).
      final price = _toPrice(priceOnly.group(1)!, priceOnly.group(2)!);
      if (pendingName != null) {
        complete(pendingName, price, quantity * pendingQty);
        pendingName = null;
        pendingQty = 1;
      }
      continue;
    }

    final atUnit = _qtyAtUnitPrice.firstMatch(rest);
    if (atUnit != null) {
      final price = _toPrice(atUnit.group(3)!, atUnit.group(4)!);
      complete(atUnit.group(1)!, price, int.parse(atUnit.group(2)!));
      pendingName = null;
      pendingQty = 1;
      continue;
    }

    final nameAndPrice = _nameAndPrice.firstMatch(rest);
    if (nameAndPrice != null) {
      var name = nameAndPrice.group(1)!;
      // "MILK 2 X 1.50": the quantity can also trail the name.
      final trailing = _qtySuffix.firstMatch(name);
      if (trailing != null) {
        final q = int.tryParse(trailing.group(2)!);
        if (q != null && q >= 1 && q <= 99) quantity *= q;
        name = trailing.group(1)!;
      }
      final price = _toPrice(nameAndPrice.group(2)!, nameAndPrice.group(3)!);
      complete(name, price, quantity * pendingQty);
      pendingName = null;
      pendingQty = 1;
      continue;
    }

    // No price yet: remember the name until a price line arrives.
    final combined = pendingName == null ? rest : '$pendingName $rest';
    pendingName = combined.length <= 80 ? combined : rest;
    pendingQty = quantity;
  }
  return items;
}

double _toPrice(String whole, String fraction) =>
    int.parse(whole) + int.parse(fraction) / 100;

/// Trims separator noise OCR leaves around product names.
String _cleanName(String name) {
  name = name
      .replaceAll(RegExp(r'^[^A-Za-z0-9%]+|[^A-Za-z0-9%)]+$'), '')
      .replaceAll(_whitespace, ' ')
      .trim();
  // Drop names that are just numbers or item codes.
  if (name.length < 2 || _digitsOnly.hasMatch(name.replaceAll(' ', ''))) return '';
  return name;
}
