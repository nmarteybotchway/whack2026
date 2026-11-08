import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// "Sunrise river valley" — the scene behind the home tab.
///
/// A warm dawn sky with a low sun glows above layered ridge silhouettes
/// wrapped in mist bands. From the hazy horizon a river winds in an S-curve,
/// widening as it flows toward the viewer, catching the sunrise colors in its
/// water. Sunlit rim highlights trace the ridge crests, conifers crown the
/// nearest ridge, and clustered trees and grass tufts line the grassy banks.
/// [progress] (0.0-1.0) drives lushness: sparse saplings at 0, a full valley
/// at 1.
class SunriseValley extends StatelessWidget {
  const SunriseValley({super.key, required this.progress});

  /// 0.0 - 1.0; growth / lushness of the scene.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _SunriseRiverPainter(progress: progress.clamp(0.0, 1.0)),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

class _C13Palette {
  // Sky: soft dawn (progress 0) -> vivid sunrise (progress 1).
  static const skyTopCalm = Color(0xFFEFC5A6);
  static const skyTopWarm = Color(0xFFFF9D74);
  static const skyMidCalm = Color(0xFFF6BB90);
  static const skyMidWarm = Color(0xFFFFB168);
  static const skyLowCalm = Color(0xFFFBDFAE);
  static const skyLowWarm = Color(0xFFFFD56E);

  static const sunCore = Color(0xFFFFF7DE);
  static const sunRim = Color(0xFFFFD98F);
  static const sunGlow = Color(0xFFFFC579);

  static const cloudLight = Color(0xFFFFF2E0);
  static const cloudShade = Color(0xFFEFC0A8);

  // Ridges, far to near: hazy rose-purple deepening to dark indigo.
  static const ridgeFar = Color(0xFFC99BB2);
  static const ridge2 = Color(0xFFA17BA4);
  static const ridge3 = Color(0xFF7A5E90);
  static const ridgeNear = Color(0xFF4A3D78);
  static const ridgeRim = Color(0xFFFFD98F);
  static const treeSilhouette = Color(0xFF2E2550);

  static const mist = Color(0xFFFFDFC0);

  // River: sunrise gold at the horizon -> deep blue-teal near the viewer.
  static const riverFar = Color(0xFFFDCE96);
  static const riverWarm = Color(0xFFF3A98C);
  static const riverMid = Color(0xFF8FB3C8);
  static const riverNear = Color(0xFF4E8FB4);

  // Meadow: pale grass (progress 0) -> lush sunlit green (progress 1).
  static const meadowLitCalm = Color(0xFFDCC795);
  static const meadowLitWarm = Color(0xFFF0D488);
  static const meadowMidCalm = Color(0xFFA3AC79);
  static const meadowMidWarm = Color(0xFF8CBB5F);
  static const meadowDeepCalm = Color(0xFF6B8358);
  static const meadowDeepWarm = Color(0xFF357243);

  static const trunkDark = Color(0xFF6B4F3A);
  static const trunkLight = Color(0xFF8A6A4F);

  // Foliage greens, near to far.
  static const leaf1 = Color(0xFF3E7A3F);
  static const leaf2 = Color(0xFF4E8C48);
  static const leaf3 = Color(0xFF639E52);
  static const leaf4 = Color(0xFF79B061);
  static const leaf5 = Color(0xFF8FBF72);

  // Warm haze that tints distant foliage.
  static const warmHaze = Color(0xFFE8B08A);

  static const grassDark = Color(0xFF2C5E3C);
  static const bird = Color(0xFF4A3B66);
  static const ray = Color(0xFFFFE3A6);
  static const vignette = Color(0xFF1E3A28);
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

class _SunriseRiverPainter extends CustomPainter {
  _SunriseRiverPainter({required this.progress});

  final double progress;

  /// Normalized x of the sun (also the river's far-center anchor, so the
  /// river's horizon reads as a sunlit path flowing toward the viewer).
  static const _sunX = 0.66;

  /// Top of the meadow / far edge of the river.
  static const _meadowTopFrac = 0.66;

  /// Top of the river (slightly below the meadow's far edge, so it emerges
  /// out of the hazy horizon).
  static const _riverTopFrac = 0.685;

  /// Interpolates from the calm dawn color to the vivid sunrise color.
  Color _c(Color calm, Color warm) => Color.lerp(calm, warm, progress)!;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintSun(canvas, size);
    _paintClouds(canvas, size);
    _paintBirds(canvas, size);
    _paintRidgesAndMist(canvas, size);
    _paintMeadow(canvas, size);
    _paintRiver(canvas, size);
    _paintBanks(canvas, size);
    _mist(canvas, size, yFrac: 0.70, hFrac: 0.03, alpha: 0.35);
    _paintTrees(canvas, size);
    _paintForegroundGrass(canvas, size);
    _paintRays(canvas, size);
    _paintVignette(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _SunriseRiverPainter old) =>
      old.progress != progress;

