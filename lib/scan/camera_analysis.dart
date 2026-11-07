import 'package:flutter/foundation.dart';

import 'product_identification_service.dart';

/// A scored item, retained for the existing result-sheet preview.
class AnalysedItem {
  const AnalysedItem({
    required this.name,
    required this.score,
    required this.highlights,
  });

  final String name;
  final int score;
  final List<String> highlights;
}

/// Result of one product photo analysis.
class AnalysisResult {
  const AnalysisResult({
    this.identification,
    this.error,
    this.item,
    this.alternative,
  });

  final ProductIdentification? identification;
  final String? error;

  /// Legacy preview fields, used only by older callers of the result sheet.
  final AnalysedItem? item;
  final AnalysedItem? alternative;
}

/// Sends a camera JPEG to the product identification service.
class CameraAnalysis {
  CameraAnalysis({ProductIdentificationProvider? service})
    : _ownsService = service == null,
      _service = service ?? const ApiProductIdentification();

  final ProductIdentificationProvider _service;
  final bool _ownsService;

  Future<AnalysisResult> analyse(Uint8List jpegBytes) async {
    debugPrint('CameraAnalysis: identifying ${jpegBytes.length} JPEG bytes');
    final identification = await _service.identify(jpegBytes);
    return AnalysisResult(identification: identification);
  }

  /// Releases the API client when this analysis created it.
  void dispose() {
    if (_ownsService) _service.close();
  }
}
