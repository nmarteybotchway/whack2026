/// Shared plumbing for the `tool/*_food*.dart` scripts.
///
/// These scripts are plain Dart (the `cloud_firestore` plugin needs Flutter),
/// so they talk to Firestore over REST, signed in anonymously like the app's
/// guest flow. Anonymous sign-in must be enabled and `firestore.rules`
/// deployed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:hackathon/food/food.dart';
import 'package:hackathon/openrouter.dart';
import 'package:http/http.dart' as http;

// Web app config from lib/firebase_options.dart (which imports Flutter, so it
// cannot be used here). Firebase API keys identify the project; they are not
// secrets.
const _apiKey = 'AIzaSyBGFZM5Y9raZrSJZGjoHlTDTZB7ytYKWSQ';
const _projectId = 'whack-2026-c7898';
const _databasePath = 'projects/$_projectId/databases/(default)';
const _documentsUrl =
    'https://firestore.googleapis.com/v1/$_databasePath/documents';

/// Per-request limit so one stalled call fails instead of hanging a run.
const _httpTimeout = Duration(seconds: 30);

/// The Firestore `food` collection, accessed over REST.
class FoodStore {
  FoodStore._(this._auth);

  final _Auth _auth;

  static Future<FoodStore> signIn() async => FoodStore._(await _Auth.signIn());

  Future<bool> exists(String id) async {
    final response = await http
        .get(
          Uri.parse('$_documentsUrl/food/${Uri.encodeComponent(id)}'),
          headers: await _auth.headers(),
        )
        .timeout(_httpTimeout);
    if (response.statusCode == 404) return false;
    _check(response);
    return true;
  }

  /// Every stored food, keyed by document ID.
  Future<Map<String, Food>> all() async {
    final foods = <String, Food>{};
    String? pageToken;
    do {
      final response = await http
          .get(
            Uri.parse('$_documentsUrl/food').replace(
              queryParameters: {'pageSize': '300', 'pageToken': ?pageToken},
            ),
            headers: await _auth.headers(),
          )
          .timeout(_httpTimeout);
      _check(response);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      for (final doc in (body['documents'] as List? ?? const [])) {
        final name = doc['name'] as String;
        final fields = (doc['fields'] as Map<String, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(k, _decode(v as Map<String, dynamic>)),
        );
        foods[name.substring(name.lastIndexOf('/') + 1)] = Food.fromMap(fields);
      }
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null);
    return foods;
  }

  /// Writes [fields] to `food/{id}` and stamps `updatedAt` with server time.
  ///
  /// With [create] the document must not exist yet; otherwise only [fields]
  /// are changed on the existing document.
  Future<void> write(
    String id,
    Map<String, dynamic> fields, {
    required bool create,
  }) => _commit([
    {
      ..._update(id, fields),
      if (!create) 'updateMask': {'fieldPaths': fields.keys.toList()},
      'currentDocument': {'exists': !create},
    },
  ]);

  /// Atomically replaces `food/{food.id}` with [food] and deletes [remove].
  Future<void> replace(Food food, Iterable<String> remove) => _commit([
    _update(food.id, food.toMap()),
    for (final id in remove)
      if (id != food.id) {'delete': '$_databasePath/documents/food/$id'},
  ]);

