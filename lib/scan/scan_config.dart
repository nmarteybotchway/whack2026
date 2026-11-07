/// How the scan page feeds camera frames to [CameraAnalysis].
enum ScanMode {
  /// Preview frames are watched by a FrameGate, and a photo is sent
  /// automatically once an item has been held steady in view for a second.
  stream,

  /// The preview is live, but a frame is only sent when the capture button
  /// is pressed.
  button,
}

/// Compile-time choice of scan mode. Change this and rebuild to switch.
const scanMode = ScanMode.button;
