import 'dart:async';

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
import 'shopping_companion_briefing.dart';
import 'shopping_companion_controller.dart';
import 'shopping_companion_overlay.dart';

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
  ShoppingCompanionController? _companion;
  AnalysisResult? _lastResult;
  DateTime? _lastScanAt;
  bool _companionWasActive = false;
  bool _showingDetails = false;
  int _foregroundEpoch = 0;
  Future<void> _streamSync = Future<void>.value();

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

  bool get _streaming =>
      widget.demo ||
      scanMode == ScanMode.stream ||
      (_companion?.active ?? false);

  bool get _interactionBusy {
    final companion = _companion;
    return companion != null &&
        companion.active &&
        (companion.listening ||
            companion.committing ||
            companion.pendingAction != null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final assistant = widget.assistant;
    final userId = widget.userId;
    if (assistant != null && userId != null && !widget.demo) {
      final briefings = ProductBriefingService(userId: userId);
      _companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: briefings.describe,
      )..addListener(_onCompanionChanged);
    }
    if (ScanPage.isSupported) _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _companion?.removeListener(_onCompanionChanged);
    _companion?.dispose();
    widget.assistant?.suspend();
    _stopCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final interrupted =
        state == AppLifecycleState.inactive &&
        !(widget.assistant?.requestingMicrophonePermission ?? false);
    if (interrupted ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foregroundEpoch++;
      _companion?.pause();
      widget.assistant?.suspend();
    }
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

  void _onCompanionChanged() {
    if (!mounted) return;
    final active = _companion?.active ?? false;
    if (active != _companionWasActive) {
      _companionWasActive = active;
      _gate.reset();
      _streamSync = _streamSync.then((_) async {
        if (!mounted) return;
        try {
          if (_streaming && !_analysing && !_showingDetails) {
            await _startStream();
          } else {
            await _stopStream();
          }
        } on CameraException {
          // Manual capture remains available if preview streaming cannot start.
        }
      });
      if (active && _lastResult?.identification != null) {
        unawaited(
          _companion!.updateProduct(
            _lastResult!.identification,
            scannedAt: _lastScanAt,
          ),
        );
      }
    }
    setState(() {});
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
    final companion = _companion;
    if (_analysing ||
        _showingDetails ||
        (companion != null &&
            companion.active &&
            (companion.loading ||
                companion.busy ||
                companion.listening ||
                companion.speaking ||
                companion.draft.trim().isNotEmpty ||
                companion.pendingAction != null))) {
      return;
    }
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
    if (controller == null ||
        analysis == null ||
        _analysing ||
        _showingDetails ||
        _interactionBusy) {
      return;
    }
    _analysing = true;
    final scannedAt = DateTime.now().toUtc();
    setState(() {});
    await _companion?.scanning();
    if (!mounted || _controller != controller) {
      _analysing = false;
      return;
    }
    widget.assistant?.setCurrentProduct({
      'status': 'scanning',
      'scannedAt': DateTime.now().toUtc().toIso8601String(),
    });
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

    if (mounted && _controller == controller) {
      _lastResult = result;
      _lastScanAt = scannedAt;
      final product = result.identification;
      widget.assistant?.setCurrentProduct({
        'status': product?.status ?? 'unavailable',
        'scannedAt': scannedAt.toIso8601String(),
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
      if (_companion?.active ?? false) {
        unawaited(_companion!.updateProduct(product, scannedAt: scannedAt));
      } else {
        await _showResult(result);
      }
    }
    if (mounted && _controller == controller) await _startStream();
  }

  Future<void> _showResult(AnalysisResult result) => showAnalysisResult(
    context,
    result,
    newsService: FoodNewsService(),
    recommendationService: widget.userId == null
        ? null
        : FoodRecommendationService(),
    userId: widget.userId,
  );

  Future<void> _showDetails() async {
    final result = _lastResult;
    if (result == null || _showingDetails || _analysing) return;
    final wasActive = _companion?.active ?? false;
    final foregroundEpoch = _foregroundEpoch;
    _showingDetails = true;
    await _companion?.pause();
    await _streamSync;
    await _stopStream();
    if (!mounted) return;
    await _showResult(result);
    _showingDetails = false;
    if (!mounted) return;
    if (wasActive &&
        foregroundEpoch == _foregroundEpoch &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await _companion?.start();
    }
    if (mounted && _streaming) await _startStream();
  }

  Future<void> _openAssistant() async {
    final assistant = widget.assistant;
    if (assistant == null || _analysing) return;
    await _companion?.pause();
    await _streamSync;
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
              tooltip: 'Open full conversation',
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final panelHeight = keyboardOpen
            ? (constraints.maxHeight - 24).clamp(0.0, constraints.maxHeight)
            : (constraints.maxHeight - 132).clamp(
                0.0,
                constraints.maxHeight * .60,
              );
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
            if (_companion case final companion?)
              Positioned(
                left: 12,
                right: 12,
                bottom: keyboardOpen ? 12 : 120,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: panelHeight),
                  child: ShoppingCompanionOverlay(
                    controller: companion,
                    scanning: _analysing,
                    onShowDetails: _lastResult == null ? null : _showDetails,
                  ),
                ),
              ),
            if (!keyboardOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Center(
                  child: _CaptureButton(
                    busy: _analysing || _interactionBusy,
                    onPressed: _capture,
                  ),
                ),
              ),
          ],
        );
      },
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
