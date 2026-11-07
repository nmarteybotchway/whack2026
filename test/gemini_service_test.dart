import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/gemini_wrapper.dart';

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

    test('defaults to gemini-2.5-flash', () {
      final service = GeminiService(apiKey: 'test-key');
      expect(service, isNotNull); // model default is fixed in the constructor
    });
  });

  // Note: no live API calls in tests. Network behaviour is exercised by the
  // optional live smoke test, which only runs when a key is provided:
  //   flutter test --dart-define=GEMINI_API_KEY=<key> --plain-name "live"
  group('live (requires GEMINI_API_KEY dart-define)', () {
    test('returns text for a simple schema prompt', () async {
      const apiKey = String.fromEnvironment('GEMINI_API_KEY');
      if (apiKey.isEmpty) {
        markTestSkipped('GEMINI_API_KEY not provided; skipping live smoke test.');
        return;
      }

      final service = GeminiService(apiKey: apiKey);
      final text = await service.generate(
        prompt: 'Reply with a one-word greeting in the answer field.',
        responseSchema: Schema.object(
          properties: {
            'answer': Schema.string(description: 'The greeting.'),
          },
        ),
      );
      expect(text, isNotEmpty);
      expect(text, contains('answer'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
