import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/services/speech_chunks.dart';

void main() {
  test('long reply has short opening chunk and keeps every word in order', () {
    final text = List.filled(50, 'a useful ingredient').join(' ');
    final chunks = speechChunks(text);
    expect(chunks.first.length, lessThanOrEqualTo(80));
    expect(chunks.join(' '), text);
    expect(chunks.skip(1).every((chunk) => chunk.length <= 180), isTrue);
  });
  test('short sentence and punctuation are preserved', () {
    expect(speechChunks('  This is suitable.  '), ['This is suitable.']);
    expect(speechChunks('  '), isEmpty);
  });
}
