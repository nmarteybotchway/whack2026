/// The result of a food-compliance check against the user's stored
/// religion and dietary preferences.
///
/// The JSON shape Gemini must return:
///
/// ```json
/// {
///   "verdict": "pass",
///   "violations": []
/// }
/// ```
///
/// or, when the food clashes with a preference:
///
/// ```json
/// {
///   "verdict": "fail",
///   "violations": [
///     {
///       "category": "religion",
///       "rule": "Islam",
///       "ingredient": "gelatin",
///       "reason": "Gelatin is typically pork-derived, which is haram."
///     }
///   ]
/// }
/// ```
library;

/// One preference the food conflicts with.
class FoodViolation {
  const FoodViolation({
    required this.category,
    required this.rule,
    required this.ingredient,
    required this.reason,
  });

  /// `'religion'` or `'dietary'`.
  final String category;

  /// The stored preference that was broken, e.g. `'Islam'`, `'Vegan'`.
  final String rule;

  /// The offending ingredient as found in the food, e.g. `'gelatin'`.
  final String ingredient;

  /// Why this ingredient breaks [rule].
  final String reason;

  factory FoodViolation.fromJson(Map<String, Object?> json) {
    return FoodViolation(
      category: json['category']! as String,
      rule: json['rule']! as String,
      ingredient: json['ingredient']! as String,
      reason: json['reason']! as String,
    );
  }

  Map<String, Object?> toJson() => {
    'category': category,
    'rule': rule,
    'ingredient': ingredient,
    'reason': reason,
  };

  @override
  String toString() =>
      'FoodViolation($category/$rule: $ingredient — $reason)';
}

/// Whether a food passes the user's preferences, and why not if it doesn't.
class FoodVerdict {
  const FoodVerdict({required this.food, required this.violations});

  final String food;

  /// Empty list means pass; any entry means fail.
  final List<FoodViolation> violations;

  bool get pass => violations.isEmpty;

  factory FoodVerdict.fromJson(String food, Map<String, Object?> json) {
    final violations = (json['violations'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(FoodViolation.fromJson)
        .toList();
    return FoodVerdict(food: food, violations: violations);
  }

  Map<String, Object?> toJson() => {
    'verdict': pass ? 'pass' : 'fail',
    'violations': [for (final v in violations) v.toJson()],
  };
}
