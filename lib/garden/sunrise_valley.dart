import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The animated river valley behind the home tab.
///
/// Layered ridges wrapped in mist bands stand above a meadow, and a river
/// winds from the horizon toward the viewer in an S-curve, widening as it
/// comes near. The scene runs a day/night cycle ([ValleyClock.dayLength]):
/// the sun arcs across the sky, then a moon and stars come out. Every
/// [ValleyClock.daysPerSeason] day/night cycles the season turns, blending
/// overnight so each morning opens on the next one. Clouds drift, trees and grass sway in the wind, and
/// light flows down the water.
///
/// [progress] (0.0-1.0) drives lushness: sparse saplings at 0, a full valley
/// at 1. The animation stops when the platform asks for reduced motion.
class SunriseValley extends StatefulWidget {
  const SunriseValley({
    super.key,
    required this.progress,
    this.startSeason,
    this.animate = true,
    this.onDayNightChanged,
  });

  /// 0.0 - 1.0; growth / lushness of the scene.
  final double progress;

  /// Season shown first, at sunrise; defaults to today's real season.
  final ValleySeason? startSeason;

  /// False freezes the scene at its start (sunrise in [startSeason]).
  final bool animate;

  /// Called whenever the sun crosses the horizon: true at sunrise, false at
  /// sunset. Lets overlays match their colors to the sky.
  final ValueChanged<bool>? onDayNightChanged;

  @override
  State<SunriseValley> createState() => _SunriseValleyState();
}

