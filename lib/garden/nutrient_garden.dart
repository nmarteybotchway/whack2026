import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

/// Three growing trees on the home page, driven by the user's nutrient
/// score from [NutritionService] data.
///
/// All three trees share the same nutrient progress (0-100 in the .riv's
/// number input), but each is scaled differently so their relative heights
/// stay fixed: left shortest, centre tallest, right in between. A perfect
/// diet fills every tree to its own maximum - never to the same height.
class NutrientGarden extends StatefulWidget {
  const NutrientGarden({super.key, required this.progress});

  /// 0.0 - 1.0; how much of the tracked vitamins/nutrients the user hit.
  final double progress;

  @override
  State<NutrientGarden> createState() => _NutrientGardenState();
}

class _NutrientGardenState extends State<NutrientGarden> {
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
    if (!mounted) return;
    setState(() => _file = file);
  }

  @override
  void dispose() {
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_file == null) {
      return const SizedBox(height: 180);
    }
    // Fixed relative sizes: left shortest, centre tallest, right between.
    // 80% cap keeps a perfect diet lush without the trees hitting the
    // artboard's absolute maximum.
    return SizedBox(
      height: 180,
      child: Row(
        children: [
          Expanded(
            child: _Tree(
              file: _file!,
              progress: widget.progress,
              scale: 0.55,
            ),
          ),
          Expanded(
            child: _Tree(
              file: _file!,
              progress: widget.progress,
              scale: 1.0,
            ),
          ),
          Expanded(
            child: _Tree(
              file: _file!,
              progress: widget.progress,
              scale: 0.75,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tree extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final controller = RiveWidgetController(
          file,
          stateMachineSelector: const StateMachineNamed('State Machine 1'),
        );
        // The Tree Demo drives growth with a numeric input; find whatever
        // it is called in this file and set 0-100 from our progress.
        for (final input in controller.stateMachine.inputs) {
          if (input is NumberInput) {
            input.value = (progress.clamp(0, 1) * 80) * scale;
            break;
          }
        }
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: constraints.maxHeight * scale,
            height: constraints.maxHeight * scale,
            child: RiveWidget(controller: controller),
          ),
        );
      },
    );
  }
}
