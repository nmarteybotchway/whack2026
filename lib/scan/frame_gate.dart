import 'dart:typed_data';

/// What [FrameGate] thinks of the latest camera frame.
enum GateState {
  /// Not enough frames seen yet.
  warmingUp,

  /// The lens is dark or covered, e.g. the phone is in a pocket or face
  /// down.
  inPocket,

  /// A send happened recently; nothing is sent until [FrameGate.cooldown]
  /// has passed.
  coolingDown,

  /// The camera (or the item) is moving too much.
  moving,

  /// The camera is steady but the centre of the frame has no detail worth
  /// identifying (a blank wall, a table top, a dim room).
  noItem,

  /// The camera is steady on the scene that was already sent.
  alreadySent,

  /// Steady on a new item; waiting for [FrameGate.holdDuration] to elapse.
  holding,

  /// Held steady long enough: send this frame to the API.
  ready,
}

/// The result of [FrameGate.addFrame], plus the raw metrics for tuning.
class GateStatus {
  const GateStatus(
    this.state, {
    this.progress = 0,
    this.motion = 0,
    this.detail = 0,
    this.novelty = 0,
    this.brightness = 0,
    this.contrast = 0,
  });

  final GateState state;

  /// 0..1 through the hold while [state] is [GateState.holding], or through
  /// the cooldown while it is [GateState.coolingDown].
  final double progress;

  /// Smoothed frame-to-frame change (0..255 luma).
  final double motion;

  /// Edge strength in the centre of the frame (0..255 luma).
  final double detail;

  /// Difference from the last frame that was sent (0..255 luma).
  final double novelty;

  /// Mean brightness of the whole frame (0..255 luma).
  final double brightness;

  /// Mean deviation from [brightness] across the whole frame (0..255 luma).
  final double contrast;

  @override
  String toString() =>
      '${state.name} motion=${motion.toStringAsFixed(1)} '
      'detail=${detail.toStringAsFixed(1)} '
      'novelty=${novelty.toStringAsFixed(1)} '
      'brightness=${brightness.toStringAsFixed(0)} '
      'contrast=${contrast.toStringAsFixed(1)}';
}

/// Decides when a live camera frame is worth spending an API call on.
///
/// Each frame is shrunk to a small brightness grid. A frame passes once:
///  * the lens is not dark or covered (in a pocket),
///  * [cooldown] has passed since the last send,
///  * the camera has been steady (little change between frames) for
///    [holdDuration],
///  * the centre of the frame has enough edges to look like an item rather
///    than a blank surface, and
///  * the scene differs from the last one sent, so holding the same item up
///    does not trigger repeat calls.
///
/// The grid is normalised to its mean brightness so auto-exposure changes do
/// not register as movement.
class FrameGate {
  FrameGate({
    this.holdDuration = const Duration(seconds: 1),
    this.cooldown = const Duration(seconds: 5),
    this.motionThreshold = 6,
    this.detailThreshold = 4,
    this.noveltyThreshold = 12,
    this.minBrightness = 25,
    this.pocketBrightness = 20,
    this.dimBrightness = 50,
    this.pocketContrast = 2,
  });

  final Duration holdDuration;

  /// Time after a send (or after [startCooldown]) during which nothing is
  /// sent, whatever the scene does.
  final Duration cooldown;

  /// Smoothed [GateStatus.motion] must stay below this to count as steady.
  final double motionThreshold;

  /// [GateStatus.detail] must reach this to count as an item.
  final double detailThreshold;

  /// [GateStatus.novelty] must reach this for a scene to count as new.
  final double noveltyThreshold;

  /// Mean luma below this is treated as too dark to identify anything.
  final double minBrightness;

  /// Mean luma below this means the lens is in the dark: in a pocket, a bag,
  /// or face down.
  final double pocketBrightness;

  /// A frame dimmer than this with less [GateStatus.contrast] than
  /// [pocketContrast] is also treated as covered: fabric pressed against the
  /// lens lets some light through but shows no structure.
  final double dimBrightness;
  final double pocketContrast;

  static const _grid = 24;
  static const _samplesPerCell = 3;
  static const _motionSmoothing = 0.5;

  Float32List? _previous;
  Float32List? _lastSent;
  Duration? _lastSentAt;
  Duration? _holdStart;
  double _motion = 0;

  /// True once a steady, different scene has been seen since the last send,
  /// so the same item can be sent again after it was taken away.
  bool _sceneChangedSinceSend = true;

  /// Forgets everything, e.g. after the camera restarts.
  void reset() {
    _previous = null;
    _lastSent = null;
    _lastSentAt = null;
    _holdStart = null;
    _motion = 0;
    _sceneChangedSinceSend = true;
  }

  /// Restarts the cooldown from [timestamp], e.g. once the API has answered,
  /// so the cooldown covers the time after the result rather than the time
  /// the request took.
  void startCooldown(Duration timestamp) => _lastSentAt = timestamp;

