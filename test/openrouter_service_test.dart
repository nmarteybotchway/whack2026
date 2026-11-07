import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/openrouter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _reply(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content},
      },
    ],
  }),
  200,
);

void main() {
  group('OpenRouterImage', () {
    test('encodes bytes as a JPEG data URL', () {
      final image = OpenRouterImage(Uint8List.fromList([1, 2, 3]));
      expect(image.dataUrl, 'data:image/jpeg;base64,AQID');
    });

    test('rejects empty bytes', () {
      expect(() => OpenRouterImage(Uint8List(0)), throwsArgumentError);
    });

    test('rejects bytes over the size cap', () {
      final tooBig = Uint8List(OpenRouterImage.maxBytes + 1);
      expect(() => OpenRouterImage(tooBig), throwsArgumentError);
    });
  });

  group('OpenRouterService', () {
    test('sends the prompt, image and schema to the preset', () async {
      late http.Request sent;
      final service = OpenRouterService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          sent = request;
          return _reply('{"answer":"hi"}');
        }),
      );

      final text = await service.generate(
        prompt: 'Say hi',
        image: OpenRouterImage(Uint8List.fromList([1, 2, 3])),
        responseSchema: {
          'type': 'object',
          'properties': {
            'answer': {'type': 'string'},
          },
        },
      );

      expect(text, '{"answer":"hi"}');
      expect(sent.headers['Authorization'], 'Bearer test-key');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['model'], '@preset/glm-flash');
      expect(body['provider']['require_parameters'], isTrue);
      final content = body['messages'][0]['content'] as List;
      expect(content[0], {'type': 'text', 'text': 'Say hi'});
      expect(content[1]['image_url']['url'], 'data:image/jpeg;base64,AQID');
      expect(body['response_format']['type'], 'json_schema');
    });

    test('sends a plain prompt without a response format', () async {
      late Map<String, dynamic> body;
      final service = OpenRouterService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return _reply('hello');
        }),
      );

      expect(await service.generate(prompt: 'Say hi'), 'hello');
      expect(body['messages'][0]['content'], 'Say hi');
      expect(body.containsKey('provider'), isFalse);
      expect(body.containsKey('response_format'), isFalse);
    });

    test('throws OpenRouterException on an API error', () async {
      final service = OpenRouterService(
        apiKey: 'bad-key',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 401, 'message': 'No auth credentials found'},
            }),
            401,
          ),
        ),
      );

      expect(
        service.generate(prompt: 'Say hi'),
        throwsA(
          isA<OpenRouterException>().having((e) => e.statusCode, 'code', 401),
        ),
      );
    });
  });

  // Hits the real API with openRouterApiKey from lib/secrets.dart. Opt in with:
  //   flutter test --dart-define=OPENROUTER_LIVE_TEST=true --plain-name live
  test('live: preset answers a schema prompt', () async {
    if (!const bool.fromEnvironment('OPENROUTER_LIVE_TEST')) {
      markTestSkipped('Live test not requested; skipping.');
      return;
    }
    final service = OpenRouterService();
    final text = await service.generate(
      prompt: 'Reply with a one-word greeting in the answer field.',
      responseSchema: {
        'type': 'object',
        'properties': {
          'answer': {'type': 'string'},
        },
        'required': ['answer'],
        'additionalProperties': false,
      },
    );
    service.close();
    expect(jsonDecode(text), contains('answer'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  // Opt in with a JPEG to describe:
  //   flutter test --dart-define=OPENROUTER_LIVE_TEST=true \
  //     --dart-define=OPENROUTER_LIVE_IMAGE=/path/to/photo.jpg --plain-name live
  test('live: preset describes an image', () async {
    const path = String.fromEnvironment('OPENROUTER_LIVE_IMAGE');
    if (!const bool.fromEnvironment('OPENROUTER_LIVE_TEST') || path.isEmpty) {
      markTestSkipped('Live image test not requested; skipping.');
      return;
    }
    final service = OpenRouterService();
    final text = await service.generate(
      prompt: 'What is the main object in this photo? Describe it briefly.',
      image: OpenRouterImage(File(path).readAsBytesSync()),
      responseSchema: {
        'type': 'object',
        'properties': {
          'object': {'type': 'string'},
          'description': {'type': 'string'},
        },
        'required': ['object', 'description'],
        'additionalProperties': false,
      },
    );
    service.close();
    // ignore: avoid_print
    print('Image answer: $text');
    expect(jsonDecode(text), contains('object'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
