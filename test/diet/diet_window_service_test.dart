import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/diet/diet_window_service.dart';
import 'package:hackathon/diet/receipt_parser.dart';

/// In-memory [DietStorage] double so the window logic is tested without
/// Firestore.
class _FakeStorage implements DietStorage {
  _FakeStorage(this.days);

  final Map<String, DietDay> days;

  @override
  Future<List<DietDay>> loadAll() async =>
      [...days.values]..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<void> deleteDays(List<String> dayIds) async {
    for (final id in dayIds) {
      days.remove(id);
    }
  }

  @override
  Future<void> save(List<ReceiptItem> items, DateTime day) async {
    final id =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    // Mirrors ReceiptStore's merge write: foods are unioned and each
    // nutrient is incremented, so earlier saves for the day are kept.
    final existing = days[id];
    final nutrition = {...?existing?.nutrition};
    nutrition['CA'] = (nutrition['CA'] ?? 0) + 2;
    days[id] = DietDay(
      id: id,
      date: DateTime(day.year, day.month, day.day),
      foods: {
        ...?existing?.foods,
        for (final item in items) item.name,
      }.toList(),
      nutrition: nutrition,
    );
  }
}

DietDay _day(String id, DateTime date, List<String> foods) => DietDay(
      id: id,
      date: date,
      foods: foods,
      nutrition: {'CA': 10},
    );

void main() {
  final today = DateTime(2026, 11, 7);

  DietWindowService serviceWith(
    Map<String, DietDay> stored, {
    required DateTime now,
  }) {
    return DietWindowService(
      'user',
      storage: _FakeStorage(stored),
      now: () => now,
    );
  }

  test('cutoff is exactly two weeks back, at midnight', () {
    final service = serviceWith({}, now: DateTime(2026, 11, 7, 15, 30));
    expect(service.cutoff(), DateTime(2026, 10, 24));
  });

  test('recentDays keeps in-window days, newest first', () async {
    final fresh = _day('2026-11-07', DateTime(2026, 11, 7), ['Milk']);
    final edge = _day('2026-10-24', DateTime(2026, 10, 24), ['Bread']);
    final service = serviceWith({fresh.id: fresh, edge.id: edge}, now: today);

    final days = await service.recentDays();
    expect([for (final d in days) d.id], ['2026-11-07', '2026-10-24']);
    expect(service.recentFoods(), ['Milk', 'Bread']);
  });

  test('stale days are deleted from storage and excluded from reads',
      () async {
    final fresh = _day('2026-11-07', DateTime(2026, 11, 7), ['Milk']);
    final stale = _day('2026-10-10', DateTime(2026, 10, 10), ['Cereal']);
    final storage = _FakeStorage({fresh.id: fresh, stale.id: stale});
    final service = DietWindowService('user', storage: storage, now: () => today);

    final days = await service.recentDays();
    expect([for (final d in days) d.id], ['2026-11-07']);
    expect(storage.days.containsKey('2026-10-10'), isFalse,
        reason: 'stale day must be deleted from storage');
    expect(service.recentFoods(), ['Milk']);
  });

  test('recentFoods keeps duplicates across days (frequency)', () async {
    final d1 = _day('2026-11-06', DateTime(2026, 11, 6), ['Eggs', 'Milk']);
    final d2 = _day('2026-11-07', DateTime(2026, 11, 7), ['Eggs']);
    final service = serviceWith({d1.id: d1, d2.id: d2}, now: today);

    await service.recentDays();
    // Newest day (11-07) first: its Eggs, then 11-06's Eggs and Milk.
    expect(service.recentFoods(), ['Eggs', 'Eggs', 'Milk']);
  });

  test('recentNutritionTotals sums only days inside the window', () async {
    final fresh = _day('2026-11-07', DateTime(2026, 11, 7), ['Milk']);
    final stale = _day('2026-10-10', DateTime(2026, 10, 10), ['Cereal']);
    final service = serviceWith({fresh.id: fresh, stale.id: stale}, now: today);

    await service.recentDays();
    expect(service.recentNutritionTotals(), {'CA': 10.0});
  });

  test('save writes through storage and prunes stale days', () async {
    final stale = _day('2026-10-01', DateTime(2026, 10, 1), ['Old item']);
    final keeper = _day('2026-11-06', DateTime(2026, 11, 6), ['Milk']);
    final storage = _FakeStorage({stale.id: stale, keeper.id: keeper});
    final service = DietWindowService('user', storage: storage, now: () => today);

    await service.save([
      const ReceiptItem(name: 'Eggs', price: 2.0),
    ], DateTime(2026, 11, 7));

    expect(storage.days.containsKey('2026-10-01'), isFalse);
    // Newest day first: 11-07's Eggs, then 11-06's Milk.
    expect(service.recentFoods(), ['Eggs', 'Milk']);
  });

  test('a second save on the same day keeps the earlier nutrition', () async {
    final storage = _FakeStorage({});
    final service = DietWindowService('user', storage: storage, now: () => today);

    await service.save([const ReceiptItem(name: 'Milk', price: 1.0)], today);
    await service.save([const ReceiptItem(name: 'Eggs', price: 2.0)], today);

    expect(service.recentFoods(), ['Milk', 'Eggs']);
    expect(service.recentNutritionTotals(), {'CA': 4.0});
  });

  test('save rejects days before the window instead of pruning them',
      () async {
    final storage = _FakeStorage({});
    final service = DietWindowService('user', storage: storage, now: () => today);

    await expectLater(
      service.save(
        [const ReceiptItem(name: 'Eggs', price: 2.0)],
        DateTime(2026, 10, 23),
      ),
      throwsA(isA<DietDayOutOfWindowException>()),
    );
    expect(storage.days, isEmpty, reason: 'nothing may be written');
  });

  test('save accepts the oldest in-window day', () async {
    final storage = _FakeStorage({});
    final service = DietWindowService('user', storage: storage, now: () => today);

    await service.save(
      [const ReceiptItem(name: 'Eggs', price: 2.0)],
      DateTime(2026, 10, 24, 18),
    );
    expect(storage.days.keys, ['2026-10-24']);
  });

  test('cutoffFor matches the review sheet bound', () {
    expect(
      DietWindowService.cutoffFor(DateTime(2026, 11, 7, 23, 59)),
      DateTime(2026, 10, 24),
    );
  });

  test('deleteDay removes the day from storage and the mirror', () async {
    final d1 = _day('2026-11-06', DateTime(2026, 11, 6), ['Milk']);
    final storage = _FakeStorage({d1.id: d1});
    final service = DietWindowService('user', storage: storage, now: () => today);

    await service.recentDays();
    await service.deleteDay(d1.id);
    expect(storage.days, isEmpty);
    expect(service.recentFoods(), isEmpty);
  });
}
