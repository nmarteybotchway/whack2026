import 'package:flutter/material.dart';

import '../food/food_recommendation_service.dart';
import '../food_news.dart';
import 'camera_analysis.dart';
import 'product_identification_service.dart';

/// Shows [result] in a modal bottom sheet over the scan page.
///
/// Pass [newsService] to show a food news alert under the product details.
/// Pass [recommendationService] and [userId] to also show whether the food
/// is safe for this user and what to buy instead.
Future<void> showAnalysisResult(
  BuildContext context,
  AnalysisResult result, {
  FoodNewsService? newsService,
  FoodRecommendationService? recommendationService,
  String? userId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => AnalysisResultSheet(
      result: result,
      newsService: newsService,
      recommendationService: recommendationService,
      userId: userId,
    ),
  );
}

/// Bottom-sheet content describing an [AnalysisResult].
class AnalysisResultSheet extends StatelessWidget {
  const AnalysisResultSheet({
    super.key,
    required this.result,
    this.newsService,
    this.recommendationService,
    this.userId,
  });

  final AnalysisResult result;
  final FoodNewsService? newsService;
  final FoodRecommendationService? recommendationService;

  /// Signed-in user whose preferences and health data the
  /// [recommendationService] checks against.
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alternative = result.alternative;
    final newsService = this.newsService;
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
            if (newsService != null &&
                result.identification != null &&
                result.error == null) ...[
              const SizedBox(height: 16),
              _FoodNewsAlert(
                service: newsService,
                foodName: _newsFoodName(result.identification!),
              ),
            ],
            if (recommendationService != null &&
                userId != null &&
                result.identification != null &&
                result.error == null) ...[
              const SizedBox(height: 16),
              _RecommendationCard(
                service: recommendationService!,
                userId: userId!,
                foodName: _newsFoodName(result.identification!),
              ),
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

/// The name the food news service looks up for a scanned product.
String _newsFoodName(ProductIdentification product) {
  final productName = product.productName;
  return (productName != null && productName.isNotEmpty)
      ? productName
      : product.displayName;
}

/// Food news alert for a scanned product: a green no-news card when the
/// database has nothing, or an alert card with local news (always listed
/// before general info) when it does.
class _FoodNewsAlert extends StatelessWidget {
  const _FoodNewsAlert({required this.service, required this.foodName});

  final FoodNewsService service;
  final String foodName;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FoodNewsResult>(
      future: service.getNews(foodName),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final news = snap.data!;
        final theme = Theme.of(context);
        if (!news.hasAlerts) {
          return Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      FoodNewsService.noNewsMessage,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Text('Food alert', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                if (news.localNews != FoodNewsService.noNewsMessage)
                  Text('Local news: ${news.localNews}',
                      style: theme.textTheme.bodyMedium),
                if (news.generalInfo != FoodNewsService.noNewsMessage) ...[
                  if (news.localNews != FoodNewsService.noNewsMessage)
                    const SizedBox(height: 4),
                  Text('General info: ${news.generalInfo}',
                      style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Personal buy/avoid verdict for a scanned product, checked against the
/// signed-in user's preferences and health data: a green "safe to buy" card
/// when nothing applies, or a red card with the reasons and what to buy
/// instead.
class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.service,
    required this.userId,
    required this.foodName,
  });

  final FoodRecommendationService service;
  final String userId;
  final String foodName;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FoodRecommendation>(
      future: service.recommendFor(uid: userId, foodName: foodName),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final r = snap.data!;
        final theme = Theme.of(context);
        if (r.canBuy) {
          return Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Safe to buy: no news or general info and it matches '
                      'none of your preferences or health data.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Text('Not recommended', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (!r.found) 'Not in the food database',
                    if (r.hasNews) 'Active food news',
                    if (r.hasGeneralInfo) 'General health info',
                    for (final c in r.clashingConditions) c.label,
                    for (final p in r.clashingPrefs) p.label,
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
                if (r.alternatives.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Try instead', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final alt in r.alternatives.take(3))
                    Text('• $alt', style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        );
      },
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
      'identified' =>
        product.confidence == 0
            ? 'Identified · model did not provide a confidence estimate'
            : 'Model estimate: ${product.confidence}%',
      'ambiguous' => 'Possible match · model estimate ${product.confidence}%',
      'unreadable' => 'Packaging is difficult to read',
      'unavailable' => 'API identification is unavailable',
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
            if (product.catalogProductId != null)
              _ProductField(
                label: 'Catalog ID',
                value: product.catalogProductId,
                confidence: null,
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
    final confidenceValue = confidence;
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
          if (confidenceValue != null && confidenceValue > 0)
            Text('$confidenceValue%'),
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
