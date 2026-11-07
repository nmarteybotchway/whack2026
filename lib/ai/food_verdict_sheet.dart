import 'package:flutter/material.dart';

import 'food_verdict.dart';

/// Shows a [FoodVerdict] in a modal bottom sheet over the current page.
Future<void> showFoodVerdict(BuildContext context, FoodVerdict verdict) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FoodVerdictSheet(verdict: verdict),
  );
}

/// Bottom-sheet content describing a [FoodVerdict]: a green pass banner or a
/// red fail banner followed by one card per violation.
class FoodVerdictSheet extends StatelessWidget {
  const FoodVerdictSheet({super.key, required this.verdict});

  final FoodVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verdict.pass ? Colors.green : Colors.red;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: [
            Text('Food check', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(verdict.food, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color),
              ),
              child: Row(
                children: [
                  Icon(
                    verdict.pass ? Icons.check_circle : Icons.cancel,
                    color: color,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      verdict.pass
                          ? 'Fits your preferences'
                          : 'Does not fit your preferences',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final violation in verdict.violations) ...[
              const SizedBox(height: 12),
              _ViolationCard(violation: violation),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViolationCard extends StatelessWidget {
  const _ViolationCard({required this.violation});

  final FoodViolation violation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Row(
              children: [
                Chip(
                  avatar: Icon(
                    violation.category == 'religion'
                        ? Icons.church
                        : Icons.restaurant,
                    size: 18,
                  ),
                  label: Text(violation.rule),
                  visualDensity: .compact,
                ),
                const Spacer(),
                Text(
                  violation.ingredient,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(violation.reason, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
