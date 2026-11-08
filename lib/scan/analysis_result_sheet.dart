import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../food/food_matcher.dart';
import '../food/food_recommendation_service.dart';
import '../food_news.dart';
import '../theme.dart';
import 'alert_summary_service.dart';
import 'camera_analysis.dart';
import 'product_identification_service.dart';

/// Shows [result] in a modal bottom sheet over the scan page.
///
/// Pass [newsService] to show a food news alert under the product details.
/// Pass [recommendationService] and [userId] to also show whether the food
/// is safe for this user and what to buy instead.
///
/// Returns the home-page tab index the user picked from the sheet's
/// navigation bar, or null when they dismissed it to scan again.
Future<int?> showAnalysisResult(
  BuildContext context,
  AnalysisResult result, {
  FoodNewsService? newsService,
  FoodRecommendationService? recommendationService,
  String? userId,
}) {
  return showModalBottomSheet<int>(
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
class AnalysisResultSheet extends StatefulWidget {
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
  State<AnalysisResultSheet> createState() => _AnalysisResultSheetState();
}

class _AnalysisResultSheetState extends State<AnalysisResultSheet> {
  bool _skipSwap = false;
  bool _savingOverride = false;

  /// Summarises the stored news/recommendation texts into one sentence.
  final AlertSummaryService _summary = AlertSummaryService();

  String _itemKey(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String? get _foodName {
    final result = widget.result;
    if (result.identification != null) {
      return _newsFoodName(result.identification!);
    }
    return result.item?.name;
  }

  @override
  void initState() {
    super.initState();
    _loadOverride();
  }

  Future<void> _loadOverride() async {
    final uid = widget.userId;
    final foodName = _foodName;
    if (uid == null || foodName == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted) return;
      final ignored = List<String>.from(
        doc.data()?['ignored_swap_items'] ?? const [],
      );
      setState(() => _skipSwap = ignored.contains(_itemKey(foodName)));
    } on FirebaseException {
      // Keep swap suggestions visible if saved overrides cannot be loaded.
    }
  }

  Future<void> _setSkipSwap(bool value) async {
    final uid = widget.userId;
    final foodName = _foodName;
    if (uid == null || foodName == null || _savingOverride) return;
    setState(() {
      _skipSwap = value;
      _savingOverride = true;
    });
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'ignored_swap_items': value
            ? FieldValue.arrayUnion([_itemKey(foodName)])
            : FieldValue.arrayRemove([_itemKey(foodName)]),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _skipSwap = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save swap preference: ${e.message ?? e.code}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingOverride = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final alternative = result.alternative;
    final newsService = widget.newsService;
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
            if (result.identification == null &&
                alternative != null &&
                !_skipSwap) ...[
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
            if (widget.userId != null &&
                _foodName != null &&
                (alternative != null ||
                    widget.recommendationService != null ||
                    _skipSwap))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _skipSwap,
                title: const Text('Don’t suggest a swap for this item again'),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: _savingOverride
                    ? null
                    : (value) => _setSkipSwap(value ?? false),
              ),
            if (newsService != null &&
                result.identification != null &&
                result.error == null) ...[
              const SizedBox(height: 16),
              _FoodNewsAlert(
                service: newsService,
                foodName: _newsFoodName(result.identification!),
              ),
            ],
            if (widget.recommendationService != null &&
                widget.userId != null &&
                result.identification != null &&
                result.error == null) ...[
              const SizedBox(height: 16),
              _RecommendationCard(
                service: widget.recommendationService!,
                userId: widget.userId!,
                foodName: _newsFoodName(result.identification!),
                hideAlternatives: _skipSwap,
                summary: _summary,
              ),
            ],
            const SizedBox(height: 16),
            _SheetNavBar(
              onScanAgain: () => Navigator.of(context).pop(),
              onTab: (tab) => Navigator.of(context).pop(tab),
            ),
          ],
        ),
      ),
    );
  }
}

/// Navigation bar shown at the bottom of the scan-result sheet: a scan-again
/// action in the middle, and Home / History on the left, Assistant / Settings
/// on the right — the same layout as the home page's bar. Tapping a tab pops
/// the sheet with that tab index so the home page can switch to it.
class _SheetNavBar extends StatelessWidget {
  const _SheetNavBar({required this.onScanAgain, required this.onTab});

  final VoidCallback onScanAgain;
  final ValueChanged<int> onTab;

