/// Whether a [Preference] is a religion or a dietary requirement, which
/// decides the settings page list it appears in.
enum PreferenceKind { none, religion, dietary }

/// Religious and dietary preferences a food can clash with.
///
/// [id] is the string stored on foods in Firestore; never change an existing
/// one. The settings page builds its options from [religions] and [dietary],
/// saving each choice's [label] in `users/{uid}`, so [fromLabel] maps a
/// user's choices back onto these. Adding a value here adds it to both the
/// settings page and tool/fill_food.dart's prompts. Beliefs with no food
/// rules are in [otherBeliefs] instead, so foods are never checked against
/// them.
enum Preference {
  /// No preference, e.g. the second key in `Food.alternatives` for someone
  /// without any of a food's clashing preferences.
  none('none', 'None', PreferenceKind.none),
  islam('islam', 'Islam', PreferenceKind.religion),
  judaism('judaism', 'Judaism', PreferenceKind.religion),
  hinduism('hinduism', 'Hinduism', PreferenceKind.religion),
  buddhism('buddhism', 'Buddhism', PreferenceKind.religion),
  sikhism('sikhism', 'Sikhism', PreferenceKind.religion),
  glutenFree('gluten_free', 'Gluten free', PreferenceKind.dietary),
  vegetarian('vegetarian', 'Vegetarian', PreferenceKind.dietary),
  vegan('vegan', 'Vegan', PreferenceKind.dietary),
  pescatarian('pescatarian', 'Pescatarian', PreferenceKind.dietary),
  halal('halal', 'Halal', PreferenceKind.dietary),
  kosher('kosher', 'Kosher', PreferenceKind.dietary),
  dairyFree('dairy_free', 'Dairy free', PreferenceKind.dietary),
  nutAllergy('nut_allergy', 'Nut allergy', PreferenceKind.dietary);

  const Preference(this.id, this.label, this.kind);

  final String id;
  final String label;
  final PreferenceKind kind;

  /// Beliefs offered on the settings page that have no food rules, so they
  /// are not preferences a food can clash with.
  static const List<String> otherBeliefs = [
    'Christianity',
    'Atheist',
    'Agnostic',
  ];

  /// Religions with food rules, as listed on the settings page.
  static final List<Preference> religions = [
    for (final p in values)
      if (p.kind == PreferenceKind.religion) p,
  ];

  /// Dietary requirements, as listed on the settings page.
  static final List<Preference> dietary = [
    for (final p in values)
      if (p.kind == PreferenceKind.dietary) p,
  ];

  static final Map<String, Preference> _byId = {
    for (final p in values) p.id: p,
  };

  /// Every real preference, i.e. all values except [none].
  static final List<Preference> preferences = [
    for (final p in values)
      if (p != none) p,
  ];

  static final Map<String, Preference> _byLabel = {
    for (final p in preferences) p.label: p,
  };

  /// The preference stored as [id], or null if it is unknown.
  static Preference? fromId(String id) => _byId[id];

  /// The preference for a settings-page option, or null for free-text
  /// "Other" entries and beliefs without food rules.
  static Preference? fromLabel(String label) => _byLabel[label];
}
