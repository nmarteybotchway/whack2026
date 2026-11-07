import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../food/food.dart';
import '../food/health_condition.dart';
import '../food/preference.dart';
import 'assistant_models.dart';

/// Firestore-backed, UID-scoped data source for assistant tools and actions.
class FirestoreAssistantRepository implements AssistantDataSource {
  FirestoreAssistantRepository({
    required this.userId,
    FirebaseFirestore? firestore,
    this._profile,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final String userId;
  final FirebaseFirestore _db;
  final Map<String, Object?>? _profile;
  final Map<String, AssistantAction> _pending = {};
  final Map<String, Map<String, Object?>> _completed = {};

  DocumentReference<Map<String, dynamic>> get _user =>
      _db.collection('users').doc(userId);

  @override
  List<Map<String, Object?>> get tools => _toolDefinitions;

  static const _toolDefinitions = <Map<String, Object?>>[
    {
      'type': 'function',
      'function': {
        'name': 'get_user_summary',
        'description':
            'Get the current user profile and latest health summary.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_preferences',
        'description':
            'Read religion, dietary preferences and health conditions.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_user_records',
        'description': 'Read one registered personal data source with bounded pagination and optional date range.',
        'parameters': {
          'type': 'object',
          'properties': {
            'source': {
              'type': 'string',
              'enum': [
                'profile',
                'measurements',
                'healthData',
                'assistantSettings',
                'bloodPressure',
                'diet',
                'receipts',
                'foodEntries',
              ],
            },
            'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50},
            'cursor': {'type': 'string'},
            'startDate': {'type': 'string', 'format': 'date'},
            'endDate': {'type': 'string', 'format': 'date'},
          },
          'required': ['source'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'lookup_food',
        'description': 'Read a stored food by name.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'minLength': 1, 'maxLength': 120},
          },
          'required': ['name'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_foods',
        'description': 'Search the shared food catalog by name prefix, or browse a bounded page.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'maxLength': 80},
            'limit': {'type': 'integer', 'minimum': 1, 'maximum': 30},
            'cursor': {'type': 'string'},
          },
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_alternatives',
        'description':
            'Find stored alternatives and evaluate known user conflicts.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'minLength': 1, 'maxLength': 120},
          },
          'required': ['name'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_food_news',
        'description': 'Read stored food news and general guidance.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'minLength': 1, 'maxLength': 120},
          },
          'required': ['name'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_nutrition',
        'description': 'Read cached nutrition information for a food.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'minLength': 1, 'maxLength': 120},
          },
          'required': ['name'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'show_food_images',
        'description':
            'Resolve stored food image references for selected names.',
        'parameters': {
          'type': 'object',
          'properties': {
            'names': {
              'type': 'array',
              'items': {'type': 'string'},
              'minItems': 1,
              'maxItems': 8,
            },
          },
          'required': ['names'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'propose_preference_change',
        'description': 'Propose a preference edit; user confirmation is required before it is saved.',
        'parameters': {
          'type': 'object',
          'properties': {
            'field': {
              'type': 'string',
              'enum': ['religion', 'dietary', 'health_conditions'],
            },
            'value': {'type': 'string', 'minLength': 1, 'maxLength': 100},
            'operation': {
              'type': 'string',
              'enum': ['add', 'remove'],
            },
          },
          'required': ['field', 'value', 'operation'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'propose_food_log',
        'description': 'Propose a manual eaten or purchased food entry; confirmation is required.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'minLength': 1, 'maxLength': 120},
            'localDate': {'type': 'string', 'format': 'date'},
            'kind': {
              'type': 'string',
              'enum': ['eaten', 'purchased'],
            },
            'amount': {'type': 'string', 'maxLength': 80},
          },
          'required': ['name', 'localDate', 'kind'],
          'additionalProperties': false,
        },
      },
    },
  ];

  @override
  Future<AssistantSettings> loadSettings() async {
    final snap = await _user
        .collection('assistantSettings')
        .doc('preferences')
        .get();
    return AssistantSettings.fromMap(snap.data() ?? const {});
  }

  @override
  Future<void> saveSettings(AssistantSettings settings) async {
    await _user.collection('assistantSettings').doc('preferences').set({
      ...settings.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<Map<String, Object?>> summary() async {
    final result = <String, Object?>{};
    final sources = <String, Future<Map<String, dynamic>?> Function()>{
      'profile': () async => (await _user.get()).data(),
      'measurements': () async =>
          (await _user.collection('healthProfile').doc('measurements').get())
              .data(),
      'healthData': () async =>
          (await _user.collection('healthData').doc('latest').get()).data(),
    };
    for (final entry in sources.entries) {
      try {
        result[entry.key] = _jsonSafe(await entry.value());
      } catch (e) {
        result[entry.key] = {'available': false, 'error': _errorCode(e)};
      }
    }
    result['authProfile'] = _jsonSafe(_profile ?? const {});
    return result;
  }

  @override
  Future<AssistantToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
  ) => _execute(name, arguments).timeout(
    const Duration(seconds: 15),
    onTimeout: () =>
        const AssistantToolResult({'available': false, 'error': 'timeout'}),
  );

  Future<AssistantToolResult> _execute(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    try {
      switch (name) {
        case 'get_user_summary':
          return AssistantToolResult(await summary());
        case 'get_preferences':
          final data = (await _user.get()).data() ?? {};
          return AssistantToolResult({
            for (final k in ['religion', 'dietary', 'health_conditions'])
              k: data[k] ?? const [],
          });
        case 'get_user_records':
          return AssistantToolResult(await _records(arguments));
        case 'lookup_food':
          final id = Food.idFor(_requiredString(arguments, 'name'));
          final doc = await _db.collection('food').doc(id).get();
          return AssistantToolResult({
            'found': doc.exists,
            if (doc.exists)
              'food': {
                'id': doc.id,
                ..._jsonSafe(doc.data()) as Map<String, Object?>,
              },
          });
        case 'search_foods':
          return AssistantToolResult(await _searchFoods(arguments));
        case 'get_alternatives':
          return AssistantToolResult(
            await _alternatives(_requiredString(arguments, 'name')),
          );
        case 'get_food_news':
          final record = await _getFoodRecord(
            _requiredString(arguments, 'name'),
          );
          final localNews = record.food?.localNews ?? '';
          final generalInfo = record.food?.generalInfo ?? '';
          final hasAlerts =
              localNews.trim().isNotEmpty || generalInfo.trim().isNotEmpty;
          return AssistantToolResult({
            'localNews': localNews.trim().isEmpty
                ? 'No negative news discovered'
                : localNews,
            'generalInfo': generalInfo.trim().isEmpty
                ? 'No negative news discovered'
                : generalInfo,
            'hasAlerts': hasAlerts,
            'source': record.source,
            'updatedAt': _jsonSafe(record.raw?['updatedAt']),
          });
        case 'get_nutrition':
          final key = _requiredString(arguments, 'name').trim().toLowerCase();
          final doc = await _db.collection('nutritionCache').doc(key).get();
          return AssistantToolResult({
            'found': doc.exists,
            if (doc.exists) 'record': _jsonSafe(doc.data()),
            'source': 'nutritionCache/$key',
          });
        case 'show_food_images':
          return await _images(arguments);
        case 'propose_preference_change':
          return await _proposePreference(arguments);
        case 'propose_food_log':
          return await _proposeFoodLog(arguments);
        default:
          return AssistantToolResult({'error': 'unknown_tool'});
      }
    } catch (e) {
      return AssistantToolResult({'error': _errorCode(e), 'available': false});
    }
  }

  Future<Map<String, Object?>> _records(Map<String, dynamic> args) async {
    final source = _requiredString(args, 'source');
    const paths = {
      'bloodPressure': 'bloodPressure',
      'diet': 'diet',
      'receipts': 'receipts',
      'foodEntries': 'foodEntries',
    };
    final path = paths[source];
    if (path == null &&
        !const {
          'profile',
          'measurements',
          'healthData',
          'assistantSettings',
        }.contains(source)) {
      throw const FormatException('invalid_source');
    }
    final start = _dateArg(args['startDate']);
    final end = _dateArg(args['endDate']);
    if (start != null && end != null && start.isAfter(end)) {
      throw const FormatException('invalid_date_range');
    }
    final limit = _boundedInt(args['limit'], fallback: 20, max: 50);
    if (source == 'profile' ||
        source == 'measurements' ||
        source == 'healthData' ||
        source == 'assistantSettings') {
      if (start != null || end != null) {
        throw const FormatException('unsupported_date_filter');
      }
      final ref = switch (source) {
        'profile' => _user,
        'measurements' => _user.collection('healthProfile').doc('measurements'),
        'healthData' => _user.collection('healthData').doc('latest'),
        _ => _user.collection('assistantSettings').doc('preferences'),
      };
      final doc = await ref.get();
      return {
        'source': source,
        'records': [
          if (doc.exists)
            {'id': doc.id, ..._jsonSafe(doc.data()) as Map<String, Object?>},
        ],
        'nextCursor': null,
        'hasMore': false,
      };
    }
    Query<Map<String, dynamic>> query = _user.collection(path!);
    final dateField = switch (source) {
      'bloodPressure' => 'measuredAt',
      'diet' => 'date',
      'receipts' => 'scannedAt',
      _ => 'localDate',
    };
    if (start != null) {
      query = query.where(
        dateField,
        isGreaterThanOrEqualTo: Timestamp.fromDate(start),
      );
    }
    if (end != null) {
      query = query.where(
        dateField,
        isLessThan: Timestamp.fromDate(end.add(const Duration(days: 1))),
      );
    }
    query = query.orderBy(dateField, descending: true);
    final cursor = args['cursor'];
    if (cursor is String && cursor.isNotEmpty) {
      final last = await _user.collection(path).doc(cursor).get();
      if (last.exists) {
        query = query.startAfterDocument(last);
      }
    }
    final snap = await query.limit(limit + 1).get();
    final more = snap.docs.length > limit;
    final docs = snap.docs.take(limit).toList();
    return {
      'source': source,
      'records': [
        for (final d in docs)
          {'id': d.id, ..._jsonSafe(d.data()) as Map<String, Object?>},
      ],
      'nextCursor': more && docs.isNotEmpty ? docs.last.id : null,
      'hasMore': more,
    };
  }

  Future<Map<String, Object?>> _searchFoods(Map<String, dynamic> args) async {
    final rawTerm = (args['query'] as String? ?? '').trim();
    final term = rawTerm.isEmpty ? '' : Food.idFor(rawTerm);
    final limit = _boundedInt(args['limit'], fallback: 10, max: 30);
    Query<Map<String, dynamic>> query = _db
        .collection('food')
        .orderBy(FieldPath.documentId);
    if (term.isNotEmpty) {
      query = query.startAt([term]).endAt(['$term\uf8ff']);
    }
    if (args['cursor'] case final String cursor when cursor.isNotEmpty) {
      final last = await _db.collection('food').doc(cursor).get();
      if (last.exists) query = query.startAfterDocument(last);
    }
    final snap = await query.limit(limit + 1).get();
    final docs = snap.docs.take(limit).toList();
    return {
      'foods': [
        for (final d in docs)
          {'id': d.id, ..._jsonSafe(d.data()) as Map<String, Object?>},
      ],
      'hasMore': snap.docs.length > limit,
      'nextCursor': snap.docs.length > limit && docs.isNotEmpty
          ? docs.last.id
          : null,
    };
  }

  Future<Map<String, Object?>> _alternatives(String name) async {
    final baseRecord = await _getFoodRecord(name);
    final base = baseRecord.food;
    if (base == null) {
      return {'found': false, 'alternatives': const []};
    }
    final prefs = await _preferences();
    final conditions = {
      for (final s in prefs['health_conditions'] as List<String>)
        ?HealthCondition.fromId(s),
    };
    final dietary = <Preference>{
      for (final s in [
        ...prefs['religion'] as List<String>,
        ...prefs['dietary'] as List<String>,
      ])
        ?(Preference.fromLabel(s) ?? Preference.fromId(s)),
    };
    final ranked = base.alternativesFor(conditions: conditions, prefs: dietary);
    final output = <Map<String, Object?>>[];
    for (final candidate in ranked.take(12)) {
      final candidateRecord = await _getFoodRecord(candidate);
      final food = candidateRecord.food;
      final conflicts = <String>[
        if (food != null)
          ...food.healthConditions
              .where((c) => conditions.contains(c))
              .map((c) => c.label),
        if (food != null)
          ...food.personalPrefs
              .where((p) => dietary.contains(p))
              .map((p) => p.label),
      ];
      final unknown = <String>[
        ...(prefs['dietary'] ?? const <String>[]).where(
          (v) =>
              Preference.fromLabel(v) == null && Preference.fromId(v) == null,
        ),
        ...(prefs['religion'] ?? const <String>[]).where(
          (v) =>
              Preference.fromLabel(v) == null && Preference.fromId(v) == null,
        ),
        ...(prefs['health_conditions'] ?? const <String>[]).where(
          (v) => HealthCondition.fromId(v) == null,
        ),
      ];
      output.add({
        'name': candidate,
        'knownConflicts': conflicts,
        'unknownConstraints': unknown,
        'compatibleWithKnownConstraints': food == null || unknown.isNotEmpty
            ? null
            : conflicts.isEmpty,
        'evidence': food == null
            ? 'candidate catalog record missing'
            : 'evaluated stored condition and preference conflict tags',
        'score': ranked.length - ranked.indexOf(candidate),
        'food': food == null ? null : _foodMap(food),
        'source': candidateRecord.source,
        'updatedAt': _jsonSafe(candidateRecord.raw?['updatedAt']),
      });
    }
    return {
      'found': true,
      'food': _foodMap(base),
      'source': baseRecord.source,
      'updatedAt': _jsonSafe(baseRecord.raw?['updatedAt']),
      'alternatives': output,
    };
  }

  Future<AssistantToolResult> _images(Map<String, dynamic> args) async {
    final names = args['names'];
    if (names is! List ||
        names.isEmpty ||
        names.length > 8 ||
        names.any((e) => e is! String || e.trim().isEmpty)) {
      throw const FormatException('invalid_names');
    }
    final images = <AssistantImage>[];
    for (final raw in names.cast<String>()) {
      final id = Food.idFor(raw);
      final doc = await _db.collection('food_images').doc(id).get();
      final data = doc.data();
      if (data == null) continue;
      final url = data['url'];
      final page = data['page'];
      final displayName = data['name'];
      final parsedUrl = url is String ? Uri.tryParse(url) : null;
      if (url is! String ||
          parsedUrl?.scheme != 'https' ||
          parsedUrl?.host.isNotEmpty != true ||
          displayName is! String ||
          Food.idFor(displayName) != id) {
        continue;
      }
      final parsedPage = page is String ? Uri.tryParse(page) : null;
      images.add(
        AssistantImage(
          foodId: id,
          name: displayName,
          url: url,
          sourcePage:
              parsedPage?.scheme == 'https' && parsedPage!.host.isNotEmpty
              ? page as String
              : '',
        ),
      );
    }
    return AssistantToolResult({
      'images': [
        for (final i in images)
          {
            'foodId': i.foodId,
            'name': i.name,
            'url': i.url,
            'sourcePage': i.sourcePage,
          },
      ],
    }, images: images);
  }

  Future<AssistantToolResult> _proposePreference(
    Map<String, dynamic> args,
  ) async {
    final field = _requiredString(args, 'field');
    final value = _requiredString(args, 'value').trim();
    final operation = _requiredString(args, 'operation');
    if (!const {'religion', 'dietary', 'health_conditions'}.contains(field) ||
        !const {'add', 'remove'}.contains(operation) ||
        value.length > 100) {
      throw const FormatException('invalid_preference_change');
    }
    final current = await _user.get();
    final before = List<String>.from(current.data()?[field] ?? const []);
    final canonicalValue = _canonicalPreference(field, value, before);
    final after = [...before];
    if (operation == 'add' && !after.contains(canonicalValue)) {
      after.add(canonicalValue);
    }
    if (operation == 'remove') {
      after.remove(canonicalValue);
    }
    if (after.length > 100) {
      throw const FormatException('too_many_preferences');
    }
    final action = _newAction(
      'propose_preference_change',
      {
        'field': field,
        'value': canonicalValue,
        'operation': operation,
        'before': before,
        'after': after,
      },
      '$operation "$canonicalValue" ${operation == 'add' ? 'to' : 'from'} $field',
    );
    return AssistantToolResult({
      'status': 'pending_confirmation',
      'actionId': action.id,
      'summary': action.summary,
    }, action: action);
  }

  Future<AssistantToolResult> _proposeFoodLog(Map<String, dynamic> args) async {
    final name = _requiredString(args, 'name').trim();
    final day = _dateArg(args['localDate']);
    final kind = _requiredString(args, 'kind');
    final amount = args['amount'];
    if (name.isEmpty ||
        name.length > 120 ||
        day == null ||
        !const {'eaten', 'purchased'}.contains(kind) ||
        (amount != null && (amount is! String || amount.length > 80))) {
      throw const FormatException('invalid_food_log');
    }
    final id = _randomId();
    final action = _newAction('propose_food_log', {
      'entryId': id,
      'name': name,
      'localDate': _dateId(day),
      'kind': kind,
      if (amount is String && amount.trim().isNotEmpty) 'amount': amount.trim(),
    }, 'Log $name as $kind on ${_dateId(day)}');
    return AssistantToolResult({
      'status': 'pending_confirmation',
      'actionId': action.id,
      'summary': action.summary,
    }, action: action);
  }

  AssistantAction _newAction(
    String tool,
    Map<String, dynamic> args,
    String summary,
  ) {
    final safeArgs = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(args)) as Map,
    );
    final action = AssistantAction(
      id: _randomId(),
      toolName: tool,
      arguments: safeArgs,
      summary: summary,
    );
    if (_pending.length >= 40) {
      final oldest = _pending.keys.first;
      _pending.remove(oldest);
      _completed.remove(oldest);
    }
    _pending[action.id] = AssistantAction(
      id: action.id,
      toolName: action.toolName,
      arguments: Map<String, dynamic>.from(
        jsonDecode(jsonEncode(safeArgs)) as Map,
      ),
      summary: action.summary,
    );
    return action;
  }

  @override
  Future<Map<String, Object?>> confirm(AssistantAction action) async {
    final pending = _pending[action.id];
    if (pending == null ||
        pending.toolName != action.toolName ||
        pending.summary != action.summary ||
        !_sameMap(pending.arguments, action.arguments)) {
      return {'success': false, 'error': 'unknown_or_expired_action'};
    }
    final done = _completed[action.id];
    if (done != null) {
      return {...done, 'duplicate': true};
    }
    final marker = _user.collection('assistantActions').doc(action.id);
    try {
      final result = await _db.runTransaction<Map<String, Object?>>((tx) async {
        final markerSnap = await tx.get(marker);
        if (markerSnap.exists) {
          return {
            'success': true,
            'duplicate': true,
            'result': _jsonSafe(markerSnap.data()?['result']),
          };
        }
        if (action.toolName == 'propose_preference_change') {
          final field = action.arguments['field'] as String;
          final userSnap = await tx.get(_user);
          final current = List<String>.from(
            userSnap.data()?[field] ?? const [],
          );
          final before = List<String>.from(action.arguments['before'] as List);
          if (!_sameList(current, before)) {
            return {
              'success': false,
              'error': 'target_changed',
              'current': current,
            };
          }
          final updated = List<String>.from(action.arguments['after'] as List);
          tx.set(_user, {
            field: updated,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          final result = {'success': true, 'field': field, 'values': updated};
          tx.set(marker, {
            'toolName': action.toolName,
            'summary': action.summary,
            'result': result,
            'createdAt': FieldValue.serverTimestamp(),
          });
          return result;
        }
        if (action.toolName == 'propose_food_log') {
          final entryId = action.arguments['entryId'] as String;
          final entry = _user.collection('foodEntries').doc(entryId);
          final existing = await tx.get(entry);
          if (existing.exists) {
            return {'success': false, 'error': 'entry_already_exists'};
          }
          final day = _dateArg(action.arguments['localDate'])!;
          final data = <String, Object?>{
            'name': action.arguments['name'],
            'localDate': Timestamp.fromDate(day),
            'localDay': action.arguments['localDate'],
            'kind': action.arguments['kind'],
            'source': 'assistant',
            'createdAt': FieldValue.serverTimestamp(),
            if (action.arguments['amount'] != null)
              'amount': action.arguments['amount'],
          };
          tx.set(entry, data);
          final result = {
            'success': true,
            'entryId': entryId,
            'entry': {
              'name': action.arguments['name'],
              'localDay': action.arguments['localDate'],
              'kind': action.arguments['kind'],
              'source': 'assistant',
              if (action.arguments['amount'] != null)
                'amount': action.arguments['amount'],
            },
          };
          tx.set(marker, {
            'toolName': action.toolName,
            'summary': action.summary,
            'result': result,
            'createdAt': FieldValue.serverTimestamp(),
          });
          return result;
        }
        return {'success': false, 'error': 'unsupported_action'};
      });
      if (result['success'] == true) {
        _completed[action.id] = Map<String, Object?>.from(result);
        while (_completed.length > 40) {
          final oldest = _completed.keys.first;
          _completed.remove(oldest);
          _pending.remove(oldest);
        }
      }
      return _jsonSafe(result) as Map<String, Object?>;
    } catch (e) {
      return {'success': false, 'error': _errorCode(e)};
    }
  }

  Future<Map<String, List<String>>> _preferences() async {
    final data = (await _user.get()).data() ?? {};
    return {
      for (final key in ['religion', 'dietary', 'health_conditions'])
        key: List<String>.from(data[key] ?? const []),
    };
  }

  String _canonicalPreference(
    String field,
    String value,
    List<String> existing,
  ) {
    if (field == 'health_conditions') {
      for (final c in HealthCondition.conditions) {
        if (c.id == value || c.label.toLowerCase() == value.toLowerCase()) {
          return c.id;
        }
      }
      if (existing.contains(value)) return value;
      throw const FormatException('unknown_health_condition');
    }
    if (field == 'dietary') {
      const values = [
        'Gluten free',
        'Vegetarian',
        'Vegan',
        'Pescatarian',
        'Halal',
        'Kosher',
        'Dairy free',
        'Nut allergy',
      ];
      for (final v in values) {
        if (v.toLowerCase() == value.toLowerCase()) return v;
      }
      if (existing.contains(value)) return value;
      throw const FormatException('unknown_dietary_preference');
    }
    const values = [
      'Christianity',
      'Islam',
      'Judaism',
      'Hinduism',
      'Buddhism',
      'Sikhism',
      'Atheist',
      'Agnostic',
    ];
    for (final v in values) {
      if (v.toLowerCase() == value.toLowerCase()) return v;
    }
    if (existing.contains(value)) return value;
    throw const FormatException('unknown_religion');
  }

  Map<String, Object?> _foodMap(Food food) => {
    'name': food.name,
    'alternatives': {
      for (final e in food.alternatives.entries)
        e.key.id: {for (final p in e.value.entries) p.key.id: p.value},
    },
    'health_conditions': [for (final c in food.healthConditions) c.id],
    'personal_prefs': [for (final p in food.personalPrefs) p.id],
    'local_news': food.localNews,
    'general_info': food.generalInfo,
  };

  Future<({Food? food, Map<String, dynamic>? raw, String source})>
  _getFoodRecord(String name) async {
    final snap = await _db.collection('food').doc(Food.idFor(name)).get();
    final data = snap.data();
    return (
      food: data == null ? null : Food.fromMap(data),
      raw: data,
      source: 'food/${snap.id}',
    );
  }

  static String _requiredString(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v is! String || v.trim().isEmpty) throw FormatException('invalid_$key');
    return v.trim();
  }

  static int _boundedInt(
    Object? value, {
    required int fallback,
    required int max,
  }) => value is int ? value.clamp(1, max) : fallback;
  static DateTime? _dateArg(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('invalid_date');
    }
    final date = DateTime.tryParse(value);
    if (date == null || _dateId(date) != value) {
      throw const FormatException('invalid_date');
    }
    return DateTime.utc(date.year, date.month, date.day);
  }

  static String _dateId(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static String _randomId() => List<int>.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  static bool _sameList(List a, List b) =>
      a.length == b.length &&
      a.asMap().entries.every((e) => e.value == b[e.key]);
  static bool _sameMap(Map a, Map b) =>
      a.length == b.length &&
      a.entries.every(
        (e) => _jsonSafe(e.value).toString() == _jsonSafe(b[e.key]).toString(),
      );
  static String _errorCode(Object e) => e is FirebaseException
      ? e.code
      : e is FormatException
      ? e.message
      : 'source_unavailable';

  static Object? _jsonSafe(Object? value) => switch (value) {
    Timestamp t => t.toDate().toUtc().toIso8601String(),
    DateTime d => d.toUtc().toIso8601String(),
    Map m => {
      for (final e in m.entries)
        if (e.key is String) e.key as String: _jsonSafe(e.value),
    },
    Iterable l => [for (final e in l) _jsonSafe(e)],
    GeoPoint _ => null,
    DocumentReference _ => null,
    FieldValue _ => null,
    num n when !n.isFinite => null,
    _ => value,
  };
}
