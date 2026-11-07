import 'package:flutter/material.dart';

import 'camera_analysis.dart';

/// Shows [result] in a modal bottom sheet over the scan page.
Future<void> showAnalysisResult(BuildContext context, AnalysisResult result) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => AnalysisResultSheet(result: result),
  );
}

/// Bottom-sheet content describing an [AnalysisResult].
class AnalysisResultSheet extends StatelessWidget {
  const AnalysisResultSheet({super.key, required this.result});

  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alternative = result.alternative;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: [
            Text('Camera analysis', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _ItemCard(item: result.item),
            if (alternative != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Try instead', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              _ItemCard(item: alternative, highlighted: true),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Scan again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.highlighted = false});

  final AnalysedItem item;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: highlighted ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: .start,
          children: [
            _ScoreBadge(score: item.score),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(item.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (final highlight in item.highlights)
                    Text('• $highlight', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 60
        ? Colors.green
        : score >= 40
        ? Colors.orange
        : Colors.red;
    return SizedBox.square(
      dimension: 56,
      child: Stack(
        alignment: .center,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            color: color,
            backgroundColor: color.withValues(alpha: 0.2),
            strokeWidth: 5,
          ),
          Text(
            '$score',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
