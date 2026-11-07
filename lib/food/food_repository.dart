import 'package:cloud_firestore/cloud_firestore.dart';

import 'food.dart';
import 'health_condition.dart';
import 'preference.dart';

/// Reads and writes the top-level `food` collection.
class FoodRepository {
  CollectionReference<Map<String, dynamic>> get foods =>
      FirebaseFirestore.instance.collection('food');

  DocumentReference<Map<String, dynamic>> doc(String name) =>
      foods.doc(Food.idFor(name));

  /// Returns the food called [name], or null if it is not stored yet.
  Future<Food?> get(String name) async {
    final data = (await doc(name).get()).data();
    return data == null ? null : Food.fromMap(data);
  }

  Stream<Food?> watch(String name) => doc(name)
      .snapshots()
      .map((snap) => snap.data() == null ? null : Food.fromMap(snap.data()!));

  /// Creates or fully replaces [food].
  Future<void> save(Food food) => foods.doc(food.id).set({
    ...food.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Adds [conditions] without duplicating ones already stored.
  Future<void> addHealthConditions(
    String name,
    Iterable<HealthCondition> conditions,
  ) => doc(name).update({
    'health_conditions': FieldValue.arrayUnion([
      for (final c in conditions) c.id,
    ]),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Sets the local news for [name]; pass an empty string to clear it.
  Future<void> setLocalNews(String name, String news) => doc(name)
      .update({'local_news': news, 'updatedAt': FieldValue.serverTimestamp()});

  /// Foods relevant to [condition], e.g. everything flagged [HealthCondition.hypertension].
  Future<List<Food>> withCondition(HealthCondition condition) async {
    final snap = await foods
        .where('health_conditions', arrayContains: condition.id)
        .get();
    return [for (final d in snap.docs) Food.fromMap(d.data())];
  }

  /// Foods that clash with [preference], e.g. everything not
  /// [Preference.vegan].
  Future<List<Food>> withPreference(Preference preference) async {
    final snap = await foods
        .where('personal_prefs', arrayContains: preference.id)
        .get();
    return [for (final d in snap.docs) Food.fromMap(d.data())];
  }
}
