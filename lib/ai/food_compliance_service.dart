import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hackathon/openrouter.dart' show OpenRouterService;

import 'food_verdict.dart';

/// Checks a food against the user's stored religion and dietary preferences.
///
/// Flow: load preferences from Firestore (`users/{uid}`), build a prompt from
/// them plus the food (and any known ingredients), ask the AI for a
/// structured JSON verdict, and parse it into a [FoodVerdict].
///
/// Today [checkFood] is called with mock food names; once the camera pipeline
/// produces real results, pass the scanned item's name (and ingredients if
/// available) and nothing else changes.
class FoodComplianceService {
  FoodComplianceService({required this.ai, FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  final OpenRouterService ai;
  final FirebaseFirestore firestore;

  /// The user's stored preferences, split by category.
  Future<({List<String> religions, List<String> dietary})> preferencesOf(
    String uid,
  ) async {
    final doc = await firestore.collection('users').doc(uid).get();
    final data = doc.data() ?? const {};
    return (
      religions: List<String>.from(data['religion'] ?? const []),
      dietary: List<String>.from(data['dietary'] ?? const []),
    );
  }

  /// Checks [foodName] against the preferences stored for [uid].
  ///
  /// [ingredients] is optional — when absent, the AI infers the typical
  /// ingredients of the food itself. If the user has no preferences stored,
  /// the food trivially passes without an AI call.
  Future<FoodVerdict> checkFood({
    required String uid,
    required String foodName,
    List<String> ingredients = const [],
  }) async {
    final prefs = await preferencesOf(uid);
    if (prefs.religions.isEmpty && prefs.dietary.isEmpty) {
      return FoodVerdict(food: foodName, violations: const []);
    }

    final ingredientLine = ingredients.isEmpty
        ? 'No ingredient list was provided — use the typical ingredients of '
              'this food, naming the specific ingredient (e.g. "gelatin" not '
              '"sweets").'
        : 'The ingredient list is: ${ingredients.join(', ')}.';

    final prompt = '''
You are a food-compliance checker for a dietary and religious tracking app.

The user's religious preferences are: ${prefs.religions.isEmpty ? 'none' : prefs.religions.join(', ')}.
The user's dietary preferences are: ${prefs.dietary.isEmpty ? 'none' : prefs.dietary.join(', ')}.

Food to check: "$foodName".
$ingredientLine

For each preference, decide whether the food (or any ingredient in it)
conflicts with it. Consider hidden or derived ingredients (e.g. gelatin is
usually pork-derived; wine in sauces; animal rennet in cheese). Only report a
violation when you are reasonably confident of the conflict, and name the
specific ingredient responsible. "pass" with an empty violations list when
nothing conflicts.
''';

    final raw = await ai.generate(
      prompt: prompt,
      responseSchema: foodVerdictSchema,
    );
    return FoodVerdict.fromJson(
      foodName,
      jsonDecode(raw) as Map<String, Object?>,
    );
  }
}

/// The JSON output shape for [FoodComplianceService.checkFood], enforced by
/// OpenRouter's strict structured-output mode.
const foodVerdictSchema = {
  'type': 'object',
  'properties': {
    'verdict': {
      'type': 'string',
      'enum': ['pass', 'fail'],
      'description': 'pass when no preference is violated, otherwise fail.',
    },
    'violations': {
      'type': 'array',
      'description': 'Empty when the verdict is pass.',
      'items': {
        'type': 'object',
        'properties': {
          'category': {
            'type': 'string',
            'enum': ['religion', 'dietary'],
            'description': 'Which kind of preference was violated.',
          },
          'rule': {
            'type': 'string',
            'description':
                'The user preference that was violated, e.g. "Islam" or '
                '"Vegan". Use the exact wording from the user\'s preferences.',
          },
          'ingredient': {
            'type': 'string',
            'description': 'The specific offending ingredient, e.g. "gelatin".',
          },
          'reason': {
            'type': 'string',
            'description':
                'One sentence explaining why this ingredient breaks the rule.',
          },
        },
        'required': ['category', 'rule', 'ingredient', 'reason'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['verdict', 'violations'],
  'additionalProperties': false,
};
