import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hackathon/openrouter.dart' show OpenRouterService;
import 'package:hackathon/secrets.dart' show openRouterApiKey;

import 'food_compliance_service.dart';
import 'food_verdict_sheet.dart';
import 'mock_foods.dart';

/// Demo section for running [FoodComplianceService] against [mockFoods].
///
/// Stands in for the real scan flow: when the camera pipeline produces food
/// names, call `FoodComplianceService.checkFood(uid:, foodName:, ingredients:)`
/// with that data and show the result with [showFoodVerdict] — the same call
/// this demo makes.
class FoodCheckDemo extends StatefulWidget {
  const FoodCheckDemo({super.key, required this.user});

  final User user;

  @override
  State<FoodCheckDemo> createState() => _FoodCheckDemoState();
}

class _FoodCheckDemoState extends State<FoodCheckDemo> {
  static final _service = FoodComplianceService(ai: OpenRouterService());

  String? _checking;

  Future<void> _run(MockFood food) async {
    if (openRouterApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'No OpenRouter key — copy lib/secrets.example.dart to '
          'lib/secrets.dart and paste your key from openrouter.ai/keys',
        ),
      ));
      return;
    }
    setState(() => _checking = food.name);
    try {
      final verdict = await _service.checkFood(
        uid: widget.user.uid,
        foodName: food.name,
        ingredients: food.ingredients,
      );
      if (!mounted) return;
      await showFoodVerdict(context, verdict);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Food check failed: $e')));
    } finally {
      if (mounted) setState(() => _checking = null);
    }
  }

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
                Icon(Icons.psychology, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('AI food check (demo)', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Tap a mock scanned food to check it against your preferences.'),
            const SizedBox(height: 8),
            for (final food in mockFoods)
              ListTile(
                contentPadding: .zero,
                dense: true,
                leading: const Icon(Icons.fastfood),
                title: Text(food.name),
                trailing: _checking == food.name
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _checking == null ? () => _run(food) : null,
              ),
          ],
        ),
      ),
    );
  }
}
