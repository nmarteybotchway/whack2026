import 'package:flutter/material.dart';

import '../diet/nutrient_insights.dart';
import 'nutrient_score_service.dart';
import 'sunrise_valley.dart';

/// Builds the scene for a 0.0 - 1.0 nutrient [progress].
typedef GardenTreesBuilder = Widget Function(
  BuildContext context,
  double progress,
);

/// Called when the valley's sun crosses the horizon: true at sunrise, false
/// at sunset.
typedef GardenDayNightChanged = void Function(bool isDay);

/// The home tab's backdrop: a sunrise river valley whose lushness follows
/// the user's nutrient score from [NutrientScoreService]. It fills whatever
/// space it is given (the whole home tab, behind the status and bottom bars).
///
/// Loads [userId]'s [NutrientInsights] once when created; give it a new key
/// to reload. While loading, or if loading fails, the valley sits at zero.
class NutrientGarden extends StatefulWidget {
  const NutrientGarden({
    super.key,
    required this.userId,
    this.loader,
    this.treesBuilder,
    this.onDayNightChanged,
  });

  final String userId;

  /// Loads the user's insights; defaults to [NutrientInsights.load].
  final Future<NutrientInsights> Function(String userId)? loader;

  /// Builds the scene for a progress value; defaults to [SunriseValley].
  /// Tests override this to check the progress without painting.
  final GardenTreesBuilder? treesBuilder;

  /// Called when the sun crosses the horizon; see [SunriseValley.onDayNightChanged].
  final GardenDayNightChanged? onDayNightChanged;

  @override
  State<NutrientGarden> createState() => _NutrientGardenState();
}

class _NutrientGardenState extends State<NutrientGarden> {
  /// 0.0 - 1.0; how much of the tracked vitamins/nutrients the user hit.
  double _progress = 0;

  /// True once insights have loaded and the user has no food recorded.
  bool _empty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loader = widget.loader ?? NutrientInsights.load;
    try {
      final insights = await loader(widget.userId);
      if (!mounted) return;
      setState(() {
        _progress = NutrientScoreService.scoreFromInsights(insights);
        _empty = insights.isEmpty;
      });
    } catch (e, st) {
      debugPrint('NutrientGarden: failed to load nutrient score: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scene = widget.treesBuilder;
    return Stack(
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: _progress),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOut,
          builder: (context, progress, _) =>
              scene?.call(context, progress) ??
              SunriseValley(
                progress: _minLushness + (1 - _minLushness) * progress,
                onDayNightChanged: widget.onDayNightChanged,
              ),
        ),
        if (_empty)
          // Above the bottom bar: the Scaffold extends the body behind it and
          // reports its height as bottom padding.
          SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Scan a receipt to grow your garden',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(blurRadius: 8, color: Colors.black45),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The valley's lushness at a score of zero. The home screen always looks
  /// at least this full; the score grows it the rest of the way.
  static const _minLushness = 0.7;
}

