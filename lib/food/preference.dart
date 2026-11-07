/// Religious and dietary preferences a food can clash with.
///
/// [id] is the string stored on foods in Firestore; never change an existing
/// one. [label] matches the option saved in `users/{uid}` by the settings
/// page, so [fromLabel] maps a user's choices onto these. Beliefs with no
/// food rules (Christianity, Atheist, Agnostic) are deliberately absent.
enum Preference {
  islam('islam', 'Islam'),
  judaism('judaism', 'Judaism'),
  hinduism('hinduism', 'Hinduism'),
  buddhism('buddhism', 'Buddhism'),
  sikhism('sikhism', 'Sikhism'),
  halal('halal', 'Halal'),
  kosher('kosher', 'Kosher'),
  vegetarian('vegetarian', 'Vegetarian'),
  vegan('vegan', 'Vegan'),
  pescatarian('pescatarian', 'Pescatarian'),
  glutenFree('gluten_free', 'Gluten free'),
  dairyFree('dairy_free', 'Dairy free'),
  nutAllergy('nut_allergy', 'Nut allergy');

  const Preference(this.id, this.label);

  final String id;
  final String label;

  static final Map<String, Preference> _byId = {
    for (final p in values) p.id: p,
  };

  static final Map<String, Preference> _byLabel = {
    for (final p in values) p.label: p,
  };

  /// The preference stored as [id], or null if it is unknown.
  static Preference? fromId(String id) => _byId[id];

  /// The preference for a settings-page option, or null for free-text
  /// "Other" entries and beliefs without food rules.
  static Preference? fromLabel(String label) => _byLabel[label];
}
