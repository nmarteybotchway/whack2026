import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../assistant/assistant_controller.dart';
import '../assistant/assistant_page.dart';
import '../food/food_recommendation_service.dart';
import '../food_news.dart';
import 'analysis_result_sheet.dart';
import 'camera_analysis.dart';
import 'frame_gate.dart';
import 'scan_config.dart';

/// Full-screen camera page for photographing and identifying packaged items.
///
/// In [ScanMode.stream] the preview frames go through a [FrameGate], and a
/// photo is sent automatically once an item has been held steady for a
/// second. The capture button works in both modes.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.userId, this.demo = false, this.assistant});

  final String? userId;
  final AssistantController? assistant;

  /// Test the auto-capture without spending API calls: the stream always
  /// runs, a capture just flashes the screen red, and the gate's numbers are
  /// shown on screen.
  final bool demo;

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

  final _gate = FrameGate();
  final _clock = Stopwatch()..start();
  GateStatus _gateStatus = const GateStatus(GateState.warmingUp);

  /// When the last streamed frame was checked; frames are checked at most
  /// every [_frameInterval] to keep the gate cheap.
  Duration _lastFrameAt = Duration.zero;
  static const _frameInterval = Duration(milliseconds: 100);

  /// Demo mode: true while the red flash is showing, and how many captures
  /// have fired.
  bool _flashing = false;
  int _demoCaptures = 0;

  bool get _streaming => widget.demo || scanMode == ScanMode.stream;

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
      _gate.reset();
      await _startStream();
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

  Future<void> _startStream() async {
    final controller = _controller;
    if (!_streaming ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream(_onFrame);
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  void _onFrame(CameraImage frame) {
    if (_analysing) return;
    final now = _clock.elapsed;
    if (now - _lastFrameAt < _frameInterval) return;
    _lastFrameAt = now;

    // Android streams YUV, whose first plane is brightness; iOS streams BGRA,
    // where green is a good stand-in for brightness.
    final plane = frame.planes.first;
    final isBgra = frame.format.group == ImageFormatGroup.bgra8888;
    final status = _gate.addFrame(
      plane.bytes,
      width: frame.width,
      height: frame.height,
      rowStride: plane.bytesPerRow,
      pixelStride: isBgra ? 4 : (plane.bytesPerPixel ?? 1),
      channelOffset: isBgra ? 1 : 0,
      timestamp: now,
    );
    if (kDebugMode && status.state != _gateStatus.state) {
      debugPrint('FrameGate: $status');
    }
    if (mounted) setState(() => _gateStatus = status);
    if (status.state == GateState.ready) _capture();
  }

  void _stopCamera() {
    _controller?.dispose();
    _controller = null;
    _analysis?.dispose();
    _analysis = null;
  }

  Future<void> _capture() async {
    if (widget.demo) return _flash();
    final controller = _controller;
    final analysis = _analysis;
    if (controller == null || analysis == null || _analysing) return;
    widget.assistant?.setCurrentProduct({
      'status': 'scanning',
      'scannedAt': DateTime.now().toUtc().toIso8601String(),
    });
    _analysing = true;
    setState(() {});
    AnalysisResult result;
    try {
      // Android cannot take a picture while streaming preview frames.
      await _stopStream();
      final photo = await controller.takePicture();
      result = await analysis.analyse(await photo.readAsBytes());
    } catch (error) {
      debugPrint('Product scan failed: $error');
      result = const AnalysisResult(
        error: 'Could not identify this photo. Check your connection and try again.',
      );
    } finally {
      // Start the cooldown from the answer, not from when the frame passed.
      _gate.startCooldown(_clock.elapsed);
      _analysing = false;
      if (mounted) setState(() {});
    }

    if (mounted) {
      final product = result.identification;
      widget.assistant?.setCurrentProduct({
        'status': product?.status ?? 'unavailable',
        'scannedAt': DateTime.now().toUtc().toIso8601String(),
        if (product != null) ...{
          'name': product.displayName,
          'productName': product.productName,
          'brand': product.brand,
          'variant': product.variant,
          'packageSize': product.packageSize,
          'gtin': product.gtin,
          'catalogProductId': product.catalogProductId,
          'confidence': product.confidence,
          'evidence': product.evidence,
          'uncertainties': product.uncertainties,
        },
        if (result.error != null) 'error': result.error,
      });
      final tab = await showAnalysisResult(
        context,
        result,
        newsService: FoodNewsService(),
        recommendationService: widget.userId == null
            ? null
            : FoodRecommendationService(),
        userId: widget.userId,
        assistant: widget.assistant,
      );
      // The user picked a home-page tab from the result sheet's navigation
      // bar: pop back home and land on it.
      if (tab != null && mounted) {
        Navigator.of(context).pop(tab);
        return;
      }
    }
    if (mounted && _controller == controller) await _startStream();
  }

  Future<void> _openAssistant() async {
    final assistant = widget.assistant;
    if (assistant == null || _analysing) return;
    await _stopStream();
    await assistant.initialize();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Shopping assistant')),
          body: AssistantPage(controller: assistant),
        ),
      ),
    );
    await assistant.suspend();
    if (mounted) await _startStream();
  }

  /// Demo stand-in for an API call: flash red and start the cooldown.
  Future<void> _flash() async {
    _gate.startCooldown(_clock.elapsed);
    setState(() {
      _flashing = true;
      _demoCaptures++;
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => _flashing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.demo ? 'Scan gate demo' : 'Scan'),
        actions: [
          if (widget.assistant != null)
            IconButton(
              tooltip: 'Ask about this product',
              onPressed: _analysing ? null : _openAssistant,
              icon: const Icon(Icons.chat_bubble_outline),
            ),
        ],
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
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _flashing ? 0.6 : 0,
            duration: const Duration(milliseconds: 120),
            child: const ColoredBox(color: Colors.red),
          ),
        ),
        if (_streaming)
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Center(
              child: _GateIndicator(
                status: _gateStatus,
                busy: _analysing,
                showMetrics: kDebugMode || widget.demo,
                captures: widget.demo ? _demoCaptures : null,
              ),
            ),
          ),
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
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: busy ? null : onPressed,
        child: busy
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.camera_alt, size: 32),
      ),
    );
  }
}

/// Tells the user what the auto-capture is waiting for.
class _GateIndicator extends StatelessWidget {
  const _GateIndicator({
    required this.status,
    required this.busy,
    required this.showMetrics,
    this.captures,
  });

  final GateStatus status;
  final bool busy;
  final bool showMetrics;

  /// Demo mode: how many captures have fired.
  final int? captures;

  @override
  Widget build(BuildContext context) {
    final label = busy
        ? 'Identifying…'
        : switch (status.state) {
            GateState.warmingUp => 'Starting…',
            GateState.inPocket => 'Camera covered',
            GateState.coolingDown => 'Ready again shortly…',
            GateState.moving => 'Hold the camera steady',
            GateState.noItem => 'Show an item to the camera',
            GateState.alreadySent => 'Show another item',
            GateState.holding || GateState.ready => 'Hold still…',
          };
    final showProgress =
        !busy &&
        (status.state == GateState.holding ||
            status.state == GateState.coolingDown);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Chip(
          avatar: showProgress
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    value: status.progress,
                    strokeWidth: 3,
                  ),
                )
              : null,
          label: Text(label),
        ),
        if (showMetrics)
          Text(
            [
              if (captures != null) 'captures=$captures',
              status.toString(),
            ].join(' '),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
      ],
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
