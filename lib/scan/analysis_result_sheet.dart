import 'package:flutter/material.dart';

import 'camera_analysis.dart';
import 'product_identification_service.dart';

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
            Text('Product scan', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (result.error != null)
              _ScanError(result.error!)
            else if (result.identification != null)
              _ProductCard(product: result.identification!)
            else if (result.item != null)
              _ItemCard(item: result.item!)
            else
              const _ScanError(
                'No product details were returned. Please try again.',
              ),
            if (result.identification == null && alternative != null) ...[
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

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final ProductIdentification product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = product.displayName.isEmpty
        ? 'Product not identified'
        : product.displayName;
    final statusText = switch (product.status) {
      'identified' => 'Model estimate: ${product.confidence}%',
      'ambiguous' => 'Possible match · model estimate ${product.confidence}%',
      'unreadable' => 'Packaging is difficult to read',
      _ => 'No packaged product detected',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(statusText, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              'Confidence values are estimates from the visible packaging.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            _ProductField(
              label: 'Brand',
              value: product.brand,
              confidence: product.brandConfidence,
            ),
            _ProductField(
              label: 'Product',
              value: product.productName,
              confidence: product.productNameConfidence,
            ),
            _ProductField(
              label: 'Variant',
              value: product.variant,
              confidence: product.variantConfidence,
            ),
            _ProductField(
              label: 'Pack size',
              value: product.packageSize,
              confidence: null,
            ),
            _ProductField(
              label: 'SKU (if printed)',
              value: product.sku,
              confidence: product.skuConfidence,
            ),
            _ProductField(
              label: 'Barcode / GTIN',
              value: product.gtin,
              confidence: product.gtinConfidence,
            ),
            if (product.evidence.isNotEmpty ||
                product.uncertainties.isNotEmpty) ...[
              const Divider(height: 24),
              if (product.evidence.isNotEmpty) ...[
                Text('Visible evidence', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final evidence in product.evidence)
                  Text('• $evidence', style: theme.textTheme.bodyMedium),
              ],
              if (product.uncertainties.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Needs a clearer photo',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                for (final uncertainty in product.uncertainties)
                  Text('• $uncertainty', style: theme.textTheme.bodyMedium),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductField extends StatelessWidget {
  const _ProductField({
    required this.label,
    required this.value,
    required this.confidence,
  });

  final String label;
  final String? value;
  final int? confidence;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'Not found in photo',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (confidence != null) Text('$confidence%'),
        ],
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
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
