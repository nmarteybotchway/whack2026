import 'package:flutter/material.dart';

import 'receipt_parser.dart';

/// Shows the items parsed from a scanned receipt for review.
///
/// Resolves to the final item list when the user saves, or null when they
/// want to retake the photo.
Future<List<ReceiptItem>?> showReceiptReview(
  BuildContext context,
  List<ReceiptItem> items,
) {
  return showModalBottomSheet<List<ReceiptItem>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ReceiptReviewSheet(items: items),
  );
}

/// Bottom-sheet content reviewing the parsed receipt items.
class ReceiptReviewSheet extends StatefulWidget {
  const ReceiptReviewSheet({super.key, required this.items});

  final List<ReceiptItem> items;

  @override
  State<ReceiptReviewSheet> createState() => _ReceiptReviewSheetState();
}

class _ReceiptReviewSheetState extends State<ReceiptReviewSheet> {
  late final List<ReceiptItem> _items = List.of(widget.items);

  double get _total => _items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: [
            Text('Receipt items', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Check what was read from your receipt. Remove anything that '
              'looks wrong, then save.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No items left.')),
              )
            else
              for (var i = 0; i < _items.length; i++) _ItemTile(
                item: _items[i],
                onRemove: () => setState(() => _items.removeAt(i)),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                Text('Total', style: theme.textTheme.titleMedium),
                Text(
                  _total.toStringAsFixed(2),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _items.isEmpty ? null : () => Navigator.pop(context, _items),
              child: Text(
                _items.isEmpty ? 'No items to save' : 'Save ${_items.length} items',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Retake photo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onRemove});

  final ReceiptItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantity = item.quantity;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(item.name),
      subtitle: quantity > 1 ? Text('Qty $quantity × ${item.price.toStringAsFixed(2)}') : null,
      trailing: Row(
        mainAxisSize: .min,
        children: [
          Text(
            item.lineTotal.toStringAsFixed(2),
            style: theme.textTheme.bodyLarge,
          ),
          IconButton(
            tooltip: 'Remove item',
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