  static const _leftTabs = [
    ('Home', Icons.home_outlined, Icons.home),
    ('History', Icons.history_outlined, Icons.history),
  ];
  static const _rightTabs = [
    ('Assistant', Icons.chat_bubble_outline, Icons.chat_bubble),
    ('Settings', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget item(int index, (String, IconData, IconData) tab) => Expanded(
          child: InkWell(
            onTap: () => onTab(index),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tab.$2, color: colors.primary),
                const SizedBox(height: 4),
                Text(
                  tab.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: colors.primary),
                ),
              ],
            ),
          ),
        );

    // A BottomAppBar needs a Scaffold ancestor, which a modal sheet does not
    // have, so the same layout is built from a plain surface container.
    return SafeArea(
      top: false,
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        color: colors.surface,
        child: Row(
          children: [
            for (var i = 0; i < _leftTabs.length; i++) item(i, _leftTabs[i]),
            Expanded(
              child: Center(
                child: SizedBox.square(
                  dimension: 60,
                  child: FloatingActionButton(
                    heroTag: null,
                    tooltip: 'Scan again',
                    shape: const CircleBorder(),
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    elevation: 2,
                    onPressed: onScanAgain,
                    child: const Icon(Icons.qr_code_scanner, size: 30),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < _rightTabs.length; i++)
              item(i + _leftTabs.length, _rightTabs[i]),
          ],
        ),
      ),
    );
  }
}

/// The name the food news and recommendation services look up for a scanned
/// product: the fuzzily matched [KnownFood] when there is one, since stored
/// foods have generic names, else the product name as read.
String _newsFoodName(ProductIdentification product) {  final productName = product.productName;
  final name = (productName != null && productName.isNotEmpty)
      ? productName
      : product.displayName;
  return (matchKnownFood(name) ?? matchKnownFood(product.displayName))
          ?.food
          .name ??
      name;
}

/// The first sentence or two of a stored explanation, so scan results stay
/// short: at most two sentences, capped at ~220 characters, with an ellipsis
/// when text was cut off.
String _condense(String text) {
  final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= 220) return trimmed;
  final matches = RegExp(r'.*?[.!?]').allMatches(trimmed).take(2).toList();
  final condensed = matches.isEmpty
      ? trimmed
      : trimmed.substring(0, matches.last.end);
  if (condensed.length > 220) {
    final cut = trimmed.substring(0, 217).trimRight();
    return RegExp(r'.*?[.!?]').firstMatch(cut)?.end != null
        ? '${trimmed.substring(0, RegExp(r'.*?[.!?]').firstMatch(cut)!.end)}…'
        : '$cut…';
  }
  return condensed.length < trimmed.length ? '$condensed…' : condensed;
}

/// Food news alert for a scanned product: a green no-news card when the
/// database has nothing, or an alert card with local news (always listed
/// before general info) when it does.
class _FoodNewsAlert extends StatefulWidget {
  const _FoodNewsAlert({required this.service, required this.foodName});

  final FoodNewsService service;
  final String foodName;

  @override
  State<_FoodNewsAlert> createState() => _FoodNewsAlertState();
}

/// Fetches once per [_FoodNewsAlert.foodName], so parent rebuilds (e.g.
/// toggling the swap checkbox) don't refetch.
class _FoodNewsAlertState extends State<_FoodNewsAlert> {
  late Future<FoodNewsResult> _news;

  @override
  void initState() {
    super.initState();
    _news = widget.service.getNews(widget.foodName);
  }

