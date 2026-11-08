import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../diet/nutrient_insights.dart';
import 'nutrient_score_service.dart';

/// Builds the trees for a 0.0 - 1.0 nutrient [progress].
typedef GardenTreesBuilder = Widget Function(
  BuildContext context,
  double progress,
);

/// Three growing trees on the home page, driven by the user's nutrient
/// score from [NutrientScoreService].
///
/// All three trees share the same nutrient progress (0-100 in the .riv's
/// number input), but each is scaled differently so their relative heights
/// stay fixed: left shortest, centre tallest, right in between. A perfect
/// diet fills every tree to its own maximum - never to the same height.
///
/// Loads [userId]'s [NutrientInsights] once when created; give it a new key
/// to reload. While loading, or if loading fails, the trees sit at zero.
class NutrientGarden extends StatefulWidget {
  const NutrientGarden({
    super.key,
    required this.userId,
    this.loader,
    this.treesBuilder,
  });

  final String userId;

  /// Loads the user's insights; defaults to [NutrientInsights.load].
  final Future<NutrientInsights> Function(String userId)? loader;

  /// Builds the trees for a progress value; defaults to the Rive trees.
  /// Tests override this so no .riv asset is needed.
  final GardenTreesBuilder? treesBuilder;

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
    final trees = widget.treesBuilder ?? _riveTrees;
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _progress),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            builder: (context, progress, _) => trees(context, progress),
          ),
        ),
        if (_empty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Scan a receipt to grow your garden',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static Widget _riveTrees(BuildContext context, double progress) =>
      _RiveTrees(progress: progress);
}

/// Loads the tree .riv once and lays out the three scaled trees.
class _RiveTrees extends StatefulWidget {
  const _RiveTrees({required this.progress});

  final double progress;

  @override
  State<_RiveTrees> createState() => _RiveTreesState();
}

class _RiveTreesState extends State<_RiveTrees> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = await File.asset(
      'assets/rive/tree_demo.riv',
      riveFactory: Factory.rive,
    );
    if (!mounted) {
      file?.dispose();
      return;
    }
    setState(() => _file = file);
  }

  @override
  void dispose() {
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return const SizedBox.expand();
    // Fixed relative sizes: left shortest, centre tallest, right between.
    // 80% cap keeps a perfect diet lush without the trees hitting the
    // artboard's absolute maximum.
    return Row(
      children: [
        Expanded(
          child: _Tree(file: file, progress: widget.progress, scale: 0.55),
        ),
        Expanded(
          child: _Tree(file: file, progress: widget.progress, scale: 1.0),
        ),
        Expanded(
          child: _Tree(file: file, progress: widget.progress, scale: 0.75),
        ),
      ],
    );
  }
}

class _Tree extends StatefulWidget {
  const _Tree({
    required this.file,
    required this.progress,
    required this.scale,
  });

  final File file;

  /// 0.0 - 1.0 nutrient progress.
  final double progress;

  /// Relative height multiplier for this tree.
  final double scale;

  @override
  State<_Tree> createState() => _TreeState();
}

class _TreeState extends State<_Tree> {
  late final RiveWidgetController _controller;
  NumberInput? _growth;

  @override
  void initState() {
    super.initState();
    _controller = RiveWidgetController(
      widget.file,
      stateMachineSelector: const StateMachineNamed('State Machine 1'),
    );
    // The Tree Demo drives growth with a numeric input; find whatever it is
    // called in this file once and keep it. Every other input is released.
    for (final input in _controller.stateMachine.inputs) {
      if (_growth == null && input is NumberInput) {
        _growth = input;
      } else {
        input.dispose();
      }
    }
    _applyProgress();
  }

  @override
  void didUpdateWidget(_Tree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress ||
        oldWidget.scale != widget.scale) {
      _applyProgress();
    }
  }

  void _applyProgress() {
    _growth?.value = (widget.progress.clamp(0, 1) * 80) * widget.scale;
  }

  @override
  void dispose() {
    _growth?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: constraints.maxHeight * widget.scale,
            height: constraints.maxHeight * widget.scale,
            child: RiveWidget(controller: _controller),
          ),
        );
      },
    );
  }
}
