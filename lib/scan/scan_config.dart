/// Legacy scan mode setting retained for source compatibility.
enum ScanMode {
  /// Legacy mode. ScanPage now captures only on demand.
  stream,

  /// Capture when requested by the user or assistant.
  button,
}

/// Retained for callers that still read the old compile-time setting.
const scanMode = ScanMode.button;
