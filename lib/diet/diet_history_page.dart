import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'diet_window_service.dart';
import 'nutrient_tracker_page.dart';
import 'receipt_scan_page.dart';

/// Diet history: scan grocery receipts and browse the stored diet, organised
/// by the day the food was bought.
class DietHistoryPage extends StatelessWidget {
  const DietHistoryPage({super.key, required this.userId});

  final String userId;

  Future<void> _scan(BuildContext context) async {
    if (!ReceiptScanPage.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Receipt scanning is only supported on Android and iOS.',
          ),
        ),
      );
      return;
    }
    final saved = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => ReceiptScanPage(userId: userId)),
    );
    if (saved == null || saved == 0 || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved $saved foods to your diet.')));
  }

  Future<void> _delete(
    BuildContext context,
    DietWindowService diet,
    String id,
  ) async {
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
      await diet.deleteDay(id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete. Check your connection and retry.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diet = DietWindowService(userId);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Diet history', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Scan grocery receipts to build a record of what you eat. Foods are '
          'grouped by the day you got them, and the last two weeks are kept.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _scan(context),
          icon: const Icon(Icons.receipt_long),
          label: const Text('Scan receipt'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NutrientTrackerPage(userId: userId),
            ),
          ),
          icon: const Icon(Icons.insights),
          label: const Text('Nutrient tracker'),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<DietDay>>(
          stream: diet.recentDaysStream(),
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
            final days = snapshot.data!;
            return Column(
              crossAxisAlignment: .stretch,
              children: [
                if (days.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No receipt purchases tracked yet.'),
                  ),
                for (final day in days)
                  _DayCard(
                    day: day,
                    onDelete: () => _delete(context, diet, day.id),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Text('Manual food logs', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'Foods you logged as eaten or purchased. These stay separate from receipt totals.',
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('foodEntries')
              .orderBy('localDate', descending: true)
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Cannot load manual food logs.');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) return const Text('No manual food logs yet.');
            return Column(
              children: [
                for (final doc in docs) _ManualEntryCard(data: doc.data()),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ManualEntryCard extends StatelessWidget {
  const _ManualEntryCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final localDay = data['localDay'];
    final date = localDay is String
        ? DateTime.tryParse(localDay)
        : (data['localDate'] as Timestamp?)?.toDate().toLocal();
    final kind = data['kind'] == 'eaten' ? 'Eaten' : 'Purchased';
    final amount = data['amount'];
    return Card(
      child: ListTile(
        leading: Icon(
          data['kind'] == 'eaten'
              ? Icons.restaurant
              : Icons.shopping_bag_outlined,
        ),
        title: Text(data['name'] as String? ?? 'Food'),
        subtitle: Text(
          [
            kind,
            if (amount is String && amount.isNotEmpty) amount,
            if (date != null) _formatDay(date),
          ].join(' · '),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.onDelete});

  final DietDay day;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = day.date;
    final foods = day.foods;
    final nutrition = day.nutrition;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(_formatDay(date)),
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
          if (nutrition.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: .centerLeft,
                child: Text(
                  'Nutrients hit',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: .centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in nutrition.entries)
                      _NutrientBox(shorthand: entry.key, value: entry.value),
                  ],
                ),
              ),
            ),
          ],
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

/// A small box showing one nutrient's shorthand and aggregated amount.
class _NutrientBox extends StatelessWidget {
  const _NutrientBox({required this.shorthand, required this.value});

  final String shorthand;
  final double value;

  static const _labels = {
    'CA': ('Calcium', 'MG'),
    'NA': ('Sodium', 'MG'),
    'FE': ('Iron', 'MG'),
    'K': ('Potassium', 'MG'),
    'MG': ('Magnesium', 'MG'),
    'ZN': ('Zinc', 'MG'),
    'VITA': ('Vitamin A', 'UG'),
    'VITB6': ('Vitamin B6', 'MG'),
    'VITB12': ('Vitamin B12', 'UG'),
    'VITC': ('Vitamin C', 'MG'),
    'VITD': ('Vitamin D', 'UG'),
    'VITE': ('Vitamin E', 'MG'),
    'VITK': ('Vitamin K', 'UG'),
    'FOL': ('Folate', 'UG'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (label, unit) = _labels[shorthand] ?? (shorthand, '');
    final amount = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(value >= 10 ? 1 : 2);
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(
              shorthand,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$amount${unit == 'UG' ? 'µg' : 'mg'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDay(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
