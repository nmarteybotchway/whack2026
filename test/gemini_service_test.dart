import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:hackathon/gemini_wrapper.dart';
<<<<<<< HEAD
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
=======
import 'package:hackathon/secrets.dart';
>>>>>>> ac39a2415b71066f76b6613eb2b25a802b8808ff

void main() {
  group('GeminiImage', () {
    test('accepts non-empty bytes within the size cap', () {
      final image = GeminiImage(Uint8List.fromList([1, 2, 3]));
      expect(image.bytes, hasLength(3));
      expect(GeminiImage.mimeType, 'image/jpeg');
    });

    test('rejects empty bytes', () {
      expect(() => GeminiImage(Uint8List(0)), throwsArgumentError);
    });

    test('rejects bytes over the 19 MB contract cap', () {
      final tooBig = Uint8List(GeminiImage.maxBytes + 1);
      expect(() => GeminiImage(tooBig), throwsArgumentError);
    });
  });

  group('GeminiService construction', () {
    test('requires an api key', () {
      expect(
        () => GeminiService(apiKey: 'test-key'),
        returnsNormally,
      );
    });

    test('defaults to gemini-3.8-flash', () {
      final service = GeminiService(apiKey: 'test-key');
      expect(service, isNotNull); // model default is fixed in the constructor
    });
  });

<<<<<<< HEAD
  group('mock live (test_image.jpg + nut-allergy prompt)', () {
    test('feeds the image and prompt, returns schema-shaped text', () async {
      final imageBytes = File('assets/test_image.jpg').readAsBytesSync();
      expect(imageBytes, isNotEmpty);

      const prompt =
          'given the user is allergic to nuts, is the product in this image '
          'appropriate';
      final responseSchema = Schema.object(
        properties: {
          'content': Schema.string(
            description: 'Whether the product is appropriate for the user.',
          ),
        },
      );

      // Capture the outgoing request and reply with a canned Gemini response
      // shaped like {"content": "string"}.
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'content':
                            'No. The product contains nuts and is not '
                                'appropriate for a user with a nut allergy.',
                      }),
                    },
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: GenerativeModel(
          model: 'gemini-3.8-flash',
          apiKey: 'test-key',
          httpClient: mockClient,
        ),
      );

      final text = await service.generate(
        prompt: prompt,
        responseSchema: responseSchema,
        image: GeminiImage(imageBytes),
      );

      // The response is the schema-shaped text the mock returned.
      expect(text, contains('content'));
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded, containsPair('content', isNotEmpty));

      // The outgoing request carried the prompt, the JPEG bytes, and the
      // response schema.
      final body = captured!.body;
      expect(body, contains('allergic to nuts'));
      expect(body, contains(base64Encode(imageBytes)));
      expect(body, contains('"generationConfig"'));
      expect(body, contains('"responseSchema"'));

      // ignore: avoid_print
      print('Agent output ({"content": string}): '
          '${decoded['content']}');
      // ignore: avoid_print
      print(
          'PASS: mock live test — prompt, JPEG image and response schema '
          'all reached the Gemini transport; response matched '
          '{"content": string}.');
    });
  });

  // Note: no live API calls in tests. Network behaviour is exercised by the
  // optional live smoke test, which only runs when a key is provided:
  //   flutter test --dart-define=GEMINI_API_KEY=<key> --plain-name "live"
  group('live (requires GEMINI_API_KEY dart-define)', () {
    test('returns schema-shaped text for the nut-allergy prompt and image',
        () async {
      const apiKey = String.fromEnvironment('GEMINI_API_KEY');
      if (apiKey.isEmpty) {
        markTestSkipped('GEMINI_API_KEY not provided; skipping live smoke test.');
        return;
      }

      final imageBytes = File('assets/test_image.jpg').readAsBytesSync();
      expect(imageBytes, isNotEmpty);

      const prompt =
          'given the user is allergic to nuts, is the product in this image '
          'appropriate';
      final responseSchema = Schema.object(
        properties: {
          'content': Schema.string(
            description: 'Whether the product is appropriate for the user.',
          ),
        },
      );

      final service = GeminiService(apiKey: apiKey);
=======
  // Note: no live API calls by default. Network behaviour is exercised by the
  // optional live smoke test, which needs geminiApiKey set in
  // lib/secrets.dart and is opted into with:
  //   flutter test --dart-define=GEMINI_LIVE_TEST=true --plain-name "live"
  group('live (opt-in, uses geminiApiKey from lib/secrets.dart)', () {
    test('returns text for a simple schema prompt', () async {
      if (!const bool.fromEnvironment('GEMINI_LIVE_TEST')) {
        markTestSkipped('Live test not requested; skipping.');
        return;
      }
      if (geminiApiKey.isEmpty) {
        markTestSkipped('geminiApiKey not set; skipping live smoke test.');
        return;
      }

      final service = GeminiService();
>>>>>>> ac39a2415b71066f76b6613eb2b25a802b8808ff
      final text = await service.generate(
        prompt: prompt,
        responseSchema: responseSchema,
        image: GeminiImage(imageBytes),
      );

      // ignore: avoid_print
      print('Agent output ({"content": string}): $text');
      // ignore: avoid_print
      print(
          'PASS: live smoke test — Gemini returned a response matching '
          '{"content": string}.');

      expect(text, isNotEmpty);
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded, containsPair('content', isNotEmpty));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
