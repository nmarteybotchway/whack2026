import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// A scored item, either the scanned one or a suggested alternative.
class AnalysedItem {
  const AnalysedItem({
    required this.name,
    required this.score,
    required this.highlights,
  });

  final String name;

  /// Health score from 0 (worst) to 100 (best).
  final int score;

  /// Short facts shown under the item, e.g. "High in sugar".
  final List<String> highlights;
}

/// What [CameraAnalysis] found in a frame.
class AnalysisResult {
  const AnalysisResult({required this.item, this.alternative});

  final AnalysedItem item;

  /// A better option to suggest instead of [item], if there is one.
  final AnalysedItem? alternative;
}

/// Receives camera frames from the scan page and analyses them.
///
/// Frames are raw [CameraImage]s from the camera's image stream: YUV420 on
/// Android and BGRA8888 on iOS. Use [camera] (e.g. its `sensorOrientation`)
/// to work out how the frame is rotated relative to the screen.
class CameraAnalysis {
  CameraAnalysis({required this.camera});

  final CameraDescription camera;

  /// Analyses a single frame. The scan page waits for the returned future
  /// before sending the next frame, so it is safe to do slow work here.
  Future<AnalysisResult> analyse(CameraImage frame) async {
    debugPrint(
      'CameraAnalysis: ${frame.width}x${frame.height} '
      '${frame.format.group.name}, ${frame.planes.length} plane(s)',
    );
    // TODO: real analysis. Mocked result until then.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return _mockResult;
  }

  /// Releases any resources held by the analysis.
  void dispose() {}
}

const _mockResult = AnalysisResult(
  item: AnalysedItem(
    name: 'Milk chocolate bar (mock)',
    score: 28,
    highlights: ['High in sugar (56g / 100g)', 'High in saturated fat'],
  ),
  alternative: AnalysedItem(
    name: 'Dark chocolate 85% (mock)',
    score: 64,
    highlights: ['70% less sugar', 'Higher in fibre and iron'],
  ),
);