  @override
  void didUpdateWidget(_FoodNewsAlert oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.foodName != widget.foodName) {
      _news = widget.service.getNews(widget.foodName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FoodNewsResult>(
      future: _news,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('Food news failed for ${widget.foodName}: ${snap.error}');
          return const _LoadFailedCard('Couldn’t load food news.');
        }
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
                  Text(
                    'Local news: ${news.localNews}',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (news.generalInfo != FoodNewsService.noNewsMessage) ...[
                  if (news.localNews != FoodNewsService.noNewsMessage)
                    const SizedBox(height: 4),
                  Text(
                    'General info: ${news.generalInfo}',
                    style: theme.textTheme.bodyMedium,
                  ),
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
/// when nothing applies, a neutral card when the food isn't in the database,
/// or a red card with the reasons and what to buy instead.
class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({
    required this.service,
    required this.userId,
    required this.foodName,
    this.hideAlternatives = false,
    required this.summary,
  });

  final FoodRecommendationService service;
  final String userId;
  final String foodName;
  final bool hideAlternatives;
  final AlertSummaryService summary;

  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

/// Fetches once per user and food, so toggling [hideAlternatives] (the swap
/// checkbox) just re-renders the loaded verdict.
class _RecommendationCardState extends State<_RecommendationCard> {
  late Future<FoodRecommendation> _recommendation;

  Future<FoodRecommendation> _load() => widget.service.recommendFor(
    uid: widget.userId,
    foodName: widget.foodName,
  );

  @override
  void initState() {
    super.initState();
    _recommendation = _load();
  }

  @override
  void didUpdateWidget(_RecommendationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.userId != widget.userId ||
        oldWidget.foodName != widget.foodName) {
      _recommendation = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FoodRecommendation>(
      future: _recommendation,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint(
            'Recommendation failed for ${widget.foodName}: ${snap.error}',
          );
          return const _LoadFailedCard('Couldn’t load a recommendation.');
        }
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
                      'Safe to buy: no alerts, and it matches none of your '
                      'preferences or health data.'
                      '${_boostText(r)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        // Not in the food collection: no data to judge by, so stay neutral.
        if (!r.found) {
          return Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No data for this product yet, so we can’t give a '
                      'personal recommendation.',
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
                // One AI summary sentence built from all the reasons; the
                // truncated reason list shows while it loads or if the
                // summariser is unavailable.
                // Personal clashes first (conditions/preferences), then the
                // AI one-sentence summary of the full explanation below.
                if (_reasons(r) case final reasons when reasons.isNotEmpty)
                  Text(
                    reasons.join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 4),
                FutureBuilder<String>(
                  future: _summaryLine(r),
                  builder: (context, summarySnap) => Text(
                    summarySnap.hasData && summarySnap.data!.isNotEmpty
                        ? summarySnap.data!
                        : _condense(r.generalInfo ?? ''),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (r.boostsNutrients.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_boostText(r).trim(), style: theme.textTheme.bodySmall),
                ],
                if (!widget.hideAlternatives && r.alternatives.isNotEmpty) ...[
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

  /// The AI one-sentence summary of why this food is not recommended, built
  /// from every reason the recommender found. Cached in state so toggling
  /// the swap checkbox doesn't re-call the summariser.
  Future<String> _summaryLine(FoodRecommendation r) {
    if (_cachedSummary != null) return _cachedSummary!;
    final full = [
      if (r.hasGeneralInfo) r.generalInfo!,
      if (r.clashingConditions.isNotEmpty || r.clashingPrefs.isNotEmpty)
        _personalizedRationale(r),
      if (r.excessNutrients.isNotEmpty)
        'This food is high in '
        '${r.excessNutrients.map((n) => n.label.toLowerCase()).join(' and ')}, '
        'which the recent diet is already over the daily limit for.',
    ].join(' ');
    _cachedSummary = widget.summary.summarize(
      full.isEmpty ? 'This food is not recommended.' : full,
    );
    return _cachedSummary!;
  }

  Future<String>? _cachedSummary;

  /// Short reason chips for why [r]'s food is not recommended.
  List<String> _reasons(FoodRecommendation r) => [
    if (r.hasNews) 'Active food news',
    for (final c in r.clashingConditions) c.label,
    for (final p in r.clashingPrefs) p.label,
    for (final n in r.excessNutrients) 'High in ${n.label}',
  ];

  String _personalizedRationale(FoodRecommendation r) {
    final conditions = r.clashingConditions.map((c) => c.label).toList();
    final prefs = r.clashingPrefs.map((p) => p.label.toLowerCase()).toList();
    final personal = [
      ...conditions.map(
        (condition) => condition == 'Pregnancy'
            ? 'you are pregnant'
            : 'you have ${_conditionPhrase(condition)}',
      ),
      ...prefs.map((preference) => 'you follow a $preference diet'),
    ];
    return 'Not recommended because ${personal.join(' and ')}.';
  }

  String _conditionPhrase(String label) => switch (label) {
    'Diabetes' => 'diabetes',
    'High blood pressure' => 'high blood pressure',
    'High cholesterol' => 'high cholesterol',
    'Heart disease' => 'heart disease',
    'Kidney disease' => 'kidney disease',
    'Coeliac disease' => 'coeliac disease',
    'Lactose intolerance' => 'lactose intolerance',
    'Irritable bowel syndrome' => 'irritable bowel syndrome',
    'Acid reflux' => 'acid reflux',
    'Peanut allergy' => 'a peanut allergy',
    'Tree nut allergy' => 'a tree nut allergy',
    'Milk allergy' => 'a milk allergy',
    'Egg allergy' => 'an egg allergy',
    'Fish allergy' => 'a fish allergy',
    'Shellfish allergy' => 'a shellfish allergy',
    'Soy allergy' => 'a soy allergy',
    'Wheat allergy' => 'a wheat allergy',
    'Sesame allergy' => 'a sesame allergy',
    'Pregnancy' => 'pregnant',
    _ => label.toLowerCase(),
  };
}

/// Neutral card shown in place of a section whose data failed to load.
class _LoadFailedCard extends StatelessWidget {
  const _LoadFailedCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// Notes the nutrients [r]'s food would top up, or an empty string.
String _boostText(FoodRecommendation r) => r.boostsNutrients.isEmpty
    ? ''
    : ' Good source of '
          '${r.boostsNutrients.map((n) => n.label).join(', ')}, which your '
          'recent diet is low in.';

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
    final status = AppTheme.statusColors;
    final color = score >= 60
        ? status.good
        : score >= 40
        ? status.warn
        : status.bad;
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
