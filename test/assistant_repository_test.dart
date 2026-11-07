import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/assistant/assistant_models.dart';
import 'package:hackathon/assistant/assistant_repository.dart';
import 'package:hackathon/diet/diet_window_service.dart';
import 'package:hackathon/diet/nutrient_insights.dart';
import 'package:hackathon/diet/receipt_parser.dart';
import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/food_recommendation_service.dart';
import 'package:hackathon/food/health_condition.dart';
import 'package:hackathon/food/nutrient.dart';
import 'package:hackathon/food/preference.dart';

void main() {
  group('FirestoreAssistantRepository proposal boundary', () {
    late _NoReadFirestore firestore;
    late FirestoreAssistantRepository repository;

    setUp(() {
      firestore = _NoReadFirestore();
      repository = FirestoreAssistantRepository(
        userId: 'fixed-user',
        firestore: firestore,
      );
    });

    test('registers bounded read and proposal tools', () {
      final names = repository.tools
          .map((t) => (t['function'] as Map)['name'])
          .toSet();
      expect(
        names,
        containsAll([
          'get_user_records',
          'lookup_food',
          'search_foods',
          'show_food_images',
          'propose_preference_change',
          'propose_food_log',
        ]),
      );
    });

    test('proposal is read/write free and produces app-owned action', () async {
      final result = await repository.execute('propose_food_log', {
        'name': 'Porridge',
        'localDate': '2026-11-07',
        'kind': 'eaten',
      });
      expect(firestore.calls, 0);
      expect(result.data['status'], 'pending_confirmation');
      expect(result.action, isNotNull);
      expect(result.action!.id, isNotEmpty);
      expect(result.action!.summary, 'Log Porridge as eaten on 2026-11-07');
    });

    test(
      'rejects malformed dates and unknown sources before database access',
      () async {
        final badDate = await repository.execute('propose_food_log', {
          'name': 'Porridge',
          'localDate': '2026-02-30',
          'kind': 'eaten',
        });
        final badSource = await repository.execute('get_user_records', {
          'source': 'otherUsers',
        });
        expect(badDate.data['error'], 'invalid_date');
        expect(badSource.data['error'], 'invalid_source');
        expect(firestore.calls, 0);
      },
    );

    test(
      'confirmation rejects fabricated actions before database access',
      () async {
        final fake = AssistantAction(
          id: 'fabricated-id',
          toolName: 'propose_food_log',
          arguments: const {'entryId': 'x'},
          summary: 'fake',
        );
        expect(await repository.confirm(fake), {
          'success': false,
          'error': 'unknown_or_expired_action',
        });
        expect(firestore.calls, 0);
      },
    );

    test(
      'rejects date filters for singleton sources before database access',
      () async {
        final result = await repository.execute('get_user_records', {
          'source': 'healthData',
          'startDate': '2026-11-01',
        });
        expect(result.data['error'], 'unsupported_date_filter');
        expect(firestore.calls, 0);
      },
    );
  });
  test('diet records come from the two-week window, paged', () async {
    final now = DateTime(2026, 11, 7, 12);
    DietDay day(int daysAgo) {
      final date = DateTime(now.year, now.month, now.day - daysAgo);
      return DietDay(
        id: 'd$daysAgo',
        date: date,
        foods: ['food$daysAgo'],
        nutrition: {'VITC': daysAgo.toDouble()},
      );
    }

    final storage = _DietStorage({
      for (final d in [day(0), day(3), day(13), day(20)]) d.id: d,
    });
    final firestore = _NoReadFirestore();
    final repository = FirestoreAssistantRepository(
      userId: 'fixed-user',
      firestore: firestore,
      diet: DietWindowService('fixed-user', storage: storage, now: () => now),
    );

    final first = await repository.execute('get_user_records', {
      'source': 'diet',
      'limit': 2,
    });
    final records = first.data['records'] as List;
    expect([for (final r in records) (r as Map)['id']], ['d0', 'd3']);
    expect(first.data['hasMore'], true);
    expect(firestore.calls, 0);
    expect(storage.days.containsKey('d20'), isFalse);

    final second = await repository.execute('get_user_records', {
      'source': 'diet',
      'limit': 2,
      'cursor': first.data['nextCursor'],
    });
    expect(
      [for (final r in second.data['records'] as List) (r as Map)['id']],
      ['d13'],
    );
    expect(second.data['hasMore'], false);

    final ranged = await repository.execute('get_user_records', {
      'source': 'diet',
      'startDate': '2026-11-01',
      'endDate': '2026-11-04',
    });
    expect(
      [for (final r in ranged.data['records'] as List) (r as Map)['id']],
      ['d3'],
    );
  });

  group('get_alternatives', () {
    const crisps = Food(
      name: 'Crisps',
      alternatives: {
        HealthCondition.none: {
          Preference.none: ['Popcorn', 'Oranges'],
        },
      },
      nutrients: {Nutrient.sodium: 700},
    );
    const popcorn = Food(name: 'Popcorn', personalPrefs: {Preference.vegan});
    final foods = {
      for (final f in [crisps, popcorn]) f.id: f,
    };

    FirestoreAssistantRepository repositoryFor(
      _NoReadFirestore firestore,
      Map<String, dynamic> user,
    ) => FirestoreAssistantRepository(
      userId: 'fixed-user',
      firestore: firestore,
      recommendations: FoodRecommendationService(
        fetcher: (name) async => foods[Food.idFor(name)],
        userFetcher: (uid) async => uid == 'fixed-user' ? user : null,
        insightsFetcher: (uid) async => NutrientInsights.fromDaily({
          DateTime(2026, 11, 7): {'NA': 20000},
        }, today: DateTime(2026, 11, 7)),
      ),
    );

    test('delegates to the recommendation service', () async {
      final firestore = _NoReadFirestore();
      final result = await repositoryFor(firestore, {
        'dietary': ['Vegan'],
      }).execute('get_alternatives', {'name': 'crisps'});
      final data = result.data;
      expect(firestore.calls, 0);
      expect(data['found'], true);
      expect(data['shouldAvoid'], true);
      expect(data['canBuy'], false);
      expect(data['excessNutrients'], ['Sodium']);
      expect(data['reasons'], ['Diet already high in Sodium']);
      expect(data['swapDeclined'], false);
      expect((data['food'] as Map)['nutrients'], {'NA': 700.0});
      final alternatives = data['alternatives'] as List;
      expect(
        [for (final a in alternatives) (a as Map)['name']],
        ['Popcorn', 'Oranges'],
      );
      expect((alternatives[0] as Map)['knownConflicts'], ['Vegan']);
      expect((alternatives[1] as Map)['knownConflicts'], isNull);
    });

    test('reports declined swaps without alternatives', () async {
      final result = await repositoryFor(_NoReadFirestore(), {
        'ignored_swap_items': ['crisps'],
      }).execute('get_alternatives', {'name': 'Crisps'});
      expect(result.data['shouldAvoid'], true);
      expect(result.data['excessNutrients'], ['Sodium']);
      expect(result.data['swapDeclined'], true);
      expect(result.data['alternatives'], isEmpty);
    });

    test('unknown food is not found', () async {
      final result = await repositoryFor(
        _NoReadFirestore(),
        {},
      ).execute('get_alternatives', {'name': 'Durian'});
      expect(result.data, {'found': false, 'alternatives': []});
    });
  });
}

class _DietStorage implements DietStorage {
  _DietStorage(this.days);

  final Map<String, DietDay> days;

  @override
  Future<List<DietDay>> loadAll() async => [...days.values];

  @override
  Future<void> deleteDays(List<String> dayIds) async =>
      dayIds.forEach(days.remove);

  @override
  Future<void> save(List<ReceiptItem> items, DateTime day) async {}
}

class _NoReadFirestore implements FirebaseFirestore {
  int calls = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    calls++;
    throw StateError('Unexpected Firestore access: $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
