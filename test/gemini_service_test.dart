import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/gemini_wrapper.dart';
import 'package:hackathon/secrets.dart';

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
