import 'package:cloud_firestore/cloud_firestore.dart';

import '../diet/nutrition_service.dart';

/// Scores how much of the daily recommended vitamins and minerals the user
/// has hit, as a single 0..1 progress value for the garden.
///
/// Daily targets (per the NHS reference nutrient intakes for adults), keyed
/// by our [nutrientUnits] shorthand, in the stored unit for each nutrient.
const _dailyTargets = <String, double>{
  'CA': 700, // Calcium mg
  'NA': 1600, // Sodium mg (target ceiling ~2.4g; we use a mid estimate)
  'FE': 8.7, // Iron mg
  'K': 3500, // Potassium mg
  'MG': 300, // Magnesium mg
  'ZN': 9.5, // Zinc mg
  'VITA': 700, // Vitamin A µg (RAE)
  'VITB6': 1.4, // Vitamin B6 mg
  'VITB12': 1.5, // Vitamin B12 µg
  'VITC': 40, // Vitamin C mg
  'VITD': 10, // Vitamin D µg
  'VITE': 4, // Vitamin E mg
  'VITK': 1, // Vitamin K µg (~1µg/kg; 70kg adult)
  'FOL': 200, // Folate µg
};

/// Turns vitamin/mineral totals (from [NutritionService]) into a 0..1 score
/// and stores/loads it per user.
class NutrientScoreService {
  NutrientScoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Score 0..1: the mean of each tracked nutrient's progress towards its
  /// daily target, clamped at 100% per nutrient so one megadose can't mask
  /// gaps elsewhere.
  static double scoreFromTotals(Map<String, double> totals) {
    if (totals.isEmpty) return 0;
    var sum = 0.0;
    var count = 0;
    _dailyTargets.forEach((key, target) {
      final value = totals[key];
      if (value == null || value <= 0) {
        count++;
        return;
      }
      sum += (value / target).clamp(0.0, 1.0);
      count++;
    });
    if (count == 0) return 0;
    return (sum / count).clamp(0.0, 1.0);
  }

  /// Computes the score from the user's diet history foods via
  /// [NutritionService.totalsFor] and stores it.
  Future<double> refreshFromFoods(String userId, List<String> foods) async {
    final nutrition = NutritionService();
    final totals = await nutrition.totalsFor(foods);
    final score = scoreFromTotals(totals);
    await save(userId, score, totals);
    return score;
  }

  /// Stores the score and per-nutrient breakdown on the user's document.
  Future<void> save(
    String userId,
    double score,
    Map<String, double> totals,
  ) async {
    await _firestore.collection('users').doc(userId).set({
      'nutrientScore': score,
      'nutrientTotals': totals,
      'nutrientUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// The stored score for [userId], or null when never computed.
  Future<double?> load(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    final value = doc.data()?['nutrientScore'];
    return value is num ? value.toDouble() : null;
  }
}