  /// Feeds one frame's brightness plane.
  ///
  /// [bytes] holds [height] rows of [rowStride] bytes; each pixel is
  /// [pixelStride] bytes wide with its brightness at [channelOffset]. For a
  /// YUV frame pass the Y plane as-is; for BGRA pass `pixelStride: 4,
  /// channelOffset: 1` to read the green channel.
  GateStatus addFrame(
    Uint8List bytes, {
    required int width,
    required int height,
    required int rowStride,
    required Duration timestamp,
    int pixelStride = 1,
    int channelOffset = 0,
  }) {
    final (grid, brightness) = _shrink(
      bytes,
      width,
      height,
      rowStride,
      pixelStride,
      channelOffset,
    );

    final previous = _previous;
    _previous = grid;
    if (previous == null) return const GateStatus(GateState.warmingUp);

    _motion =
        _motionSmoothing * _difference(grid, previous) +
        (1 - _motionSmoothing) * _motion;
    final detail = _centreDetail(grid);
    final contrast = _contrast(grid);
    final lastSent = _lastSent;
    final novelty = lastSent == null ? 255.0 : _difference(grid, lastSent);

    GateStatus status(GateState state, [double progress = 0]) => GateStatus(
      state,
      progress: progress,
      motion: _motion,
      detail: detail,
      novelty: novelty,
      brightness: brightness,
      contrast: contrast,
    );

    final inPocket =
        brightness < pocketBrightness ||
        (brightness < dimBrightness && contrast < pocketContrast);
    if (inPocket) {
      _holdStart = null;
      return status(GateState.inPocket);
    }

    final steady = _motion <= motionThreshold;
    // Seeing a different scene settle counts even during the cooldown, so the
    // same item can be sent again once it has been taken away.
    if (steady && novelty >= noveltyThreshold) _sceneChangedSinceSend = true;

    final lastSentAt = _lastSentAt;
    if (lastSentAt != null && timestamp - lastSentAt < cooldown) {
      _holdStart = null;
      final cooled = (timestamp - lastSentAt).inMicroseconds;
      return status(
        GateState.coolingDown,
        (cooled / cooldown.inMicroseconds).clamp(0, 1).toDouble(),
      );
    }

    if (!steady) {
      _holdStart = null;
      return status(GateState.moving);
    }

    if (brightness < minBrightness || detail < detailThreshold) {
      _holdStart = null;
      return status(GateState.noItem);
    }

    if (!_sceneChangedSinceSend) {
      _holdStart = null;
      return status(GateState.alreadySent);
    }

    final holdStart = _holdStart ??= timestamp;
    final held = timestamp - holdStart;
    if (held < holdDuration) {
      final progress = held.inMicroseconds / holdDuration.inMicroseconds;
      return status(GateState.holding, progress.clamp(0, 1).toDouble());
    }

    _lastSent = grid;
    _lastSentAt = timestamp;
    _holdStart = null;
    _sceneChangedSinceSend = false;
    return status(GateState.ready, 1);
  }

  /// Averages the frame into a [_grid]² grid with its mean subtracted, and
  /// returns the grid with the mean brightness.
  static (Float32List, double) _shrink(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
    int pixelStride,
    int channelOffset,
  ) {
    final grid = Float32List(_grid * _grid);
    const steps = _samplesPerCell * _grid;
    var total = 0.0;
    for (var gy = 0; gy < _grid; gy++) {
      for (var gx = 0; gx < _grid; gx++) {
        var sum = 0;
        for (var sy = 0; sy < _samplesPerCell; sy++) {
          final y =
              ((gy * _samplesPerCell + sy) * 2 + 1) * height ~/ (2 * steps);
          final row = y * rowStride + channelOffset;
          for (var sx = 0; sx < _samplesPerCell; sx++) {
            final x =
                ((gx * _samplesPerCell + sx) * 2 + 1) * width ~/ (2 * steps);
            sum += bytes[row + x * pixelStride];
          }
        }
        final value = sum / (_samplesPerCell * _samplesPerCell);
        grid[gy * _grid + gx] = value;
        total += value;
      }
    }
    final mean = total / grid.length;
    for (var i = 0; i < grid.length; i++) {
      grid[i] -= mean;
    }
    return (grid, mean);
  }

  static double _difference(Float32List a, Float32List b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += (a[i] - b[i]).abs();
    }
    return sum / a.length;
  }

  /// Mean distance from the mean; the grid already has its mean subtracted.
  static double _contrast(Float32List grid) {
    var sum = 0.0;
    for (final value in grid) {
      sum += value.abs();
    }
    return sum / grid.length;
  }

  /// Mean absolute gradient over the middle half of the grid.
  static double _centreDetail(Float32List grid) {
    const start = _grid ~/ 4;
    const end = _grid - _grid ~/ 4;
    var sum = 0.0;
    var count = 0;
    for (var y = start; y < end - 1; y++) {
      for (var x = start; x < end - 1; x++) {
        final here = grid[y * _grid + x];
        sum += (grid[y * _grid + x + 1] - here).abs();
        sum += (grid[(y + 1) * _grid + x] - here).abs();
        count += 2;
      }
    }
    return sum / count;
  }
}
