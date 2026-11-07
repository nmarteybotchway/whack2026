import 'package:flutter/material.dart';

import '../theme.dart';
import 'diet_window_service.dart';
import 'nutrient_insights.dart';
import 'nutrition_service.dart';
import 'receipt_store.dart';

/// Longest range the tracker offers: receipt days are only kept for the
/// [DietWindowService] window.
final _maxDays = DietWindowService.window.inDays;

/// Receipt days from the sliding window plus foods logged through the
/// assistant, combined per day.
Future<NutrientInsights> _loadInsights(String userId, int days) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day - (days - 1));
  final results = await Future.wait([
    DietWindowService(userId).recentDays(),
    ReceiptStore(userId).loggedIntakeSince(start),
  ]);
  final receiptDays = results[0] as List<DietDay>;
  final intake = results[1] as Map<DateTime, Map<String, double>>;
  for (final day in receiptDays) {
    if (day.date.isBefore(start)) continue;
    final into = intake.putIfAbsent(day.date, () => {});
    day.nutrition.forEach((k, v) => into[k] = (into[k] ?? 0) + v);
  }
  return NutrientInsights.fromDaily(intake, today: now, days: days);
}

/// Historical vitamins and minerals tracker: averages what the user's
/// receipts and logged meals provide per day and highlights what they are
/// consistently short of.
class NutrientTrackerPage extends StatefulWidget {
  const NutrientTrackerPage({super.key, required this.userId});

  final String userId;

  @override
  State<NutrientTrackerPage> createState() => _NutrientTrackerPageState();
}

class _NutrientTrackerPageState extends State<NutrientTrackerPage> {
  int _days = _maxDays;
  late Future<NutrientInsights> _insights = _loadInsights(widget.userId, _days);