  Map<String, dynamic> _update(String id, Map<String, dynamic> fields) => {
    'update': {
      'name': '$_databasePath/documents/food/$id',
      'fields': fields.map((k, v) => MapEntry(k, _encode(v))),
    },
    'updateTransforms': [
      {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
    ],
  };

  Future<void> _commit(List<Map<String, dynamic>> writes) async {
    final response = await http
        .post(
          Uri.parse('$_documentsUrl:commit'),
          headers: await _auth.headers(),
          body: jsonEncode({'writes': writes}),
        )
        .timeout(_httpTimeout);
    _check(response);
  }
}

/// Asks OpenRouter for a JSON object matching [schema].
Future<Map<String, dynamic>> askJson(
  OpenRouterService ai,
  String prompt,
  Map<String, Object?> schema, {
  bool webSearch = false,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final text = await ai.generate(
    prompt: prompt,
    responseSchema: schema,
    webSearch: webSearch,
    timeout: timeout,
  );
  return _extractJson(text, schema);
}

/// Finds the JSON object matching [schema] in a model reply.
///
/// Models sometimes ignore the JSON response format and surround the JSON
/// with prose (often containing markdown links, empty code fences or other
/// braces), so fenced blocks are tried first, then every bracketed span of
/// the whole reply, until one parses and has the schema's required keys.
Map<String, dynamic> _extractJson(String text, Map<String, Object?> schema) {
  final required = [...?(schema['required'] as List?)];
  final properties = schema['properties'] as Map<String, Object?>;
  Map<String, dynamic>? match(Object? json) => switch (json) {
    Map<String, dynamic> m when required.every(m.containsKey) => m,
    // A bare list for a schema whose only property is a list, e.g. `[]` for
    // `{"groups": []}`.
    List l
        when properties.length == 1 &&
            (properties.values.single as Map?)?['type'] == 'array' =>
      {properties.keys.single: l},
    _ => null,
  };

  final fences = RegExp(r'```(?:json)?\s*([\s\S]*?)```').allMatches(text);
  for (final candidate in [...fences.map((m) => m.group(1)!), text]) {
    for (final (open, close) in [('{', '}'), ('[', ']')]) {
      for (
        var start = candidate.indexOf(open);
        start >= 0;
        start = candidate.indexOf(open, start + 1)
      ) {
        for (
          var end = candidate.lastIndexOf(close);
          end > start;
          end = candidate.lastIndexOf(close, end - 1)
        ) {
          try {
            if (match(jsonDecode(candidate.substring(start, end + 1)))
                case final json?) {
              return json;
            }
          } on FormatException {
            // Not JSON over this span; try a shorter one.
          }
        }
      }
    }
  }
  throw FormatException('No JSON matching the schema in reply', text);
}

/// Encodes a string or list of strings as a Firestore REST value.
Map<String, dynamic> _encode(Object? v) => switch (v) {
  String s => {'stringValue': s},
  List l => {
    'arrayValue': {'values': l.map(_encode).toList()},
  },
  _ => throw ArgumentError('Unsupported Firestore value: $v'),
};

/// Decodes the Firestore REST values a food uses; others (such as
/// `updatedAt`) become null, which [Food.fromMap] ignores.
Object? _decode(Map<String, dynamic> v) => switch (v) {
  {'stringValue': String s} => s,
  {'arrayValue': Map a} => [
    for (final e in (a['values'] as List? ?? const []))
      _decode(e as Map<String, dynamic>),
  ],
  _ => null,
};

void _check(http.Response response) {
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode} ${response.body}');
  }
}

/// An anonymous Firebase Auth session whose ID token is refreshed before it
/// expires (tokens last an hour).
class _Auth {
  _Auth._(this._idToken, this._refreshToken, this._expires);

  String _idToken;
  String _refreshToken;
  DateTime _expires;

  static Future<_Auth> signIn() async {
    final body = await _post(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey',
      {'returnSecureToken': true},
    );
    return _Auth._(
      body['idToken'] as String,
      body['refreshToken'] as String,
      _expiry(body['expiresIn']),
    );
  }

  Future<Map<String, String>> headers() async {
    if (DateTime.now().isAfter(_expires)) {
      final body = await _post(
        'https://securetoken.googleapis.com/v1/token?key=$_apiKey',
        {'grant_type': 'refresh_token', 'refresh_token': _refreshToken},
      );
      _idToken = body['id_token'] as String;
      _refreshToken = body['refresh_token'] as String;
      _expires = _expiry(body['expires_in']);
    }
    return {
      'Authorization': 'Bearer $_idToken',
      'Content-Type': 'application/json',
    };
  }

  /// Refreshes five minutes early to leave room for slow requests.
  static DateTime _expiry(Object? seconds) =>
      DateTime.now().add(Duration(seconds: int.parse(seconds as String) - 300));

  static Future<Map<String, dynamic>> _post(
    String url,
    Map<String, Object> body,
  ) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_httpTimeout);
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
