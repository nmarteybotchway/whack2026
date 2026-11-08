import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/assistant/message_spans.dart';

void main() {
  test('paired markers become bold spans', () {
    final spans = messageSpans('Try **Oats** instead.');
    expect(spans.map((s) => s.text).join(), 'Try Oats instead.');
    expect(spans[1].style?.fontWeight, FontWeight.w700);
    expect(spans[0].style, isNull);
  });

  test('an unpaired marker stays literal', () {
    final spans = messageSpans('Pick **Oats** or **Rice');
    expect(spans.map((s) => s.text).join(), 'Pick Oats or **Rice');
    expect(spans.last.style, isNull);
  });
}
