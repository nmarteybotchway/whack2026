import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'diet_summary_service.dart';
import '../openrouter/openrouter_service.dart';

/// The AI diet review entry on the history page: a static teaser card that
/// opens the review in a modal bottom sheet, so the history page underneath
/// never rebuilds while the review loads.
class DietSummaryCard extends StatelessWidget {
  const DietSummaryCard({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => DietSummarySheet(userId: userId),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text('AI diet review', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'See how your last two weeks of eating are doing — '
                      'what is helping you and what to watch.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// The review sheet: shows a cached review straight away, generates a fresh
/// one, and offers a refresh button. Closed by tapping outside or dragging
/// down.
class DietSummarySheet extends StatefulWidget {
  const DietSummarySheet({super.key, required this.userId});

  final String userId;

  @override
  State<DietSummarySheet> createState() => _DietSummarySheetState();
}

class _DietSummarySheetState extends State<DietSummarySheet> {
  final DietSummaryService _service = DietSummaryService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final bool _loading = true;
  bool _regenerating = false;
  DietSummary? _summary;
  String? _error;
  DateTime? _generatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  /// Cache doc at `users/{uid}/dietSummary/current`.
  DocumentReference<Map<String, dynamic>> get _doc => _firestore
      .collection('users')
      .doc(widget.userId)
      .collection('dietSummary')
      .doc('current');

  /// Shows a cached review straight away if one exists, then generates a
  /// fresh one in the background.
  Future<void> _load() async {
    try {
      final snap = await _doc.get();
      final data = snap.data();
      if (data != null && data['summary'] is Map && mounted) {
        setState(() {
          _summary = DietSummary.fromJson(
            Map<String, dynamic>.from(data['summary'] as Map),
          );
          _generatedAt = (data['generatedAt'] as Timestamp?)?.toDate();
        });
      }
    } catch (_) {
      // No cache (missing rules or offline); go straight to generating.
    }
    await _regenerate();
  }

  /// Generates a fresh review, replacing whatever is shown.
  Future<void> _regenerate() async {
    setState(() {
      _regenerating = true;
      _error = null;
    });
    try {
      final summary = await _service.summarize(widget.userId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _generatedAt = DateTime.now();
      });
      // Best-effort cache write.
      unawaited(
        _doc.set({
          'summary': summary!.toJson(),
          'generatedAt': FieldValue.serverTimestamp(),
        }),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  /// Short, friendly text for the error strip.
  String _message(Object e) {
    if (e is NoDietDataException) {
      return 'Scan a receipt first — your review needs some tracked days.';
    }
    if (e is FormatException || e is OpenRouterException) {
      return 'The AI review could not be generated. Tap retry.';
    }
    return 'Could not load the AI review. Check your connection and retry.';
  }

  IconData get _ratingIcon => switch (_summary?.rating) {
    DietSummaryRating.good => Icons.emoji_emotions_outlined,
    DietSummaryRating.concerning => Icons.warning_amber_outlined,
    _ => Icons.balance_outlined,
  };

  Color get _ratingColor => switch (_summary?.rating) {
    DietSummaryRating.good => Colors.green.shade700,
    DietSummaryRating.concerning => Colors.orange.shade800,
    _ => Theme.of(context).colorScheme.primary,
  };

  String get _ratingLabel => switch (_summary?.rating) {
    DietSummaryRating.good => 'Doing well',
    DietSummaryRating.concerning => 'Needs attention',
    _ => 'Mixed picture',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    Widget body;
    if (_summary == null && _loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_summary == null && _error != null) {
      body = Column(
        children: [
          Text(_error!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _regenerate,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    } else if (_summary != null) {
      body = _review(context, _summary!);
    } else {
      body = Text(
        _error ?? 'Nothing to review yet.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('AI diet review', style: theme.textTheme.titleMedium),
              ),
              IconButton(
                onPressed: _regenerating ? null : _regenerate,
                icon: _regenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Regenerate review',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(child: SingleChildScrollView(child: body)),
        ],
      ),
    );
  }

  /// The rendered review for a loaded [summary].
  Widget _review(BuildContext context, DietSummary summary) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          children: [
            Icon(_ratingIcon, size: 20, color: _ratingColor),
            const SizedBox(width: 8),
            Text(
              _ratingLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                color: _ratingColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(summary.headline, style: theme.textTheme.bodyMedium),
        if (summary.goodPoints.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final point in summary.goodPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: .start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(point, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
        if (summary.gaps.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final gap in summary.gaps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: .start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          gap.nutrient,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(gap.detail, style: theme.textTheme.bodySmall),
                        Text(
                          gap.risk,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (gap.foods.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Try: ${gap.foods.join(', ')}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _footer(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// Footer line: how old the review is.
  String _footer() {
    final generatedAt = _generatedAt;
    if (generatedAt == null) return 'Based on your last two weeks of receipts.';
    final age = DateTime.now().difference(generatedAt);
    final when = age.inMinutes < 1
        ? 'just now'
        : age.inHours < 1
        ? '${age.inMinutes} min ago'
        : age.inDays < 1
        ? '${age.inHours} h ago'
        : '${age.inDays} d ago';
    return 'Generated $when from your last two weeks of receipts.';
  }
}
