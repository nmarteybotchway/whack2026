/// Read-only, bounded inspection of Firestore food_images documents.
///
/// Usage: dart run tool/inspect_food_images.dart [limit]
/// Defaults to four documents; output redacts URL query strings.
/// Firestore access is read-only. Unless FIREBASE_ID_TOKEN is provided, the
/// script signs in anonymously, which creates/uses a Firebase Auth account.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _projectId = 'whack-2026-c7898';
const _apiKey = 'AIzaSyBGFZM5Y9raZrSJZGjoHlTDTZB7ytYKWSQ';
const _timeout = Duration(seconds: 30);

Future<void> main(List<String> args) async {
  final limit = args.isEmpty ? 4 : int.tryParse(args.first);
  if (limit == null || limit < 1 || limit > 10) {
    stderr.writeln('Limit must be between 1 and 10.');
    exitCode = 64;
    return;
  }
  try {
    final auth = await _Auth.signIn();
    final uri = Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$_projectId/databases/(default)/documents/food_images',
      {'pageSize': '$limit'},
    );
    final response = await http
        .get(uri, headers: auth.headers)
        .timeout(_timeout);
    if (response.statusCode != 200) {
      stderr.writeln('Firestore read failed (${response.statusCode}).');
      exitCode = 1;
      return;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final docs = body['documents'] as List? ?? const [];
    stdout.writeln(
      'Project: $_projectId; collection: food_images; returned: ${docs.length} (limit $limit)',
    );
    for (final raw in docs) {
      final doc = raw as Map<String, dynamic>;
      final name = doc['name'] as String;
      final id = name.substring(name.lastIndexOf('/') + 1);
      final fields = doc['fields'] as Map<String, dynamic>? ?? const {};
      stdout.writeln('documentId: $id');
      for (final entry in fields.entries) {
        final value = _value(entry.value as Map<String, dynamic>);
        stdout.writeln('  ${entry.key}: ${_safe(value)}');
      }
    }
  } on SocketException {
    stderr.writeln('Network unavailable while reading Firestore.');
    exitCode = 1;
  } on HttpException catch (e) {
    stderr.writeln('Firebase Auth failed: ${e.message}');
    exitCode = 1;
  } catch (e) {
    stderr.writeln('Inspection failed (${e.runtimeType}).');
    exitCode = 1;
  }
}

Object? _value(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('integerValue')) return v['integerValue'];
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('timestampValue')) return v['timestampValue'];
  if (v['nullValue'] != null) return null;
  if (v['arrayValue'] case final Map a) {
    return [
      for (final x in (a['values'] as List? ?? const []))
        _value(x as Map<String, dynamic>),
    ];
  }
  if (v['mapValue'] case final Map m) {
    return {
      for (final e in (m['fields'] as Map? ?? const {}).entries)
        e.key: _value(e.value as Map<String, dynamic>),
    };
  }
  return '<other Firestore value>';
}

Object? _safe(Object? value) => switch (value) {
  String s when Uri.tryParse(s)?.hasScheme == true => _redactUrl(s),
  String s => s.length > 160 ? '${s.substring(0, 160)}…' : s,
  List l => [for (final x in l) _safe(x)],
  Map m => {for (final e in m.entries) e.key: _safe(e.value)},
  _ => value,
};

String _redactUrl(String s) {
  final uri = Uri.tryParse(s);
  if (uri == null) return '<URL redacted>';
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

class _Auth {
  _Auth(this._token);
  final String _token;

  static Future<_Auth> signIn() async {
    final existingToken = Platform.environment['FIREBASE_ID_TOKEN'];
    if (existingToken != null && existingToken.isNotEmpty) {
      return _Auth(existingToken);
    }
    final r = await http
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'returnSecureToken': true}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) throw HttpException('${r.statusCode}');
    return _Auth(
      (jsonDecode(r.body) as Map<String, dynamic>)['idToken'] as String,
    );
  }

  Map<String, String> get headers => {
    'Authorization': 'Bearer $_token',
    'Content-Type': 'application/json',
  };
}
