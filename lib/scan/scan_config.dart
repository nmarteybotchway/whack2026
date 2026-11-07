/// How the scan page feeds camera frames to [CameraAnalysis].
enum ScanMode {
  /// Every frame from the camera is sent for analysis (frames that arrive
  /// while an analysis is still running are dropped).
  stream,

  /// The preview is live, but a frame is only sent when the capture button
  /// is pressed.
  button,
}

/// Compile-time choice of scan mode. Change this and rebuild to switch.
const scanMode = ScanMode.button;
