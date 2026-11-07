import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'receipt_parser.dart';
import 'receipt_scan_page.dart';
import 'receipt_store.dart';

/// Diet history: scan grocery receipts and review everything stored so far.
class DietHistoryPage extends StatelessWidget {
  const DietHistoryPage({super.key, required this.userId});

  final String userId;

  Future<void> _scan(BuildContext context) async {
    if (!ReceiptScanPage.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Receipt scanning is only supported on Android and iOS.'),
      ));
      return;
    }
    final saved = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => ReceiptScanPage(userId: userId)),
    );
    if (saved == null || saved == 0 || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved $saved items from your receipt.')),
    );
  }

  Future<void> _delete(BuildContext context, ReceiptStore store, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: const Text('This deletes the receipt and its items from Firebase.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await store.delete(id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not delete the receipt. Check your connection and retry.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = ReceiptStore(userId);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Diet history', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Scan grocery receipts to build a record of what you buy. Items are '
          'stored with your account so they can be used for diet tracking '
          'later on.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _scan(context),
          icon: const Icon(Icons.receipt_long),
          label: const Text('Scan receipt'),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: store.history(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text(
                'Cannot load receipts. Check Firebase Authentication, '
                'Firestore, and security rules.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) return const Text('No receipts scanned yet.');
            return Column(
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  snapshot.data!.metadata.isFromCache
                      ? 'Saved receipts (cached)'
                      : 'Scanned receipts',
                ),
                for (final doc in docs)
                  _ReceiptCard(
                    data: doc.data(),
                    onDelete: () => _delete(context, store, doc.id),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.data, required this.onDelete});

  final Map<String, dynamic> data;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scannedAt = (data['scannedAt'] as Timestamp?)?.toDate().toLocal();
    final items = [
      for (final raw in (data['items'] as List? ?? []))
        ReceiptItem.fromMap(Map<String, dynamic>.from(raw as Map)),
    ];
    final total = (data['total'] as num?)?.toDouble() ??
        items.fold<double>(0, (acc, item) => acc + item.lineTotal);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(scannedAt == null ? 'Receipt' : _formatDate(scannedAt)),
        subtitle: Text('${items.length} items · Total ${total.toStringAsFixed(2)}'),
        children: [
          for (final item in items)
            ListTile(
              dense: true,
              title: Text(item.name),
              subtitle: item.quantity > 1
                  ? Text('Qty ${item.quantity} × ${item.price.toStringAsFixed(2)}')
                  : null,
              trailing: Text(item.lineTotal.toStringAsFixed(2)),
            ),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete receipt'),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}