class _SunriseValleyState extends State<SunriseValley>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Scene time in seconds; the painter repaints whenever it changes.
  late final ValueNotifier<double> _seconds;

  /// Scene time when the ticker last started; [Ticker] restarts its elapsed
  /// time at zero, so this keeps the clock from jumping back.
  late double _base;

  /// Last known day/night state, so [SunriseValley.onDayNightChanged] fires
  /// only when the sun actually crosses the horizon.
  bool _lastDay = true;

  @override
  void initState() {
    super.initState();
    _base = ValleyClock.sunriseOf(
      widget.startSeason ?? ValleySeason.of(DateTime.now()),
    );
    _seconds = ValueNotifier(_base);
    _lastDay = _clockAt(_base).sunHeight >= 0;
    _ticker = createTicker((elapsed) {
      final seconds = _base + elapsed.inMicroseconds / 1e6;
      _seconds.value = seconds;
      final day = _clockAt(seconds).sunHeight >= 0;
      if (day != _lastDay) {
        _lastDay = day;
        widget.onDayNightChanged?.call(day);
      }
    });
  }

  ValleyClock _clockAt(double seconds) => ValleyClock(seconds);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(SunriseValley oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final run = widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) {
      _base = _seconds.value;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ValleyPainter(
              progress: widget.progress.clamp(0.0, 1.0),
              seconds: _seconds,
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Time: day/night cycle and seasons
// ---------------------------------------------------------------------------

enum ValleySeason {
  spring,
  summer,
  autumn,
  winter;

  /// The (northern hemisphere) meteorological season [date] falls in.
  static ValleySeason of(DateTime date) => switch (date.month) {
    3 || 4 || 5 => spring,
    6 || 7 || 8 => summer,
    9 || 10 || 11 => autumn,
    _ => winter,
  };
}

/// Where the valley is in its day and its year at [seconds] of scene time.
class ValleyClock {
  const ValleyClock(this.seconds);

  final double seconds;

  /// Seconds per full day/night cycle.
  static const dayLength = 48.0;

  /// Share of each cycle the sun is up; the rest is night.
  static const daylightShare = 0.65;

  /// Day/night cycles per season.
  static const daysPerSeason = 1;

  /// Scene time just after sunrise on the first day of [season].
  static double sunriseOf(ValleySeason season) =>
      (season.index * daysPerSeason + 0.04) * dayLength;

  /// 0..1 through the current cycle; 0 is sunrise.
  double get dayPhase => _fract(seconds / dayLength);

  /// The sun's angle along its arc: 0 at sunrise, pi at sunset, 2 pi at the
  /// next sunrise. Daylight takes [daylightShare] of the cycle.
  double get sunAngle {
    final p = dayPhase;
    return p < daylightShare
        ? math.pi * p / daylightShare
        : math.pi + math.pi * (p - daylightShare) / (1 - daylightShare);
  }

  /// Sun height: 1 at noon, 0 on the horizon, -1 at midnight.
  double get sunHeight => math.sin(sunAngle);

  /// Continuous season: 0 spring, 1 summer, 2 autumn, 3 winter, wrapping
  /// at 4. Holds each whole season through its days, then blends into the
  /// next during the night that ends its last day.
  double get season {
    final position = seconds / (dayLength * daysPerSeason);
    final whole = position.floorToDouble();
    // The last night of the season, as a share of the whole season. The
    // blend starts after dusk and finishes before the next sunrise.
    final dusk = (daysPerSeason - 1 + daylightShare) / daysPerSeason;
    final night = (1 - daylightShare) / daysPerSeason;
    final blend = _smoothstep(dusk + 0.15 * night, dusk + 0.85 * night,
        position - whole);
    return (whole + blend) % 4;
  }

  /// The season [season] is mostly in.
  ValleySeason get currentSeason =>
      ValleySeason.values[season.round() % ValleySeason.values.length];
}

double _fract(double x) => x - x.floorToDouble();

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Stable 0..1 noise for an integer seed. Animated details use this rather
/// than a shared [math.Random] so the static layout never shifts as
/// particles or seasons come and go.
double _hash(int n) {
  var x = (n * 374761393 + 668265263) & 0x7fffffff;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
  return (x ^ (x >> 16)) % 10007 / 10006;
}

/// Multiplies [c]'s color channels by [tint]'s, keeping [c]'s alpha.
Color _modulate(Color c, Color tint) => Color.from(
  alpha: c.a,
  red: c.r * tint.r,
  green: c.g * tint.g,
  blue: c.b * tint.b,
);

/// Pulls [c] toward its own gray by [amount].
Color _dull(Color c, double amount) {
  final g = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
  return Color.lerp(c, Color.from(alpha: c.a, red: g, green: g, blue: g),
      amount)!;
}

// ---------------------------------------------------------------------------
// Palettes
// ---------------------------------------------------------------------------

class _Palette {
  // Sky (top, middle, horizon) keyed by sun height.
  static const skyKeys = <(double, List<Color>)>[
    (-0.55, [Color(0xFF060A20), Color(0xFF0E1638), Color(0xFF1A2550)]),
    (-0.15, [Color(0xFF1E2556), Color(0xFF4B3F7A), Color(0xFFA2647E)]),
    (0.10, [Color(0xFFF2A27E), Color(0xFFFFB46E), Color(0xFFFFD98A)]),
    (0.38, [Color(0xFF86B6E6), Color(0xFFBFDDF0), Color(0xFFF6E6C8)]),
    (0.80, [Color(0xFF5797DC), Color(0xFF94C2EC), Color(0xFFD6E9F6)]),
  ];

  static const sunCore = Color(0xFFFFF7DE);
  static const sunRim = Color(0xFFFFD98F);
  static const sunGlowLow = Color(0xFFFFC579);
  static const sunGlowHigh = Color(0xFFFFF3D0);
  static const moon = Color(0xFFF2F0E6);
  static const moonGlow = Color(0xFFC9D6FF);
  static const moonShade = Color(0xFFD9D6CA);
  static const star = Color(0xFFFFFFFF);

  static const cloudLight = Color(0xFFFFFFFF);
  static const cloudShade = Color(0xFFDCE6F2);
  static const cloudLightGolden = Color(0xFFFFF2E0);
  static const cloudShadeGolden = Color(0xFFEFC0A8);
  static const cloudLightNight = Color(0xFF3A4270);
  static const cloudShadeNight = Color(0xFF262C52);

  // Ridges, far to near: rose-purple at dawn and dusk, blue haze by day.
  static const ridgesGolden = [
    Color(0xFFC99BB2),
    Color(0xFFA17BA4),
    Color(0xFF7A5E90),
    Color(0xFF4A3D78),
  ];
  static const ridgesDay = [
    Color(0xFFA9BCD6),
    Color(0xFF8AA2C0),
    Color(0xFF6D86A3),
    Color(0xFF3F566B),
  ];
  static const ridgeSnow = Color(0xFFE6EDF5);
  static const ridgeRim = Color(0xFFFFD98F);
  static const crestTreesGolden = Color(0xFF2E2550);
  static const crestTreesDay = Color(0xFF22383F);

  static const mistGolden = Color(0xFFFFDFC0);
  static const mistDay = Color(0xFFEEF3F8);

  // River, horizon to viewer.
  static const riverGolden = [
    Color(0xFFFDCE96),
    Color(0xFFF3A98C),
    Color(0xFF8FB3C8),
    Color(0xFF4E8FB4),
  ];
  static const riverDay = [
    Color(0xFFCFE3F2),
    Color(0xFFA9CBE6),
    Color(0xFF7FAFD0),
    Color(0xFF3F84B0),
  ];
  static const ice = Color(0xFFCFE0EA);

  static const trunkDark = Color(0xFF6B4F3A);
  static const trunkLight = Color(0xFF8A6A4F);

  /// Haze that tints distant foliage.
  static const warmHaze = Color(0xFFE8B08A);
  static const bird = Color(0xFF4A3B66);
  static const ray = Color(0xFFFFE3A6);
  static const vignette = Color(0xFF1E3A28);

  // Light on the land, multiplied over every land color.
  static const tintGolden = Color(0xFFFFE0C4);
  static const tintBlueHour = Color(0xFFB59AC8);
  static const tintNight = Color(0xFF3B4680);
}

/// What the land looks like in one season.
class _SeasonLook {
  const _SeasonLook({
    required this.meadow,
    required this.leaves,
    required this.canopy,
    required this.blossom,
    required this.snow,
    required this.grass,
  });

  /// Meadow gradient: lit far edge, middle, deep foreground.
  final List<Color> meadow;

  /// Five foliage colors, blended by depth.
  final List<Color> leaves;

  /// Canopy fullness, 0 bare to 1 full.
  final double canopy;

  /// Blossom on the canopies, 0 to 1.
  final double blossom;

  /// Snow on the land, 0 to 1.
  final double snow;

  final Color grass;

  static _SeasonLook lerp(_SeasonLook a, _SeasonLook b, double t) =>
      _SeasonLook(
        meadow: [
          for (var i = 0; i < a.meadow.length; i++)
            Color.lerp(a.meadow[i], b.meadow[i], t)!,
        ],
        leaves: [
          for (var i = 0; i < a.leaves.length; i++)
            Color.lerp(a.leaves[i], b.leaves[i], t)!,
        ],
        canopy: ui.lerpDouble(a.canopy, b.canopy, t)!,
        blossom: ui.lerpDouble(a.blossom, b.blossom, t)!,
        snow: ui.lerpDouble(a.snow, b.snow, t)!,
        grass: Color.lerp(a.grass, b.grass, t)!,
      );

  /// The look at a continuous [season] (see [ValleyClock.season]).
  static _SeasonLook at(double season) {
    final i = season.floor() % _seasons.length;
    return lerp(
      _seasons[i],
      _seasons[(i + 1) % _seasons.length],
      season - season.floorToDouble(),
    );
  }
}

/// In [ValleySeason] order.
const _seasons = [
  // Spring: fresh light greens and blossom.
  _SeasonLook(
    meadow: [Color(0xFFD5E59E), Color(0xFF8CC46A), Color(0xFF4E8F4A)],
    leaves: [
      Color(0xFF5E9E4A),
      Color(0xFF73B159),
      Color(0xFF89C26A),
      Color(0xFFA2D07E),
      Color(0xFFB9DC95),
    ],
    canopy: 0.85,
    blossom: 1,
    snow: 0,
    grass: Color(0xFF3F7A3F),
  ),
  // Summer: deep, full greens.
  _SeasonLook(
    meadow: [Color(0xFFE2D58A), Color(0xFF8CBB5F), Color(0xFF357243)],
    leaves: [
      Color(0xFF3E7A3F),
      Color(0xFF4E8C48),
      Color(0xFF639E52),
      Color(0xFF79B061),
      Color(0xFF8FBF72),
    ],
    canopy: 1,
    blossom: 0,
    snow: 0,
    grass: Color(0xFF2C5E3C),
  ),
  // Autumn: amber canopies over a golden meadow.
  _SeasonLook(
    meadow: [Color(0xFFE6C27A), Color(0xFFB9A15A), Color(0xFF6F6B3A)],
    leaves: [
      Color(0xFFB5502A),
      Color(0xFFC9662E),
      Color(0xFFD9843A),
      Color(0xFFE3A04A),
      Color(0xFFE9B866),
    ],
    canopy: 0.85,
    blossom: 0,
    snow: 0,
    grass: Color(0xFF6B5A2E),
  ),
  // Winter: snow on the ground, thin frosted canopies.
  _SeasonLook(
    meadow: [Color(0xFFF4F7FA), Color(0xFFDCE5EE), Color(0xFFB7C6D6)],
    leaves: [
      Color(0xFFC9D3DC),
      Color(0xFFD3DCE4),
      Color(0xFFDCE3EA),
      Color(0xFFE3E9EE),
      Color(0xFFEAEFF3),
    ],
    canopy: 0.45,
    blossom: 0,
    snow: 1,
    grass: Color(0xFF8C8F86),
  ),
];

/// Where the sun and moon are and how they light the scene.
class _Light {
  factory _Light(ValleyClock clock, Size size) {
    final angle = clock.sunAngle;
    final h = math.sin(angle);
    Offset arc(double a) => Offset(
      size.width * (0.5 - 0.4 * math.cos(a)),
      size.height * (_horizonFrac - 0.32 * math.sin(a)),
    );
    return _Light._(
      sunHeight: h,
      sun: arc(angle),
      moon: arc(angle + math.pi),
      day: _smoothstep(0.0, 0.45, h),
      night: 1 - _smoothstep(-0.45, 0.02, h),
      golden: _smoothstep(0, 1, 1 - (h - 0.08).abs() / 0.3),
      sunUp: _smoothstep(-0.12, 0.04, h),
      moonUp: _smoothstep(-0.12, 0.04, -h),
    );
  }

  const _Light._({
    required this.sunHeight,
    required this.sun,
    required this.moon,
    required this.day,
    required this.night,
    required this.golden,
    required this.sunUp,
    required this.moonUp,
  });

  /// Where the sun and moon rise and set (behind the far ridge).
  static const _horizonFrac = 0.42;

  final double sunHeight;
  final Offset sun;
  final Offset moon;

  /// 1 in full daylight.
  final double day;

  /// 1 in full night.
  final double night;

  /// 1 while the sun is low (sunrise and sunset light).
  final double golden;

  /// 1 while the sun disc is above the horizon.
  final double sunUp;

  /// 1 while the moon disc is above the horizon.
  final double moonUp;

  /// Multiplied over the land: neutral by day, warm at golden hour, violet
  /// in the blue hour, deep blue at night.
  Color get landTint {
    final warm = Color.lerp(Colors.white, _Palette.tintGolden, golden)!;
    final blueHour = Color.lerp(
      warm,
      _Palette.tintBlueHour,
      (1 - sunUp) * (1 - night),
    )!;
    return Color.lerp(blueHour, _Palette.tintNight, night)!;
  }

  /// Sky colors (top, middle, horizon) for the current sun height.
  List<Color> get sky {
    const keys = _Palette.skyKeys;
    if (sunHeight <= keys.first.$1) return keys.first.$2;
    for (var i = 1; i < keys.length; i++) {
      final (h1, c1) = keys[i];
      if (sunHeight <= h1) {
        final (h0, c0) = keys[i - 1];
        final t = _smoothstep(h0, h1, sunHeight);
        return [for (var j = 0; j < 3; j++) Color.lerp(c0[j], c1[j], t)!];
      }
    }
    return keys.last.$2;
  }
}

// ---------------------------------------------------------------------------
// Ridge model
// ---------------------------------------------------------------------------

/// A ridge's silhouette profile: alternating peak/valley heights and their
/// normalized x positions, shared by the path builder and tree placement so
/// trees always sit exactly on the crest.
class _Ridge {
  _Ridge({required this.nodes, required this.xs});

  /// Height factors, 0..1 (even indices are peaks, odd are valleys).
  final List<double> nodes;

  /// Normalized x for each node, strictly increasing from 0 to 1.
  final List<double> xs;

  /// Linear height factor at normalized position [t].
  double heightAt(double t) {
    final n = nodes.length;
    final pos = (t.clamp(0.0, 1.0)) * (n - 1);
    final i = math.min(n - 2, pos.floor());
    final f = pos - i;
    return nodes[i] + (nodes[i + 1] - nodes[i]) * f;
  }
}

// ---------------------------------------------------------------------------
// Scene painter
// ---------------------------------------------------------------------------

class _ValleyPainter extends CustomPainter {
  _ValleyPainter({required this.progress, required this.seconds})
    : super(repaint: seconds);

  final double progress;
  final ValueNotifier<double> seconds;

  /// Top of the meadow / far edge of the river.
  static const _meadowTopFrac = 0.66;

  /// Top of the river (slightly below the meadow's far edge, so it emerges
  /// out of the hazy horizon).
  static const _riverTopFrac = 0.685;

  // Per-frame state, set at the start of [paint].
  late double _time;
  late ValleyClock _clock;
  late _Light _light;
  late _SeasonLook _look;

  @override
  void paint(Canvas canvas, Size size) {
    _time = seconds.value;
    _clock = ValleyClock(_time);
    _light = _Light(_clock, size);
    _look = _SeasonLook.at(_clock.season);

    _paintSky(canvas, size);
    _paintStars(canvas, size);
    _paintMoon(canvas, size);
    _paintSun(canvas, size);
    _paintClouds(canvas, size);
    _paintBirds(canvas, size);

    // The land is painted in layers lit by one color filter, so day, dusk
    // and night reach every ridge, field and tree alike.
    final lit = Paint()
      ..colorFilter = ColorFilter.mode(_light.landTint, BlendMode.modulate);
    canvas.saveLayer(Offset.zero & size, lit);
    _paintRidgesAndMist(canvas, size);
    _paintMeadow(canvas, size);
    final river = _riverPath(size);
    _paintRiver(canvas, size, river);
    _paintBanks(canvas, size);
    canvas.restore();

    // Light on the water stays bright: it is the sun or moon itself.
    _paintWaterLight(canvas, size, river);

    canvas.saveLayer(Offset.zero & size, lit);
    _mist(canvas, size, yFrac: 0.70, hFrac: 0.03, alpha: 0.35);
    _paintTrees(canvas, size);
    _paintForegroundGrass(canvas, size);
    canvas.restore();

    _paintWeather(canvas, size);
    _paintRays(canvas, size);
    _paintVignette(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _ValleyPainter old) =>
      old.progress != progress || old.seconds != seconds;

  /// Wind at screen x: slow gusts with a little flutter, about -1..1.
  double _wind(double x) {
    final gust = 0.55 + 0.45 * math.sin(_time * 0.23);
    return gust *
        (0.65 * math.sin(_time * 1.1 + x * 0.012) +
            0.35 * math.sin(_time * 2.6 + x * 0.031));
  }

  // -- Sky -------------------------------------------------------------------

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _light.sky,
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  void _paintStars(Canvas canvas, Size size) {
    final night = _light.night;
    if (night <= 0.01) return;
    final paint = Paint();
    for (var i = 0; i < 80; i++) {
      final x = _hash(i * 3 + 1) * size.width;
      final y = math.pow(_hash(i * 3 + 2), 1.4) * size.height * 0.46;
      final twinkle =
          0.55 + 0.45 * math.sin(_time * (1.2 + 2 * _hash(i * 3 + 3)) + i);
      final r = 0.6 + 1.2 * _hash(i * 7 + 5);
      paint.color = _Palette.star.withValues(alpha: night * twinkle * 0.9);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _paintMoon(Canvas canvas, Size size) {
    final up = _light.moonUp;
    if (up <= 0.01) return;
    final c = _light.moon;
    final r = size.width * 0.045;
    canvas.drawCircle(
      c,
      r * 5,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 5, [
          _Palette.moonGlow.withValues(alpha: 0.28 * up),
          _Palette.moonGlow.withValues(alpha: 0.0),
        ]),
    );
    canvas.drawCircle(c, r, Paint()..color = _Palette.moon.withValues(alpha: up));
    // A few soft maria so it reads as a moon, not a second sun.
    final shade = Paint()..color = _Palette.moonShade.withValues(alpha: 0.7 * up);
    canvas.drawCircle(c.translate(-r * 0.3, -r * 0.2), r * 0.28, shade);
    canvas.drawCircle(c.translate(r * 0.25, r * 0.3), r * 0.2, shade);
    canvas.drawCircle(c.translate(r * 0.35, -r * 0.35), r * 0.12, shade);
  }

  void _paintSun(Canvas canvas, Size size) {
    final up = _light.sunUp;
    if (up <= 0.01) return;
    final center = _light.sun;
    final day = _light.day;
    final glowColor =
        Color.lerp(_Palette.sunGlowLow, _Palette.sunGlowHigh, day)!;
    final glowRadius =
        size.width * (0.34 + 0.12 * progress) * (1 - 0.3 * day);
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          glowRadius,
          [
            glowColor.withValues(alpha: (0.40 + 0.25 * progress) * up),
            glowColor.withValues(alpha: (0.14 + 0.06 * progress) * up),
            glowColor.withValues(alpha: 0.0),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    final haloRadius = size.width * 0.075 * (1 - 0.2 * day);
    canvas.drawCircle(
      center,
      haloRadius,
      Paint()..color = _Palette.sunRim.withValues(alpha: 0.85 * up),
    );
    canvas.drawCircle(
      center,
      haloRadius * 0.78,
      Paint()..color = _Palette.sunCore.withValues(alpha: up),
    );
  }

  // -- Clouds (drifting, wrapping around) -------------------------------------

  void _paintClouds(Canvas canvas, Size size) {
    // (x, y, scale, puffs, speed in screen widths per second)
    const clouds = [
      (0.13, 0.09, 1.0, 5, 0.010),
      (0.50, 0.05, 1.35, 6, 0.007),
      (0.85, 0.12, 0.8, 4, 0.012),
      (0.32, 0.18, 0.65, 4, 0.015),
      (0.68, 0.22, 0.55, 3, 0.018),
    ];
    final base = size.width * 0.055;
    final rnd = math.Random(9);
    const margin = 0.35;
    for (final (dx, dy, scale, puffs, speed) in clouds) {
      final x = (dx + margin + _time * speed) % (1 + 2 * margin) - margin;
      _paintCloud(
        canvas,
        Offset(x * size.width, dy * size.height),
        base * scale,
        puffs,
        rnd,
      );
    }
  }

  void _paintCloud(
    Canvas canvas,
    Offset center,
    double r,
    int puffs,
    math.Random rnd,
  ) {
    final golden = _light.golden * (1 - _light.night);
    final night = _light.night;
    final lightColor = Color.lerp(
      Color.lerp(_Palette.cloudLight, _Palette.cloudLightGolden, golden)!,
      _Palette.cloudLightNight,
      night,
    )!;
    final shadeColor = Color.lerp(
      Color.lerp(_Palette.cloudShade, _Palette.cloudShadeGolden, golden)!,
      _Palette.cloudShadeNight,
      night,
    )!;
    final opacity = (0.75 + 0.15 * progress) * (1 - 0.25 * night);
    final shadow = Paint()..color = shadeColor.withValues(alpha: opacity * 0.8);
    final light = Paint()..color = lightColor.withValues(alpha: opacity);
    // Flat bottom: clip puffs to a rounded slab.
    final slab = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, r * 0.25),
        width: r * (2.2 + puffs * 0.25),
        height: r * 1.15,
      ),
      Radius.circular(r * 0.55),
    );
    canvas.drawRRect(slab, shadow);
    canvas.drawRRect(slab.shift(const Offset(0, -2)), light);
    for (var i = 0; i < puffs; i++) {
      final t = puffs == 1 ? 0.5 : i / (puffs - 1);
      final px = center.dx + (t - 0.5) * r * (2.0 + puffs * 0.22);
      final pr = r * (0.45 + 0.4 * rnd.nextDouble());
      final py = center.dy - r * 0.35 - (1 - (2 * t - 1).abs()) * r * 0.3;
      canvas.drawCircle(Offset(px, py), pr, light);
    }
  }

  // -- Birds (daytime, flapping across) ---------------------------------------

  void _paintBirds(Canvas canvas, Size size) {
    final visible = _light.sunUp * (1 - _light.night);
    if (visible <= 0.01) return;
    const specs = [(0.17, 0.16, 1.0), (0.27, 0.11, 0.78), (0.79, 0.13, 0.9)];
    final paint = Paint()
      ..color = _Palette.bird.withValues(alpha: 0.85 * visible)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    var i = 0;
    for (final (x0, y, s) in specs) {
      final x = (x0 + 0.2 + _time * 0.025) % 1.4 - 0.2;
      final c = Offset(
        x * size.width,
        y * size.height + math.sin(_time * 0.9 + i) * size.height * 0.008,
      );
      final wing = size.width * 0.016 * s;
      final flap = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(_time * 7 + i * 1.7));
      paint.strokeWidth = math.max(1.0, wing * 0.26);
      final path = Path()
        ..moveTo(c.dx - wing, c.dy + wing * (0.4 - flap * 0.6))
        ..quadraticBezierTo(
          c.dx - wing * 0.45, c.dy - wing * 0.95 * flap, c.dx, c.dy - wing * 0.18,
        )
        ..quadraticBezierTo(
          c.dx + wing * 0.45, c.dy - wing * 0.95 * flap,
          c.dx + wing, c.dy + wing * (0.4 - flap * 0.6),
        );
      canvas.drawPath(path, paint);
      i++;
    }
  }

  // -- Ridges with rim highlights and mist -----------------------------------

  void _paintRidgesAndMist(Canvas canvas, Size size) {
    const ridges = [
      (baseY: 0.44, amp: 0.10, peaks: 5, seed: 7, jagged: true, rim: false),
      (baseY: 0.50, amp: 0.085, peaks: 4, seed: 23, jagged: true, rim: true),
      (baseY: 0.56, amp: 0.06, peaks: 5, seed: 41, jagged: false, rim: true),
      (baseY: 0.62, amp: 0.045, peaks: 3, seed: 59, jagged: false, rim: true),
    ];
    const mists = [(0.465, 0.05, 0.55), (0.53, 0.045, 0.5), (0.585, 0.04, 0.45)];
    for (var i = 0; i < ridges.length; i++) {
      final r = ridges[i];
      final daylit = Color.lerp(
        _Palette.ridgesGolden[i],
        _Palette.ridgesDay[i],
        _light.day,
      )!;
      // Snow settles most on the far, high ridges.
      final color = Color.lerp(
        daylit,
        _Palette.ridgeSnow,
        _look.snow * (0.45 - 0.11 * i),
      )!;
      _ridge(
        canvas, size,
        baseY: r.baseY, amp: r.amp, peaks: r.peaks, seed: r.seed,
        color: color, jagged: r.jagged, rim: r.rim,
        crestTrees: i == ridges.length - 1,
      );
      if (i < mists.length) {
        final (y, h, a) = mists[i];
        _mist(canvas, size, yFrac: y, hFrac: h, alpha: a);
      }
    }
  }

  _Ridge _buildRidge(int peaks, int seed) {
    final rnd = math.Random(seed);
    final n = peaks * 2 + 1;
    final nodes = List.generate(n, (_) => rnd.nextDouble());
    for (var i = 0; i < n; i++) {
      // Even nodes become peaks, odd nodes the valleys between them.
      nodes[i] = i.isEven ? 0.55 + 0.45 * nodes[i] : 0.32 * nodes[i];
    }
    final xs = List<double>.generate(n, (i) => i / (n - 1));
    return _Ridge(nodes: nodes, xs: xs);
  }

  Offset _ridgePoint(
    _Ridge ridge,
    Size size,
    int i, {
    required double baseY,
    required double amp,
    required bool jagged,
  }) {
    final t = ridge.xs[i];
    final wobble =
        math.sin(t * 23 + i * 2.7) * size.height * (jagged ? 0.006 : 0.0);
    return Offset(
      t * size.width,
      (baseY - amp * ridge.nodes[i]) * size.height + wobble,
    );
  }

  /// Open crest path (used for the sunlit rim stroke).
  Path _crestPath(
    _Ridge ridge,
    Size size, {
    required double baseY,
    required double amp,
    required bool jagged,
  }) {
    final start =
        _ridgePoint(ridge, size, 0, baseY: baseY, amp: amp, jagged: jagged);
    final path = Path()..moveTo(start.dx, start.dy);
    final n = ridge.nodes.length;
    for (var i = 1; i < n; i++) {
      final p = _ridgePoint(ridge, size, i, baseY: baseY, amp: amp, jagged: jagged);
      if (jagged || i == n - 1) {
        path.lineTo(p.dx, p.dy);
      } else {
        final next = _ridgePoint(
          ridge, size, i + 1, baseY: baseY, amp: amp, jagged: jagged,
        );
        path.quadraticBezierTo(
          p.dx, p.dy, (p.dx + next.dx) / 2, (p.dy + next.dy) / 2,
        );
      }
    }
    return path;
  }

  void _ridge(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double amp,
    required int peaks,
    required int seed,
    required Color color,
    required bool jagged,
    required bool rim,
    required bool crestTrees,
  }) {
    final ridge = _buildRidge(peaks, seed);
    final crest = _crestPath(ridge, size, baseY: baseY, amp: amp, jagged: jagged);
    final fill = Path.from(crest)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color);

    // Sunlit rim: a warm stroke along the crest, strongest toward the sun
    // and only while it is low.
    final rimStrength = _light.golden * _light.sunUp;
    if (rim && rimStrength > 0.01) {
      final towardRight = _light.sun.dx >= size.width / 2;
      final rimColor = _Palette.ridgeRim.withValues(
        alpha: (0.35 + 0.2 * progress) * rimStrength,
      );
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size.width * 0.006)
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            begin: towardRight ? Alignment.centerLeft : Alignment.centerRight,
            end: towardRight ? Alignment.centerRight : Alignment.centerLeft,
            colors: [rimColor.withValues(alpha: 0.0), rimColor],
          ).createShader(Offset.zero & size),
      );
    }

    if (crestTrees) {
      _paintTreeRow(
        canvas, size, ridge,
        baseY: baseY, amp: amp,
        color: Color.lerp(
          _Palette.crestTreesGolden,
          _Palette.crestTreesDay,
          _light.day,
        )!,
        crestHeight: size.height * 0.09,
        baseCount: 2, fullCount: 10, sink: 0.012,
      );
    }
  }

  // -- Conifers on the near ridge crest ---------------------------------------

  void _paintTreeRow(
    Canvas canvas,
    Size size,
    _Ridge ridge, {
    required double baseY,
    required double amp,
    required Color color,
    required double crestHeight,
    required int baseCount,
    required int fullCount,
    required double sink,
  }) {
    final rnd = math.Random(ridge.nodes.length * 131 + crestHeight.round());
    final count = baseCount + ((fullCount - baseCount) * progress).round();
    final sizeFactor = 0.4 + 0.6 * progress;
    for (var i = 0; i < count; i++) {
      final t = (i + 0.5 + (rnd.nextDouble() - 0.5) * 0.7) / count;
      final x = t.clamp(0.02, 0.98) * size.width;
      final crestY =
          (baseY - amp * ridge.heightAt(t)) * size.height + sink * size.height;
      final h = crestHeight * sizeFactor * (0.7 + 0.45 * rnd.nextDouble());
      _conifer(canvas, x, crestY, h, color, sway: _wind(x) * 0.03);
    }
  }

  void _conifer(
    Canvas canvas,
    double x,
    double baseY,
    double h,
    Color color, {
    required double sway,
  }) {
    canvas.save();
    canvas.translate(x, baseY);
    canvas.rotate(sway);
    final paint = Paint()..color = color;
    final trunkWidth = math.max(1.2, h * 0.08);
    canvas.drawRect(
      Rect.fromLTWH(-trunkWidth / 2, -h * 0.16, trunkWidth, h * 0.18),
      paint,
    );
    final snow = Paint()
      ..color = _Palette.ridgeSnow.withValues(alpha: 0.85 * _look.snow);
    for (var i = 0; i < 3; i++) {
      final tierBase = -h * (0.10 + i * 0.28);
      final tierWidth = h * (0.55 - i * 0.13);
      final tierHeight = h * 0.42;
      final tier = Path()
        ..moveTo(-tierWidth / 2, tierBase)
        ..lineTo(tierWidth / 2, tierBase)
        ..lineTo(0, tierBase - tierHeight)
        ..close();
      canvas.drawPath(tier, paint);
      if (_look.snow > 0.01) {
        // Snow on the upper third of each tier.
        final cap = Path()
          ..moveTo(-tierWidth * 0.18, tierBase - tierHeight * 0.66)
          ..lineTo(tierWidth * 0.18, tierBase - tierHeight * 0.66)
          ..lineTo(0, tierBase - tierHeight)
          ..close();
        canvas.drawPath(cap, snow);
      }
    }
    canvas.restore();
  }

  // -- Mist bands -------------------------------------------------------------

  void _mist(
    Canvas canvas,
    Size size, {
    required double yFrac,
    required double hFrac,
    required double alpha,
  }) {
    final rect = Rect.fromLTWH(
      0,
      (yFrac - hFrac / 2) * size.height,
      size.width,
      hFrac * size.height,
    );
    final mist = Color.lerp(_Palette.mistGolden, _Palette.mistDay, _light.day)!;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          mist.withValues(alpha: 0),
          mist.withValues(alpha: alpha + 0.15 * progress),
          mist.withValues(alpha: 0),
        ],
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, hFrac * size.height * 0.3);
    canvas.drawRect(rect, paint);
  }

  // -- Meadow (valley floor) ----------------------------------------------------

  /// Season color, duller while the diet (and so the valley) is sparse.
  Color _grown(Color c) => _dull(c, (1 - progress) * 0.35);

  void _paintMeadow(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      _meadowTopFrac * size.height,
      size.width,
      size.height - _meadowTopFrac * size.height + 2,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [for (final c in _look.meadow) _grown(c)],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );
  }

  // -- River --------------------------------------------------------------------

  /// Center X of the river at parametric depth t (0 = horizon, 1 = viewer).
  /// It sways into an S-curve as it approaches the viewer.
  double _riverCenterX(double t, double width) {
    final sway = math.sin(t * math.pi * 1.15 + 0.4) * 0.16 +
        math.sin(t * math.pi * 2.3 + 1.2) * 0.05;
    return width * (0.62 + sway * (0.2 + 0.8 * t) - 0.12 * t);
  }

  /// Half-width of the river at depth t; widens as it approaches the viewer.
  double _riverHalfWidth(double t, double size) {
    return size * (0.012 + 0.17 * math.pow(t, 1.35).toDouble());
  }

  /// Screen y of depth t on the river.
  double _riverY(double t, Size size) {
    final top = size.height * _riverTopFrac;
    final bottom = size.height * 1.02;
    return top + (bottom - top) * math.pow(t, 1.15).toDouble();
  }

  /// One closed ribbon: left edge horizon->viewer, then right edge
  /// viewer->horizon.
  Path _riverPath(Size size) {
    final diag = math.min(size.width, size.height);
    Offset point(int side, double t) => Offset(
      _riverCenterX(t, size.width) + side * _riverHalfWidth(t, diag),
      _riverY(t, size),
    );
    const steps = 48;
    final start = point(-1, 0);
    final path = Path()..moveTo(start.dx, start.dy);
    for (var i = 1; i <= steps; i++) {
      final p = point(-1, i / steps);
      path.lineTo(p.dx, p.dy);
    }
    for (var i = steps; i >= 0; i--) {
      final p = point(1, i / steps);
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  void _paintRiver(Canvas canvas, Size size, Path river) {
    final top = size.height * _riverTopFrac;
    final rect = Rect.fromLTWH(0, top, size.width, size.height * 1.02 - top);
    final colors = [
      for (var i = 0; i < 4; i++)
        Color.lerp(
          Color.lerp(_Palette.riverGolden[i], _Palette.riverDay[i], _light.day)!,
          _Palette.ice,
          _look.snow * 0.45,
        )!,
    ];
    canvas.drawPath(
      river,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: const [0.0, 0.2, 0.5, 1.0],
        ).createShader(rect),
    );
  }

  /// The sun or moon reflected in the river, and streaks of light flowing
  /// down it toward the viewer.
  void _paintWaterLight(Canvas canvas, Size size, Path river) {
    final top = size.height * _riverTopFrac;
    final diag = math.min(size.width, size.height);
    final sunStrength = _light.sunUp * (0.35 + 0.65 * _light.golden);
    final moonStrength = _light.moonUp * _light.night * 0.6;
    final useSun = sunStrength >= moonStrength;
    final strength = useSun ? sunStrength : moonStrength;
    if (strength <= 0.01) return;
    final source = useSun ? _light.sun : _light.moon;
    final core = useSun ? _Palette.sunCore : _Palette.moon;
    final glow = useSun ? _Palette.sunGlowLow : _Palette.moonGlow;

    canvas.save();
    canvas.clipPath(river);
    final reflection = Offset(source.dx, top);
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, size.height - top),
      Paint()
        ..shader = ui.Gradient.radial(
          reflection,
          diag * 0.55,
          [
            core.withValues(alpha: (0.55 + 0.2 * progress) * strength),
            glow.withValues(alpha: (0.28 + 0.12 * progress) * strength),
            glow.withValues(alpha: 0.0),
          ],
          const [0.0, 0.35, 1.0],
        ),
    );

    // Streaks drift from the horizon toward the viewer, fading in and out
    // at the ends and swaying across the current.
    final shimmer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const streaks = 18;
    for (var i = 0; i < streaks; i++) {
      final u = _fract(_hash(i + 40) + _time * 0.035);
      final t = 0.05 + 0.93 * u;
      final y = _riverY(t, size);
      final cx = _riverCenterX(t, size.width);
      final hw = _riverHalfWidth(t, diag);
      final len = hw * (0.35 + 0.5 * (0.5 + 0.5 * math.sin(_time * 1.3 + i * 2)));
      final off = hw * 0.5 * math.sin(_time * 0.7 + i * 1.9);
      final warm = (1 - t).clamp(0.0, 1.0);
      final fade = math.sin(math.pi * u);
      shimmer
        ..color = Color.lerp(Colors.white, core, warm * 0.8)!.withValues(
          alpha: (0.22 + 0.12 * progress) * fade * (0.4 + 0.6 * strength),
        )
        ..strokeWidth = 1.0 + 1.8 * t;
      canvas.drawLine(
        Offset(cx + off - len / 2, y),
        Offset(cx + off + len / 2, y),
        shimmer,
      );
    }
    canvas.restore();
  }

  // -- Grassy banks hugging the river ------------------------------------------

  void _paintBanks(Canvas canvas, Size size) {
    for (final side in const [-1, 1]) {
      _paintBank(
        canvas, size, side: side,
        colorFar: _grown(_look.meadow[0]),
        colorNear: _grown(_look.meadow[1]),
      );
    }
  }

  void _paintBank(
    Canvas canvas,
    Size size, {
    required int side,
    required Color colorFar,
    required Color colorNear,
  }) {
    final top = size.height * _riverTopFrac;
    final bottom = size.height * 1.02;
    final diag = math.min(size.width, size.height);

    // Inner edge hugs the river; outer edge flares out with irregular sway.
    Offset point(double t, {required bool inner}) {
      final cx = _riverCenterX(t, size.width);
      final hw = _riverHalfWidth(t, diag);
      final out = hw +
          diag *
              (0.035 + 0.22 * math.pow(t, 1.3).toDouble()) *
              (0.85 + 0.3 * math.sin(t * 7 + side * 2));
      return Offset(cx + side * (inner ? hw * 0.96 : out), _riverY(t, size));
    }

    const steps = 40;
    final first = point(0, inner: true);
    final shape = Path()..moveTo(first.dx, first.dy);
    for (var i = 1; i <= steps; i++) {
      final p = point(i / steps, inner: true);
      shape.lineTo(p.dx, p.dy);
    }
    for (var i = steps; i >= 0; i--) {
      final p = point(i / steps, inner: false);
      shape.lineTo(p.dx, p.dy);
    }
    shape.close();

    final rect = Rect.fromLTWH(0, top, size.width, bottom - top);
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colorFar, colorNear],
        ).createShader(rect),
    );
  }

  // -- Trees on the banks -------------------------------------------------------

  void _paintTrees(Canvas canvas, Size size) {
    final diag = math.min(size.width, size.height);
    final rnd = math.Random(42);

    // Cluster specs: (side, depth center, spread, count).
    const clusters = [
      (side: -1, depth: 0.06, spread: 0.05, count: 8),
      (side: 1, depth: 0.10, spread: 0.06, count: 7),
      (side: -1, depth: 0.22, spread: 0.08, count: 6),
      (side: 1, depth: 0.26, spread: 0.07, count: 7),
      (side: -1, depth: 0.42, spread: 0.10, count: 5),
      (side: 1, depth: 0.48, spread: 0.11, count: 5),
      (side: -1, depth: 0.66, spread: 0.14, count: 4),
      (side: 1, depth: 0.74, spread: 0.13, count: 4),
      (side: -1, depth: 0.92, spread: 0.10, count: 2),
      (side: 1, depth: 0.95, spread: 0.09, count: 2),
    ];

    // Paint far-to-near so nearer trees overlap correctly.
    final trees = <_TreeSpec>[];
    for (final c in clusters) {
      for (var i = 0; i < c.count; i++) {
        final jitter = (rnd.nextDouble() - 0.5) * c.spread;
        final depth = (c.depth + jitter).clamp(0.0, 1.0);
        final lateral = 0.35 + 0.85 * rnd.nextDouble(); // distance from river
        trees.add(_TreeSpec(side: c.side, depth: depth, lateral: lateral));
      }
    }
    trees.sort((a, b) => a.depth.compareTo(b.depth));

    final lush = 0.35 + 0.65 * progress; // canopy fullness
    for (var i = 0; i < trees.length; i++) {
      final t = trees[i];
      // Skip some saplings at low progress; trees grow with progress.
      if (rnd.nextDouble() > (0.25 + 0.75 * progress) * _countGate(t.depth)) {
        continue;
      }
      _paintTree(canvas, size, t, diag, lush, rnd, i);
    }
  }

  /// Depth-based density gate so far rows feel like woodland, near rows like
  /// standalone trees.
  double _countGate(double depth) => 0.7 + 0.5 * math.sin(depth * math.pi);

  void _paintTree(
    Canvas canvas,
    Size size,
    _TreeSpec spec,
    double diag,
    double lush,
    math.Random rnd,
    int index,
  ) {
    final t = spec.depth;
    final y = size.height * _meadowTopFrac +
        size.height * 0.62 * math.pow(t, 1.15).toDouble();
    final cx = _riverCenterX(t, size.width);
    final hw = _riverHalfWidth(t, diag);
    final baseX =
        cx + spec.side * (hw + spec.lateral * diag * (0.03 + 0.30 * t));

    // Keep trunks on screen.
    final scale = diag * (0.020 + 0.105 * math.pow(t, 1.4).toDouble()) * lush;
    final baseY = y + scale * 0.05;
    if (baseX < -scale || baseX > size.width + scale) return;

    // The random draws below always run, whatever the season, so each tree
    // keeps its shape through the year.
    final depthFade = (1.0 - 0.62 * (1 - t)).clamp(0.0, 1.0);
    final trunkH = scale * (1.5 + 0.5 * rnd.nextDouble());
    final trunkW = math.max(1.0, scale * 0.10);
    final blobs = 3 + (rnd.nextDouble() * 3).floor();
    final canopyR =
        scale * (0.55 + 0.35 * lush) * (0.6 + 0.4 * _look.canopy);
    final greenT = (t * 0.85 + 0.1 * rnd.nextDouble()).clamp(0.0, 1.0);
    final blobShapes = [
      for (var i = 0; i < blobs; i++)
        (rnd.nextDouble(), rnd.nextDouble(), rnd.nextDouble()),
    ];

    // Sway about the base of the trunk; nearer, taller trees move more.
    canvas.save();
    canvas.translate(baseX, baseY);
    canvas.rotate(_wind(baseX) * (0.025 + 0.03 * t));

    final crownY = -trunkH - canopyR * 0.35;
    final trunkColor =
        Color.lerp(_Palette.trunkDark, _Palette.trunkLight, t)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -trunkH / 2),
          width: trunkW,
          height: trunkH,
        ),
        Radius.circular(trunkW),
      ),
      Paint()..color = trunkColor,
    );
    // Branches: hidden under a full canopy, bare in winter.
    final branch = Paint()
      ..color = trunkColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, trunkW * 0.6);
    for (final dir in const [-1.0, 1.0]) {
      canvas.drawLine(
        Offset(0, -trunkH * 0.75),
        Offset(dir * canopyR * 0.7, crownY - canopyR * 0.25),
        branch,
      );
    }

    // Canopy: overlapping blobs, lighter on the sunward side and hazy in
    // the distance.
    final baseLeaf = _leafFor(greenT);
    final haze = Color.lerp(baseLeaf, _Palette.warmHaze, 0.45 * (1 - t))!;
    final sunSide = _light.sun.dx >= size.width / 2 ? 1 : -1;
    final alpha = (0.55 + 0.45 * depthFade) * (0.35 + 0.65 * _look.canopy);
    for (final (a, d, s) in blobShapes) {
      final ang = a * math.pi * 2;
      final rad = d * canopyR * 0.55;
      final shade = math.cos(ang) * sunSide > 0 ? 0.12 : -0.10;
      final c = Color.lerp(haze, Colors.white, (0.10 + shade) * depthFade)!;
      canvas.drawCircle(
        Offset(math.cos(ang) * rad, crownY + math.sin(ang) * rad * 0.6),
        canopyR * (0.55 + 0.45 * s),
        Paint()..color = c.withValues(alpha: alpha),
      );
    }
    // Canopy core to unify blobs.
    canvas.drawCircle(
      Offset(0, crownY),
      canopyR * 0.6,
      Paint()..color = haze.withValues(alpha: alpha),
    );

    // Spring blossom.
    if (_look.blossom > 0.01) {
      final petals = Paint();
      final count = (7 * _look.blossom * lush).round();
      for (var k = 0; k < count; k++) {
        final ang = _hash(index * 31 + k) * math.pi * 2;
        final rad = _hash(index * 31 + k + 400) * canopyR * 0.8;
        petals.color = Color.lerp(
          const Color(0xFFF6B8CF),
          Colors.white,
          _hash(index * 31 + k + 800) * 0.5,
        )!.withValues(alpha: 0.9 * _look.blossom * depthFade);
        canvas.drawCircle(
          Offset(math.cos(ang) * rad, crownY + math.sin(ang) * rad * 0.6),
          math.max(1.0, canopyR * 0.11),
          petals,
        );
      }
    }
    canvas.restore();
  }

  /// Picks one of the season's five foliage colors; intermediate values
  /// blend so the ramp reads as continuous depth shading.
  Color _leafFor(double t) {
    final ramp = _look.leaves;
    final x = t.clamp(0.0, 0.999) * (ramp.length - 1);
    final i = x.floor();
    return _grown(Color.lerp(ramp[i], ramp[i + 1], x - i)!);
  }

  // -- Foreground grass tufts ---------------------------------------------------

  void _paintForegroundGrass(Canvas canvas, Size size) {
    final rnd = math.Random(19);
    final paint = Paint()
      ..color = _look.grass.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final diag = math.min(size.width, size.height);
    final n = (14 + 16 * progress).round();
    for (var i = 0; i < n; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = size.height * (0.86 + 0.13 * rnd.nextDouble());
      final h = size.height * (0.012 + 0.02 * rnd.nextDouble());
      final lean = (rnd.nextDouble() - 0.5) * h * 0.8;
      final width = 1.5 + 1.5 * rnd.nextDouble();
      // Skip tufts that fall in the river mouth.
      final t = ((y - size.height * _meadowTopFrac) / (size.height * 0.62))
          .clamp(0.0, 1.0);
      if ((x - _riverCenterX(t, size.width)).abs() < _riverHalfWidth(t, diag)) {
        continue;
      }
      final sway = lean + _wind(x) * h * 0.45;
      final path = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + sway * 0.4, y - h * 0.6, x + sway, y - h);
      canvas.drawPath(path, paint..strokeWidth = width);
    }
  }

  // -- Seasonal weather: petals, leaves, snow -----------------------------------

  void _paintWeather(Canvas canvas, Size size) {
    final s = _clock.season;
    // How much of each season is in the air, crossfading at hand-overs.
    double weight(int season) {
      final d = (s - season).abs();
      return (1.0 - math.min(d, 4.0 - d)).clamp(0.0, 1.0);
    }

    final spring = weight(ValleySeason.spring.index);
    final autumn = weight(ValleySeason.autumn.index);
    final winter = weight(ValleySeason.winter.index);
    if (spring > 0.01) {
      _fall(canvas, size, count: 16, seed: 1000, amount: spring,
          speed: 0.045, shape: _Flake.petal);
    }
    if (autumn > 0.01) {
      _fall(canvas, size, count: 22, seed: 2000, amount: autumn,
          speed: 0.06, shape: _Flake.leaf);
    }
    if (winter > 0.01) {
      _fall(canvas, size, count: 70, seed: 3000, amount: winter,
          speed: 0.03, shape: _Flake.snow);
    }
  }

  void _fall(
    Canvas canvas,
    Size size, {
    required int count,
    required int seed,
    required double amount,
    required double speed,
    required _Flake shape,
  }) {
    final unit = size.width / 400;
    final tint = Color.lerp(_light.landTint, Colors.white, 0.35)!;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final n = seed + i * 13;
      // Fewer particles while the season fades in or out.
      if (_hash(n) > amount) continue;
      final fall = speed * (0.6 + 0.8 * _hash(n + 1));
      final y = _fract(_hash(n + 2) + _time * fall) * size.height * 1.05 -
          size.height * 0.03;
      final drift = math.sin(_time * (0.6 + _hash(n + 3)) + i) * size.width * 0.04;
      final x = (_hash(n + 4) * size.width + drift + _wind(y) * 18 * unit) %
          size.width;
      final c = Offset(x, y);
      switch (shape) {
        case _Flake.snow:
          paint.color = _modulate(Colors.white, tint).withValues(alpha: 0.85);
          canvas.drawCircle(c, (1.2 + 1.6 * _hash(n + 5)) * unit, paint);
        case _Flake.leaf || _Flake.petal:
          final leaf = shape == _Flake.leaf;
          final base = leaf
              ? Color.lerp(const Color(0xFFC9662E), const Color(0xFFE9B866),
                  _hash(n + 6))!
              : Color.lerp(const Color(0xFFF6B8CF), Colors.white, _hash(n + 6) * 0.5)!;
          paint.color = _modulate(base, tint).withValues(alpha: 0.9);
          final w = (leaf ? 7.0 : 5.0) * unit;
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(_time * (1.5 + 2 * _hash(n + 7)) + i);
          canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.5),
            paint,
          );
          canvas.restore();
      }
    }
  }

  // -- Light rays -----------------------------------------------------------------

  void _paintRays(Canvas canvas, Size size) {
    final strength =
        _light.sunUp * (0.35 * _light.day + _light.golden).clamp(0.0, 1.0);
    if (strength <= 0.01) return;
    final sun = _light.sun;
    final paint = Paint()
      ..color = _Palette.ray.withValues(
        alpha: (0.04 + 0.07 * progress) * strength,
      );
    // Fan the rays down toward the middle of the valley.
    final toValley = math.atan2(
      size.height * 0.85 - sun.dy,
      size.width * 0.5 - sun.dx,
    );
    final rnd = math.Random(5);
    for (var i = 0; i < 4; i++) {
      final angle =
          toValley + (i - 1.5) * 0.45 + (rnd.nextDouble() - 0.5) * 0.12;
      final length = size.height * 1.3;
      final halfWidth = size.width * 0.05;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final perp = Offset(-dir.dy, dir.dx);
      final tip = sun + dir * length;
      final path = Path()
        ..moveTo(sun.dx, sun.dy)
        ..lineTo(tip.dx + perp.dx * halfWidth, tip.dy + perp.dy * halfWidth)
        ..lineTo(tip.dx - perp.dx * halfWidth, tip.dy - perp.dy * halfWidth)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  // -- Vignette -------------------------------------------------------------------

  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _Palette.vignette.withValues(alpha: 0),
            _Palette.vignette.withValues(alpha: 0.30),
          ],
          stops: const [0.82, 1.0],
        ).createShader(rect),
    );
  }
}

// ---------------------------------------------------------------------------
// Small model records
// ---------------------------------------------------------------------------

enum _Flake { snow, leaf, petal }

class _TreeSpec {
  const _TreeSpec({
    required this.side,
    required this.depth,
    required this.lateral,
  });

  final int side;
  final double depth;
  final double lateral;
}
