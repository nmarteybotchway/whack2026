import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'analysis_result_sheet.dart';
import 'camera_analysis.dart';

/// Full-screen camera page for photographing and identifying packaged items.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.userId});

  final String? userId;

  /// The camera is supported on Android and iOS.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraAnalysis? _analysis;
  String? _error;

  /// True while a still photo is being analysed.
  bool _analysing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ScanPage.isSupported) _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera must be released when the app goes to the background. Skip
    // this while the camera is still starting: the permission dialog also
    // makes the app inactive, and disposing mid-initialise breaks the plugin.
    final initialized = _controller?.value.isInitialized ?? false;
    if (state == AppLifecycleState.inactive && initialized) {
      _stopCamera();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('noCamera', 'No camera found');
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      final analysis = CameraAnalysis();
      setState(() {
        _analysis = analysis;
        _error = null;
      });
    } catch (e) {
      // A newer start (or dispose) has replaced this controller; ignore.
      if (_controller != controller) return;
      _stopCamera();
      if (mounted) {
        setState(
          () => _error = e is CameraException
              ? e.description ?? e.code
              : e.toString(),
        );
      }
    }
  }

  void _stopCamera() {
    _controller?.dispose();
    _controller = null;
    _analysis?.dispose();
    _analysis = null;
  }

  Future<void> _capture() async {
    final controller = _controller;
    final analysis = _analysis;
    if (controller == null || analysis == null || _analysing) return;
    _analysing = true;
    setState(() {});
    AnalysisResult result;
    try {
      final photo = await controller.takePicture();
      result = await analysis.analyse(await photo.readAsBytes());
    } catch (error) {
      debugPrint('Product scan failed: $error');
      result = const AnalysisResult(
        error: 'Could not identify this photo. Check your connection and try again.',
      );
    } finally {
      _analysing = false;
      if (mounted) setState(() {});
    }

    if (mounted) {
      await showAnalysisResult(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!ScanPage.isSupported) {
      return const _Message('Scanning is only supported on Android and iOS.');
    }
    if (_error != null) return _Message('Camera error: $_error');

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(controller)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Center(
            child: _CaptureButton(busy: _analysing, onPressed: _capture),
          ),
        ),
      ],
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 72,
      child: FloatingActionButton(
        tooltip: 'Analyse frame',
        shape: const CircleBorder(),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        onPressed: busy ? null : onPressed,
        child: busy
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.camera_alt, size: 32),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