  // -- Sky -------------------------------------------------------------------

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _c(_C13Palette.skyTopCalm, _C13Palette.skyTopWarm),
            _c(_C13Palette.skyMidCalm, _C13Palette.skyMidWarm),
            _c(_C13Palette.skyLowCalm, _C13Palette.skyLowWarm),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  // -- Sun (low, just behind the far ridge) ----------------------------------

  void _paintSun(Canvas canvas, Size size) {
    final center = Offset(size.width * _sunX, size.height * 0.38);
    final glowRadius = size.width * (0.34 + 0.12 * progress);
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        center,
        glowRadius,
        [
          _C13Palette.sunGlow.withValues(alpha: 0.40 + 0.25 * progress),
          _C13Palette.sunGlow.withValues(alpha: 0.14 + 0.06 * progress),
          _C13Palette.sunGlow.withValues(alpha: 0.0),
        ],
        const [0.0, 0.45, 1.0],
      );
    canvas.drawCircle(center, glowRadius, glow);

    final haloRadius = size.width * 0.075;
    canvas.drawCircle(
      center,
      haloRadius,
      Paint()..color = _C13Palette.sunRim.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      center,
      haloRadius * 0.78,
      Paint()..color = _C13Palette.sunCore,
    );
  }

  // -- Clouds (warm dawn puffs) ----------------------------------------------

  void _paintClouds(Canvas canvas, Size size) {
    const clouds = [
      (0.13, 0.09, 1.0, 5),
      (0.50, 0.05, 1.35, 6),
      (0.85, 0.12, 0.8, 4),
      (0.32, 0.18, 0.65, 4),
      (0.68, 0.22, 0.55, 3),
    ];
    final base = size.width * 0.055;
    final rnd = math.Random(9);
    for (final (dx, dy, scale, puffs) in clouds) {
      _paintCloud(
        canvas,
        Offset(dx * size.width, dy * size.height),
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
    final opacity = 0.75 + 0.15 * progress;
    final shadow = Paint()
      ..color = _C13Palette.cloudShade.withValues(alpha: opacity * 0.8);
    final light = Paint()..color = _C13Palette.cloudLight.withValues(alpha: opacity);
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
    canvas.drawRRect(
      slab.shift(const Offset(0, -2)),
      light,
    );
    for (var i = 0; i < puffs; i++) {
      final t = puffs == 1 ? 0.5 : i / (puffs - 1);
      final px = center.dx + (t - 0.5) * r * (2.0 + puffs * 0.22);
      final pr = r * (0.45 + 0.4 * rnd.nextDouble());
      final py = center.dy - r * 0.35 - (1 - (2 * t - 1).abs()) * r * 0.3;
      canvas.drawCircle(Offset(px, py), pr, light);
    }
  }

  // -- Birds -----------------------------------------------------------------

  void _paintBirds(Canvas canvas, Size size) {
    const specs = [
      (0.17, 0.16, 1.0),
      (0.27, 0.11, 0.78),
      (0.79, 0.13, 0.9),
    ];
    final paint = Paint()
      ..color = _C13Palette.bird.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (x, y, s) in specs) {
      final c = Offset(x * size.width, y * size.height);
      final wing = size.width * 0.016 * s;
      paint.strokeWidth = math.max(1.0, wing * 0.26);
      final path = Path()
        ..moveTo(c.dx - wing, c.dy)
        ..quadraticBezierTo(
          c.dx - wing * 0.45, c.dy - wing * 0.95, c.dx, c.dy - wing * 0.18,
        )
        ..quadraticBezierTo(
          c.dx + wing * 0.45, c.dy - wing * 0.95, c.dx + wing, c.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  // -- Ridges with rim highlights and mist -----------------------------------

  void _paintRidgesAndMist(Canvas canvas, Size size) {
    _ridge(
      canvas, size,
      baseY: 0.44, amp: 0.10, peaks: 5, seed: 7,
      color: _C13Palette.ridgeFar, jagged: true, rim: false,
    );
    _mist(canvas, size, yFrac: 0.465, hFrac: 0.05, alpha: 0.55);
    _ridge(
      canvas, size,
      baseY: 0.50, amp: 0.085, peaks: 4, seed: 23,
      color: _C13Palette.ridge2, jagged: true, rim: true,
    );
    _mist(canvas, size, yFrac: 0.53, hFrac: 0.045, alpha: 0.5);
    _ridge(
      canvas, size,
      baseY: 0.56, amp: 0.06, peaks: 5, seed: 41,
      color: _C13Palette.ridge3, jagged: false, rim: true,
    );
    _mist(canvas, size, yFrac: 0.585, hFrac: 0.04, alpha: 0.45);
    _ridge(
      canvas, size,
      baseY: 0.62, amp: 0.045, peaks: 3, seed: 59,
      color: _C13Palette.ridgeNear, jagged: false, rim: true, crestTrees: true,
    );
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
    final path = Path()
      ..moveTo(_ridgePoint(ridge, size, 0, baseY: baseY, amp: amp, jagged: jagged).dx,
          _ridgePoint(ridge, size, 0, baseY: baseY, amp: amp, jagged: jagged).dy);
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

  Path _ridgePath(
    _Ridge ridge,
    Size size, {
    required double baseY,
    required double amp,
    required bool jagged,
  }) {
    final path = _crestPath(ridge, size, baseY: baseY, amp: amp, jagged: jagged);
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
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
    bool crestTrees = false,
  }) {
    final ridge = _buildRidge(peaks, seed);
    final path = _ridgePath(
      ridge, size, baseY: baseY, amp: amp, jagged: jagged,
    );
    canvas.drawPath(path, Paint()..color = color);

    // Sunlit rim: a warm stroke along the crest, strongest toward the sun.
    if (rim) {
      final crest = _crestPath(
        ridge, size, baseY: baseY, amp: amp, jagged: jagged,
      );
      final rect = Offset.zero & size;
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size.width * 0.006)
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              _C13Palette.ridgeRim.withValues(alpha: 0.0),
              _C13Palette.ridgeRim.withValues(alpha: 0.35 + 0.2 * progress),
            ],
          ).createShader(rect),
      );
    }

    if (crestTrees) {
      _paintTreeRow(
        canvas, size, ridge,
        baseY: baseY, amp: amp,
        color: _C13Palette.treeSilhouette,
        crestHeight: size.height * 0.09,
        baseCount: 2, fullCount: 10, sink: 0.012,
      );
    }
  }

