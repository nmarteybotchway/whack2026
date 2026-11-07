import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'receipt_scan_page.dart';
import 'receipt_store.dart';

/// Diet history: scan grocery receipts and browse the stored diet, organised
/// by the day the food was bought.
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
      SnackBar(content: Text('Saved $saved foods to your diet.')),
    );
  }

  Future<void> _delete(BuildContext context, ReceiptStore store, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this day?'),
        content: const Text(
          'This deletes every food stored for that day from Firebase.',
        ),
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
          content: Text('Could not delete. Check your connection and retry.'),
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
          'Scan grocery receipts to build a record of what you eat. Foods are '
          'grouped by the day you got them.',
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
                'Cannot load your diet. Check Firebase Authentication, '
                'Firestore, and security rules.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) return const Text('No foods tracked yet. Scan a receipt to start.');
            return Column(
              crossAxisAlignment: .stretch,
              children: [
                if (snapshot.data!.metadata.isFromCache)
                  const Text('Saved diet (cached)'),
                for (final doc in docs)
                  _DayCard(
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

class _DayCard extends StatelessWidget {
  const _DayCard({required this.data, required this.onDelete});

  final Map<String, dynamic> data;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = (data['date'] as Timestamp?)?.toDate().toLocal();
    final foods = List<String>.from(data['foods'] ?? const []);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(date == null ? 'Unknown date' : _formatDay(date)),
        subtitle: Text('${foods.length} foods'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: .centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final food in foods) Chip(label: Text(food))],
              ),
            ),
          ),
          Align(
            alignment: .centerLeft,
            child: TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete day'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDay(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
