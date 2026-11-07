import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/assistant/assistant_models.dart';
import 'package:hackathon/assistant/assistant_repository.dart';

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