  // -- Trees on a ridge crest -------------------------------------------------

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
      final h = crestHeight *
          sizeFactor *
          (0.7 + 0.45 * rnd.nextDouble());
      _conifer(canvas, x, crestY, h, color);
    }
  }

  void _conifer(
    Canvas canvas,
    double x,
    double baseY,
    double h,
    Color color,
  ) {
    final paint = Paint()..color = color;
    final trunkWidth = math.max(1.2, h * 0.08);
    canvas.drawRect(
      Rect.fromLTWH(x - trunkWidth / 2, baseY - h * 0.16, trunkWidth, h * 0.18),
      paint,
    );
    for (var i = 0; i < 3; i++) {
      final tierBase = baseY - h * (0.10 + i * 0.28);
      final tierWidth = h * (0.55 - i * 0.13);
      final tierHeight = h * 0.42;
      final path = Path()
        ..moveTo(x - tierWidth / 2, tierBase)
        ..lineTo(x + tierWidth / 2, tierBase)
        ..lineTo(x, tierBase - tierHeight)
        ..close();
      canvas.drawPath(path, paint);
    }
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
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _C13Palette.mist.withValues(alpha: 0),
          _C13Palette.mist.withValues(alpha: alpha + 0.15 * progress),
          _C13Palette.mist.withValues(alpha: 0),
        ],
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, hFrac * size.height * 0.3);
    canvas.drawRect(rect, paint);
  }

  // -- Meadow (valley floor) ----------------------------------------------------

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
          colors: [
            _c(_C13Palette.meadowLitCalm, _C13Palette.meadowLitWarm),
            _c(_C13Palette.meadowMidCalm, _C13Palette.meadowMidWarm),
            _c(_C13Palette.meadowDeepCalm, _C13Palette.meadowDeepWarm),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );
  }

  // -- River --------------------------------------------------------------------

  /// Center X of the river at parametric depth t (0 = horizon, 1 = viewer).
  /// The far end anchors near the sun so the river reads as a sunlit path;
  /// it sways into an S-curve as it approaches the viewer.
  double _riverCenterX(double t, double width) {
    final sway = math.sin(t * math.pi * 1.15 + 0.4) * 0.16 +
        math.sin(t * math.pi * 2.3 + 1.2) * 0.05;
    return width * (0.62 + sway * (0.2 + 0.8 * t) - 0.12 * t);
  }

  /// Half-width of the river at depth t; widens as it approaches the viewer.
  double _riverHalfWidth(double t, double size) {
    return size * (0.012 + 0.17 * math.pow(t, 1.35).toDouble());
  }

  void _paintRiver(Canvas canvas, Size size) {
    final top = size.height * _riverTopFrac;
    final bottom = size.height * 1.02;
    final diag = math.min(size.width, size.height);

    Offset riverPoint(int side, double t) {
      final y = top + (bottom - top) * math.pow(t, 1.15).toDouble();
      final cx = _riverCenterX(t, size.width);
      final hw = _riverHalfWidth(t, diag);
      return Offset(cx + side * hw, y);
    }

    // One closed ribbon: left edge horizon->viewer, then right edge
    // viewer->horizon, so the gradient fill reads as a single shape.
    const steps = 48;
    final fill = Path()..moveTo(riverPoint(-1, 0).dx, riverPoint(-1, 0).dy);
    for (var i = 1; i <= steps; i++) {
      final p = riverPoint(-1, i / steps);
      fill.lineTo(p.dx, p.dy);
    }
    for (var i = steps; i >= 0; i--) {
      final p = riverPoint(1, i / steps);
      fill.lineTo(p.dx, p.dy);
    }
    fill.close();

    final rect = Rect.fromLTWH(0, top, size.width, bottom - top);
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _C13Palette.riverFar,
            _C13Palette.riverWarm,
            _C13Palette.riverMid,
            _C13Palette.riverNear,
          ],
          stops: const [0.0, 0.2, 0.5, 1.0],
        ).createShader(rect),
    );

    // Sunrise light pooling on the water near the horizon.
    canvas.save();
    canvas.clipPath(fill);
    final sunCenter = Offset(size.width * _sunX, top);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          sunCenter,
          diag * 0.55,
          [
            _C13Palette.sunCore.withValues(alpha: 0.55 + 0.2 * progress),
            _C13Palette.sunGlow.withValues(alpha: 0.28 + 0.12 * progress),
            _C13Palette.sunGlow.withValues(alpha: 0.0),
          ],
          const [0.0, 0.35, 1.0],
        ),
    );
    canvas.restore();

    // Soft shimmer strokes across the water; warm near the horizon.
    final rnd = math.Random(13);
    final shimmer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final t = 0.08 + 0.9 * (i / 12) + 0.02 * rnd.nextDouble();
      final y = top + (bottom - top) * math.pow(t, 1.15).toDouble();
      final cx = _riverCenterX(t, size.width);
      final hw = _riverHalfWidth(t, diag);
      final len = hw * (0.5 + 0.7 * rnd.nextDouble());
      final off = (2 * rnd.nextDouble() - 1) * hw * 0.5;
      final warm = (1 - t).clamp(0.0, 1.0);
      shimmer
        ..color = Color.lerp(
          Colors.white,
          _C13Palette.sunCore,
          warm * 0.8,
        )!.withValues(alpha: 0.22 + 0.1 * progress)
        ..strokeWidth = 1.0 + 1.8 * t;
      canvas.drawLine(
        Offset(cx + off - len / 2, y),
        Offset(cx + off + len / 2, y),
        shimmer,
      );
    }
  }

  // -- Grassy banks hugging the river ------------------------------------------

  void _paintBanks(Canvas canvas, Size size) {
    _paintBank(
      canvas, size, side: -1,
      colorFar: _C13Palette.meadowLitWarm,
      colorNear: _C13Palette.meadowMidWarm,
    );
    _paintBank(
      canvas, size, side: 1,
      colorFar: _C13Palette.meadowLitWarm,
      colorNear: _C13Palette.meadowMidWarm,
    );
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
      final y = top + (bottom - top) * math.pow(t, 1.15).toDouble();
      final cx = _riverCenterX(t, size.width);
      final hw = _riverHalfWidth(t, diag);
      final out = hw +
          diag *
              (0.035 + 0.22 * math.pow(t, 1.3).toDouble()) *
              (0.85 + 0.3 * math.sin(t * 7 + side * 2));
      final x = cx + side * (inner ? hw * 0.96 : out);
      return Offset(x, y);
    }

    const steps = 40;
    final shape = Path();
    final first = point(0, inner: true);
    shape.moveTo(first.dx, first.dy);
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
    for (final t in trees) {
      // Skip some saplings at low progress; trees grow with progress.
      if (rnd.nextDouble() > (0.25 + 0.75 * progress) * _countGate(t.depth)) {
        continue;
      }
      _paintTree(canvas, size, t, diag, lush, rnd);
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

    final depthFade = (1.0 - 0.62 * (1 - t)).clamp(0.0, 1.0);
    final trunkH = scale * (1.5 + 0.5 * rnd.nextDouble());
    final trunkW = math.max(1.0, scale * 0.10);

    // Trunk: slight taper via two rounded rects.
    final trunkRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(baseX, baseY - trunkH / 2),
        width: trunkW,
        height: trunkH,
      ),
      Radius.circular(trunkW),
    );
    canvas.drawRRect(
      trunkRect,
      Paint()..color = Color.lerp(_C13Palette.trunkDark, _C13Palette.trunkLight, t)!,
    );

    // Canopy: 3-5 overlapping blobs, jittered; lighter on the sun side and
    // hazy warm in the distance.
    final blobs = 3 + (rnd.nextDouble() * 3).floor();
    final canopyR = scale * (0.55 + 0.35 * lush);
    final greenT = (t * 0.85 + 0.1 * rnd.nextDouble()).clamp(0.0, 1.0);
    final baseLeaf = _leafFor(greenT);
    final haze = Color.lerp(baseLeaf, _C13Palette.warmHaze, 0.45 * (1 - t))!;

    for (var i = 0; i < blobs; i++) {
      final ang = rnd.nextDouble() * math.pi * 2;
      final rad = rnd.nextDouble() * canopyR * 0.55;
      final bx = baseX + math.cos(ang) * rad;
      final by = baseY - trunkH - canopyR * 0.35 + math.sin(ang) * rad * 0.6;
      final br = canopyR * (0.55 + 0.45 * rnd.nextDouble());
      final shade = (math.cos(ang) * spec.side > 0 ? 0.12 : -0.10);
      final c = Color.lerp(
        haze,
        Colors.white,
        (0.10 + shade) * depthFade,
      )!;
      final alpha = 0.55 + 0.45 * depthFade;
      canvas.drawCircle(
        Offset(bx, by),
        br,
        Paint()..color = c.withValues(alpha: alpha),
      );
    }
    // Canopy core to unify blobs.
    canvas.drawCircle(
      Offset(baseX, baseY - trunkH - canopyR * 0.35),
      canopyR * 0.6,
      Paint()
        ..color = haze.withValues(alpha: 0.55 + 0.45 * depthFade),
    );
  }

  /// Picks one of the five foliage greens; intermediate values blend so the
  /// ramp reads as continuous depth shading.
  static Color _leafFor(double t) {
    const ramp = [
      _C13Palette.leaf1,
      _C13Palette.leaf2,
      _C13Palette.leaf3,
      _C13Palette.leaf4,
      _C13Palette.leaf5,
    ];
    final x = t.clamp(0.0, 0.999) * (ramp.length - 1);
    final i = x.floor();
    return Color.lerp(ramp[i], ramp[i + 1], x - i)!;
  }

  // -- Foreground grass tufts ---------------------------------------------------

  void _paintForegroundGrass(Canvas canvas, Size size) {
    final rnd = math.Random(19);
    final paint = Paint()
      ..color = _C13Palette.grassDark.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final n = (14 + 16 * progress).round();
    for (var i = 0; i < n; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = size.height * (0.86 + 0.13 * rnd.nextDouble());
      // Skip tufts that fall in the river mouth.
      final t = ((y - size.height * _meadowTopFrac) / (size.height * 0.62))
          .clamp(0.0, 1.0);
      if ((x - _riverCenterX(t, size.width)).abs() <
          _riverHalfWidth(t, math.min(size.width, size.height))) {
        continue;
      }
      final h = size.height * (0.012 + 0.02 * rnd.nextDouble());
      final sway = (rnd.nextDouble() - 0.5) * h * 0.8;
      final path = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + sway * 0.4, y - h * 0.6, x + sway, y - h);
      canvas.drawPath(path, paint..strokeWidth = 1.5 + 1.5 * rnd.nextDouble());
    }
  }

  // -- Light rays -----------------------------------------------------------------

  void _paintRays(Canvas canvas, Size size) {
    final sun = Offset(size.width * _sunX, size.height * 0.38);
    final paint = Paint()
      ..color = _C13Palette.ray.withValues(alpha: 0.04 + 0.07 * progress);
    final rnd = math.Random(5);
    for (var i = 0; i < 4; i++) {
      final angle =
          math.pi / 2 + (i - 1.5) * 0.45 + (rnd.nextDouble() - 0.5) * 0.12;
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
            _C13Palette.vignette.withValues(alpha: 0),
            _C13Palette.vignette.withValues(alpha: 0.30),
          ],
          stops: const [0.82, 1.0],
        ).createShader(rect),
    );
  }
}

// ---------------------------------------------------------------------------
// Small model records
// ---------------------------------------------------------------------------

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