  void _setDays(int days) {
    setState(() {
      _days = days;
      _insights = _loadInsights(widget.userId, days);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nutrient tracker')),
      body: RefreshIndicator(
        onRefresh: () async {
          _setDays(_days);
          await _insights;
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Average daily vitamins and minerals from your receipts and '
              'logged meals, compared with adult reference intakes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: [
                const ButtonSegment(value: 3, label: Text('3 days')),
                const ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: _maxDays, label: Text('$_maxDays days')),
              ],
              selected: {_days},
              onSelectionChanged: (selection) => _setDays(selection.first),
            ),
            const SizedBox(height: 16),
            FutureBuilder<NutrientInsights>(
              future: _insights,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'Cannot load your nutrient history. Check your connection '
                    'and try again.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final insights = snapshot.data!;
                if (insights.isEmpty) {
                  return const Text(
                    'No foods recorded in this period. Scan a receipt or log a '
                    'meal with the assistant to start tracking.',
                  );
                }
                return Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    _GapsSummary(insights: insights),
                    const SizedBox(height: 16),
                    for (final c in insights.coverage)
                      _NutrientRow(coverage: c),
                    const SizedBox(height: 12),
                    Text(
                      'Estimates assume one ~100 g serving per food item and '
                      'are averaged over the days since you started tracking. '
                      'Not medical advice.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GapsSummary extends StatelessWidget {
  const _GapsSummary({required this.insights});

  final NutrientInsights insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gaps = insights.gaps;
    final sodium = insights.coverage.firstWhere((c) => c.key == 'NA');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(
              gaps.isEmpty
                  ? 'You\'re covering your vitamins and minerals'
                  : 'You may be lacking',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${insights.trackedDays} of ${insights.days} days tracked',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final gap in gaps.take(4)) ...[
              const SizedBox(height: 12),
              Text(
                '${gap.target.label} · ${(gap.ratio * 100).round()}% of target',
                style: theme.textTheme.labelLarge,
              ),
              Text(
                'Try: ${gap.target.sources.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (sodium.status == NutrientStatus.high) ...[
              const SizedBox(height: 12),
              Text(
                'Sodium is ${(sodium.ratio * 100).round()}% of the daily limit '
                '— consider cutting back on salty foods.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.statusColors.bad,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _statusColor(NutrientStatus status) => switch (status) {
  NutrientStatus.lacking => AppTheme.statusColors.bad,
  NutrientStatus.low => AppTheme.statusColors.warn,
  NutrientStatus.good => AppTheme.statusColors.good,
  NutrientStatus.high => AppTheme.statusColors.bad,
};

String _statusLabel(NutrientStatus status) => switch (status) {
  NutrientStatus.lacking => 'Lacking',
  NutrientStatus.low => 'Low',
  NutrientStatus.good => 'Good',
  NutrientStatus.high => 'Too high',
};

String _amount(double value, String key) {
  final unit = nutrientUnits[key] == 'UG' ? 'µg' : 'mg';
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(value >= 10 ? 1 : 2);
  return '$text $unit';
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({required this.coverage});

  final NutrientCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = coverage.target;
    final color = _statusColor(coverage.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(child: Text(target.label)),
            Text(
              _statusLabel(coverage.status),
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: .start,
          children: [
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: coverage.ratio.clamp(0, 1),
                minHeight: 6,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_amount(coverage.average, coverage.key)}/day of '
              '${_amount(target.daily, coverage.key)} '
              '${target.isLimit ? 'limit' : 'target'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: .start,
        children: [
          Text('Daily intake', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          _DailyBars(coverage: coverage, color: color),
          if (target.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Good sources', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final source in target.sources)
                  Chip(label: Text(source), visualDensity: .compact),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bar per day of the window, scaled to the daily target which is drawn as a
/// dashed-looking reference line.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.coverage, required this.color});

  final NutrientCoverage coverage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daily = coverage.daily;
    final targetValue = coverage.target.daily;
    final peak = daily.fold<double>(targetValue, (a, b) => b > a ? b : a);
    const height = 72.0;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: height * targetValue / peak,
                child: Container(height: 1, color: theme.colorScheme.outline),
              ),
              Row(
                crossAxisAlignment: .end,
                children: [
                  for (final value in daily)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: daily.length > 40 ? 0.5 : 1.5,
                        ),
                        child: Container(
                          height: value <= 0
                              ? 2
                              : (height * value / peak).clamp(2, height),
                          decoration: BoxDecoration(
                            color: value <= 0
                                ? theme.colorScheme.surfaceContainerHighest
                                : color.withValues(alpha: 0.8),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('${daily.length} days ago', style: theme.textTheme.labelSmall),
            const Spacer(),
            Text('Today', style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

/// Compact home-screen card listing the nutrients the user is most short of
/// over the last two weeks; opens [NutrientTrackerPage].
class NutrientGapsCard extends StatefulWidget {
  const NutrientGapsCard({super.key, required this.userId});

  final String userId;

  @override
  State<NutrientGapsCard> createState() => _NutrientGapsCardState();
}

class _NutrientGapsCardState extends State<NutrientGapsCard> {
  late Future<NutrientInsights> _insights = _loadInsights(
    widget.userId,
    _maxDays,
  );

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NutrientTrackerPage(userId: widget.userId),
      ),
    );
    if (mounted)
      setState(() => _insights = _loadInsights(widget.userId, _maxDays));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nutrient tracker',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<NutrientInsights>(
                future: _insights,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Could not load nutrient history.');
                  }
                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator();
                  }
                  final insights = snapshot.data!;
                  if (insights.isEmpty) {
                    return const Text(
                      'Scan receipts or log meals to see what you might be '
                      'lacking.',
                    );
                  }
                  final gaps = insights.gaps;
                  if (gaps.isEmpty) {
                    return const Text(
                      'No gaps in the last two weeks — nice work.',
                    );
                  }
                  return Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        'Last two weeks, you may be lacking:',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final gap in gaps.take(5))
                            Chip(
                              visualDensity: .compact,
                              avatar: CircleAvatar(
                                backgroundColor: _statusColor(gap.status),
                                radius: 5,
                              ),
                              label: Text(
                                '${gap.target.label} '
                                '${(gap.ratio * 100).round()}%',
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
