import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/scan/frame_gate.dart';

const _size = 96;

/// A flat grey frame, like a blank wall.
Uint8List _blank() =>
    Uint8List(_size * _size)..fillRange(0, _size * _size, 120);

/// A uniform frame of brightness [luma], e.g. a lens in a pocket.
Uint8List _flat(int luma) =>
    Uint8List(_size * _size)..fillRange(0, _size * _size, luma);

/// A checkerboard in the centre, like a labelled item, shifted by [offset].
Uint8List _item({int offset = 0, int squares = 8}) {
  final bytes = _blank();
  for (var y = _size ~/ 4; y < _size * 3 ~/ 4; y++) {
    for (var x = _size ~/ 4; x < _size * 3 ~/ 4; x++) {
      final cell = _size ~/ squares;
      final dark = (((x + offset) ~/ cell) + (y ~/ cell)).isEven;
      bytes[y * _size + x] = dark ? 30 : 220;
    }
  }
  return bytes;
}

void main() {
  late FrameGate gate;
  var time = Duration.zero;

  GateStatus feed(Uint8List frame) {
    time += const Duration(milliseconds: 100);
    return gate.addFrame(
      frame,
      width: _size,
      height: _size,
      rowStride: _size,
      timestamp: time,
    );
  }

  /// Feeds [frame] for [ms] milliseconds and returns every state seen.
  List<GateState> hold(Uint8List frame, int ms) => [
    for (var i = 0; i < ms ~/ 100; i++) feed(frame).state,
  ];

  setUp(() {
    gate = FrameGate();
    time = Duration.zero;
  });

  test('a steady item is sent once after a second', () {
    final states = hold(_item(), 1500);
    expect(states.where((s) => s == GateState.ready), hasLength(1));
    expect(states.indexOf(GateState.ready), greaterThanOrEqualTo(10));
    final after = hold(_item(), 8000);
    expect(after, isNot(contains(GateState.ready)));
    expect(after.first, GateState.coolingDown);
    expect(after.last, GateState.alreadySent);
  });

  test('a blank scene is never sent', () {
    expect(hold(_blank(), 3000), isNot(contains(GateState.ready)));
    expect(feed(_blank()).state, GateState.noItem);
  });

  test('a moving camera is never sent', () {
    final states = [
      for (var i = 0; i < 30; i++) feed(_item(offset: i * 6)).state,
    ];
    expect(states, isNot(contains(GateState.ready)));
    expect(states.last, GateState.moving);
  });

  test('a brightness change alone does not count as motion', () {
    hold(_item(), 500);
    final brighter = Uint8List.fromList([for (final b in _item()) b + 20]);
    expect(feed(brighter).state, GateState.holding);
  });

  test('a new item is sent after the previous one', () {
    hold(_item(), 1500);
    hold(_blank(), 5000);
    final states = hold(_item(squares: 4), 1500);
    expect(states, contains(GateState.ready));
  });

  test('the same item is sent again after it was taken away', () {
    hold(_item(), 1500);
    hold(_blank(), 5000);
    expect(hold(_item(), 1500), contains(GateState.ready));
  });

  test('a dark lens counts as in a pocket and is never sent', () {
    final states = hold(_flat(5), 3000);
    expect(states, isNot(contains(GateState.ready)));
    expect(states.last, GateState.inPocket);
  });

  test('a dim, featureless lens counts as in a pocket', () {
    hold(_flat(40), 300);
    expect(feed(_flat(40)).state, GateState.inPocket);
  });

  test('nothing is sent during the cooldown', () {
    hold(_item(), 1500);
    hold(_blank(), 1000);
    final states = hold(_item(squares: 4), 3000);
    expect(states.first, GateState.coolingDown);
    expect(states, isNot(contains(GateState.ready)));
    // Once the cooldown is over, the new item goes through.
    expect(hold(_item(squares: 4), 2000), contains(GateState.ready));
  });

  test('startCooldown restarts the cooldown', () {
    hold(_item(), 1500);
    hold(_blank(), 4000);
    gate.startCooldown(time);
    expect(hold(_item(squares: 4), 4000), isNot(contains(GateState.ready)));
  });
}
