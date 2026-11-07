import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'receipt_parser.dart';
import 'receipt_store.dart';

/// One stored diet day: the foods bought that day plus the aggregated
/// vitamins and minerals of everything bought.
class DietDay {
  const DietDay({
    required this.id,
    required this.date,
    required this.foods,
    required this.nutrition,
  });

  /// Firestore document id (`yyyy-MM-dd`).
  final String id;

  /// The day the food was bought, at local midnight.
  final DateTime date;

  /// Food names from that day's receipts.
  final List<String> foods;

  /// Aggregated nutrients for the day, keyed by shorthand (CA, VITC, ...).
  final Map<String, double> nutrition;

  /// Parses one `users/{uid}/diet/{yyyy-MM-dd}` document.
  factory DietDay.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final date = (data['date'] as Timestamp?)?.toDate().toLocal();
    return DietDay(
      id: doc.id,
      date: date ?? DateTime(1970),
      foods: List<String>.from(data['foods'] ?? const []),
      nutrition: <String, double>{
        for (final entry in (data['nutrition'] as Map? ?? {}).entries)
          if (entry.value is num) '${entry.key}': (entry.value as num).toDouble(),
      },
    );
  }
}

/// Interface for the diet persistence the window service reads and prunes.
/// [ReceiptStore] is the Firebase implementation; tests substitute fakes.
abstract class DietStorage {
  /// Every stored day, newest first.
  Future<List<DietDay>> loadAll();

  /// Deletes the days with the given ids.
  Future<void> deleteDays(List<String> dayIds);

  /// Saves foods under [day].
  Future<void> save(List<ReceiptItem> items, DateTime day);
}

/// Implements [DietStorage] on top of the Firestore-backed [ReceiptStore].
class FirestoreDietStorage implements DietStorage {
  FirestoreDietStorage(this.userId) : _store = ReceiptStore(userId);

  final String userId;

  final ReceiptStore _store;

  @override
  Future<List<DietDay>> loadAll() async {
    final snap = await _store.history().first;
    return [for (final doc in snap.docs) DietDay.fromDoc(doc)];
  }

  @override
  Future<void> deleteDays(List<String> dayIds) async {
    for (final id in dayIds) {
      await _store.delete(id);
    }
  }

  @override
  Future<void> save(List<ReceiptItem> items, DateTime day) =>
      _store.save(items, day);
}

/// Sliding-window view over the user's stored diet.
///
/// Anything wanting recent diet data reads from here rather than from
/// Firestore directly. The window covers the last [window] days (two weeks);
/// days that fall out of it are deleted — from storage and from the local
/// mirror — whenever the window is read or written, so the store never grows
/// beyond two weeks. Every read refreshes the mirror, so callers always see
/// everything the person ate recently.
class DietWindowService {
  DietWindowService(
    this.userId, {
    DietStorage? storage,
    DateTime Function()? now,
  }) : storage = storage ?? FirestoreDietStorage(userId),
       _now = now ?? DateTime.now;

  final String userId;

  /// Where the diet is persisted; prunes delete through this.
  final DietStorage storage;

  final DateTime Function() _now;

  /// How much diet history is kept.
  static const window = Duration(days: 14);

  /// Bumped by every mutation so stream listeners notice cheaply.
  int _version = 0;

  /// Local mirror of the window, keyed by day id. Refreshed on every read
  /// and pruned alongside storage, so deleted days never reappear here.
  final Map<String, DietDay> _local = {};

  /// The oldest day still inside the window, at local midnight.
  ///
  /// Counts back whole calendar days rather than subtracting a duration:
  /// a 14×24h subtraction drifts an hour across DST changes and would
  /// misclassify the boundary day.
  DateTime cutoff() {
    final n = _now();
    return DateTime(n.year, n.month, n.day - window.inDays);
  }

  /// Live stream of the window, newest first. Emits the refreshed window
  /// immediately on listen, then again whenever [save] or [deleteDay]
  /// change it, and at least every hour so day rollover and pruning are
  /// picked up while the page stays open. Each event is a full refresh that
  /// prunes expired days from storage and the mirror.
  Stream<List<DietDay>> recentDaysStream() async* {
    var seenVersion = -1;
    var lastRefresh = _now();
    while (true) {
      final days = await recentDays();
      seenVersion = _version;
      lastRefresh = _now();
      yield days;
      // Sleep until something changes or an hour passes.
      while (_version == seenVersion &&
          _now().difference(lastRefresh) < const Duration(hours: 1)) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  /// Loads the window: refreshes the mirror from storage, deleting anything
  /// older than two weeks on the way. Returns the in-window days, newest
  /// first.
  Future<List<DietDay>> recentDays() async {
    final all = await storage.loadAll();
    final cutoffDay = cutoff();
    final expired = [
      for (final day in all)
        if (day.date.isBefore(cutoffDay)) day.id,
    ];
    if (expired.isNotEmpty) {
      await storage.deleteDays(expired);
    }
    final inWindow = [
      for (final day in all)
        if (!day.date.isBefore(cutoffDay)) day,
    ]..sort((a, b) => b.date.compareTo(a.date));
    _local
      ..clear()
      ..addEntries([for (final day in inWindow) MapEntry(day.id, day)]);
    return inWindow;
  }

  /// Every food in the current window, newest day first, duplicates kept so
  /// frequency (how often a food was bought) is preserved. Call [recentDays]
  /// first to refresh the mirror.
  List<String> recentFoods() {
    final days = [..._local.values]..sort((a, b) => b.date.compareTo(a.date));
    return [for (final day in days) ...day.foods];
  }

  /// Nutrient totals summed across the whole window. Call [recentDays]
  /// first to refresh the mirror.
  Map<String, double> recentNutritionTotals() {
    final totals = <String, double>{};
    for (final day in _local.values) {
      day.nutrition.forEach((key, value) {
        totals[key] = (totals[key] ?? 0) + value;
      });
    }
    return totals;
  }

  /// Saves foods under [day] (through storage), trims the window so expired
  /// days are removed in the same breath, and wakes [recentDaysStream]
  /// listeners with the refreshed window.
  Future<void> save(List<ReceiptItem> items, DateTime day) async {
    await storage.save(items, day);
    _version++;
    await recentDays();
  }

  /// Deletes one day (storage + local mirror) and wakes [recentDaysStream]
  /// listeners with the refreshed window.
  Future<void> deleteDay(String dayId) async {
    await storage.deleteDays([dayId]);
    _local.remove(dayId);
    _version++;
  }

  /// Closes nothing; retained so callers have an explicit teardown hook.
  void dispose() {}
}
