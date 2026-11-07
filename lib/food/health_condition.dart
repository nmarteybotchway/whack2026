/// Health conditions a food can clash with.
///
/// [id] is the string stored in Firestore; never change an existing one, or
/// stored foods will stop matching it. [label] is for display.
enum HealthCondition {
  hypertension('hypertension', 'High blood pressure'),
  diabetes('diabetes', 'Diabetes'),
  highCholesterol('high_cholesterol', 'High cholesterol'),
  heartDisease('heart_disease', 'Heart disease'),
  kidneyDisease('kidney_disease', 'Kidney disease'),
  gout('gout', 'Gout'),
  coeliacDisease('coeliac_disease', 'Coeliac disease'),
  lactoseIntolerance('lactose_intolerance', 'Lactose intolerance'),
  ibs('ibs', 'Irritable bowel syndrome'),
  acidReflux('acid_reflux', 'Acid reflux'),
  peanutAllergy('peanut_allergy', 'Peanut allergy'),
  treeNutAllergy('tree_nut_allergy', 'Tree nut allergy'),
  milkAllergy('milk_allergy', 'Milk allergy'),
  eggAllergy('egg_allergy', 'Egg allergy'),
  fishAllergy('fish_allergy', 'Fish allergy'),
  shellfishAllergy('shellfish_allergy', 'Shellfish allergy'),
  soyAllergy('soy_allergy', 'Soy allergy'),
  wheatAllergy('wheat_allergy', 'Wheat allergy'),
  sesameAllergy('sesame_allergy', 'Sesame allergy'),
  pregnancy('pregnancy', 'Pregnancy');

  const HealthCondition(this.id, this.label);

  final String id;
  final String label;

  static final Map<String, HealthCondition> _byId = {
    for (final c in values) c.id: c,
  };

  /// The condition stored as [id], or null if it is unknown.
  static HealthCondition? fromId(String id) => _byId[id];
}
