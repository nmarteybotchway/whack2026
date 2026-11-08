/// Vitamins and minerals tracked on foods and in the user's diet.
///
/// [id] is the shorthand stored in Firestore, both as a key of a food's
/// `nutrients` map and of a diet day's `nutrition` map; never change an
/// existing one. Element shorthands follow the periodic table (CA calcium,
/// NA sodium, ...); vitamins are prefixed VIT so vitamin K never collides
/// with potassium K. Every amount is in [unit].
///
/// Reference amounts are the UK label Nutrient Reference Values per day for
/// adults ([dailyValue]), with vitamin D at the UK's 10 µg advice. Sodium is
/// something to limit rather than reach, so it has a [dailyLimit] (6 g of
/// salt) instead.
enum Nutrient {
  calcium('CA', 'Calcium', 'MG', dailyValue: 800),
  sodium('NA', 'Sodium', 'MG', dailyLimit: 2400),
  iron('FE', 'Iron', 'MG', dailyValue: 14),
  potassium('K', 'Potassium', 'MG', dailyValue: 2000),
  magnesium('MG', 'Magnesium', 'MG', dailyValue: 375),
  zinc('ZN', 'Zinc', 'MG', dailyValue: 10),
  vitaminA('VITA', 'Vitamin A', 'UG', dailyValue: 800),
  vitaminB6('VITB6', 'Vitamin B6', 'MG', dailyValue: 1.4),
  vitaminB12('VITB12', 'Vitamin B12', 'UG', dailyValue: 2.5),
  vitaminC('VITC', 'Vitamin C', 'MG', dailyValue: 80),
  vitaminD('VITD', 'Vitamin D', 'UG', dailyValue: 10),
  vitaminE('VITE', 'Vitamin E', 'MG', dailyValue: 12),
  vitaminK('VITK', 'Vitamin K', 'UG', dailyValue: 75),
  folate('FOL', 'Folate', 'UG', dailyValue: 200);

  const Nutrient(
    this.id,
    this.label,
    this.unit, {
    this.dailyValue,
    this.dailyLimit,
  });

  final String id;
  final String label;

  /// `MG` or `UG`.
  final String unit;

  /// Amount an adult should get per day; null for [dailyLimit] nutrients.
  final double? dailyValue;

  /// Amount an adult should stay under per day; null for [dailyValue]
  /// nutrients.
  final double? dailyLimit;

  /// Per-100 g amount making a food a "source of" this nutrient: 15% of
  /// [dailyValue], the UK labelling rule. Null for [dailyLimit] nutrients.
  double? get sourceThreshold => dailyValue == null ? null : dailyValue! * 0.15;

  /// Per-100 g amount making a food "high" in this nutrient: 25% of
  /// [dailyLimit], which for sodium is the UK red traffic light (1.5 g salt).
  /// Null for [dailyValue] nutrients.
  double? get highThreshold => dailyLimit == null ? null : dailyLimit! * 0.25;

  static final Map<String, Nutrient> _byId = {for (final n in values) n.id: n};

  /// The nutrient stored as [id], or null if it is unknown.
  static Nutrient? fromId(String id) => _byId[id];

  /// Parses a Firestore `{id: amount}` map, skipping unknown IDs and
  /// non-numeric or non-positive amounts.
  static Map<Nutrient, double> parseAmounts(Object? raw) => {
    if (raw is Map)
      for (final MapEntry(:key, :value) in raw.entries)
        if ((fromId('$key'), value) case (final n?, num v) when v > 0)
          n: v.toDouble(),
  };
}
