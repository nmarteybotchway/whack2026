import 'package:flutter/material.dart';

import 'diet_window_service.dart';
import 'receipt_parser.dart';

/// Result of reviewing a scanned receipt: the confirmed items and the day
/// they were bought.
class ReviewedReceipt {
  const ReviewedReceipt({required this.items, required this.day});

  final List<ReceiptItem> items;
  final DateTime day;
}

/// Shows the items parsed from a scanned receipt for review, then asks for
/// the purchase date (defaulting to today).
///
/// Resolves to a [ReviewedReceipt] when the user saves, or null when they
/// want to retake the photo.
Future<ReviewedReceipt?> showReceiptReview(
  BuildContext context,
  List<ReceiptItem> items,
) {
  return showModalBottomSheet<ReviewedReceipt>(
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
  DateTime _day = DateTime.now();

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year && _day.month == now.month && _day.day == now.day;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      // Older days fall outside the diet window and would not be kept.
      firstDate: DietWindowService.cutoffFor(now),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = picked);
  }

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
              'Is this everything you bought? Remove anything that looks '
              'wrong, then save.',
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
            Card(
              child: ListTile(
                leading: const Icon(Icons.event),
                title: const Text('When did you get this?'),
                subtitle: Text(
                  _isToday
                      ? 'Today (tap to change)'
                      : _formatDay(_day),
                ),
                trailing: const Icon(Icons.edit_calendar),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _items.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      ReviewedReceipt(items: _items, day: _day),
                    ),
              child: Text(
                _items.isEmpty
                    ? 'No items to save'
                    : 'Save ${_items.length} items',
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

String _formatDay(DateTime day) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onRemove});

  final ReceiptItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(item.name),
      trailing: IconButton(
        tooltip: 'Remove item',
        icon: const Icon(Icons.delete_outline),
        onPressed: onRemove,
      ),
    );
  }
}
