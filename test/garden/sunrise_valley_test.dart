import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hackathon/garden/sunrise_valley.dart';

const _day = ValleyClock.dayLength;
const _seasonLength = _day * ValleyClock.daysPerSeason;

void main() {
  group('ValleySeason.of', () {
    test('maps months to meteorological seasons', () {
      expect(ValleySeason.of(DateTime(2026, 4, 1)), ValleySeason.spring);
      expect(ValleySeason.of(DateTime(2026, 7, 1)), ValleySeason.summer);
      expect(ValleySeason.of(DateTime(2026, 11, 8)), ValleySeason.autumn);
      expect(ValleySeason.of(DateTime(2026, 1, 15)), ValleySeason.winter);
      expect(ValleySeason.of(DateTime(2026, 12, 1)), ValleySeason.winter);
    });
  });

  group('ValleyClock', () {
    test('starts each season just after sunrise', () {
      for (final season in ValleySeason.values) {
        final clock = ValleyClock(ValleyClock.sunriseOf(season));
        expect(clock.currentSeason, season);
        expect(clock.sunHeight, inInclusiveRange(0.0, 0.3));
      }
    });

    test('runs the sun up by day and below the horizon at night', () {
      const noon = ValleyClock(_day * ValleyClock.daylightShare / 2);
      const midnight =
          ValleyClock(_day * (1 + ValleyClock.daylightShare) / 2);
      expect(noon.sunHeight, closeTo(1, 1e-9));
      expect(midnight.sunHeight, closeTo(-1, 1e-9));
    });

    test('holds a season through the day, then turns overnight', () {
      // Whole spring from sunrise until dusk on its last day.
      final lastDusk =
          _seasonLength - _day + _day * ValleyClock.daylightShare;
      for (var t = 0.0; t <= lastDusk; t += _day / 8) {
        expect(ValleyClock(t).season, 0);
      }
      // Mid-blend in the dark.
      final midnight = ValleyClock(
        _seasonLength - _day * (1 - ValleyClock.daylightShare) / 2,
      );
      expect(midnight.season, inExclusiveRange(0.0, 1.0));
      expect(midnight.sunHeight, lessThan(0));
      // Fully summer by the next sunrise.
      expect(ValleyClock(_seasonLength - 1).season, closeTo(1, 1e-9));
      expect(ValleyClock(ValleyClock.sunriseOf(ValleySeason.summer)).season, 1);
    });

    test('wraps from winter back to spring', () {
      expect(ValleyClock(_seasonLength * 4 + 1).season, closeTo(0, 1e-9));
      expect(ValleyClock(_seasonLength * 4 - 1).season, closeTo(0, 1e-9));
    });
  });

  testWidgets('paints a whole year of days and nights without errors',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SunriseValley(progress: 0.7, startSeason: ValleySeason.spring),
      ),
    );
    // Step through every season at several times of day.
    for (var t = 0.0; t < _seasonLength * 4; t += _day / 5) {
      await tester.pump(const Duration(milliseconds: 9600));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('stops animating when the platform asks for reduced motion',
      (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SunriseValley(progress: 0.5),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('animates by default', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(),
        child: SunriseValley(progress: 0.5),
      ),
    );
    expect(tester.hasRunningAnimations, isTrue);
  });
}
