import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../assistant/assistant_controller.dart';
import '../assistant/assistant_page.dart';
import '../food/food_recommendation_service.dart';
import '../food_news.dart';
import 'analysis_result_sheet.dart';
import 'camera_analysis.dart';
import 'product_identification_service.dart';
import 'shopping_companion_briefing.dart';
import 'shopping_companion_controller.dart';
import 'shopping_companion_overlay.dart';

/// Full-screen camera page for photographing and identifying packaged items.
///
/// Photos are captured on demand from the capture button or assistant.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.userId, this.demo = false, this.assistant});

  final String? userId;
  final AssistantController? assistant;

  /// Retained for source compatibility with the old gate demo route.
  @Deprecated('ScanPage now captures only on demand.')
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
  bool _assistantProductUpdatePending = false;
  int _foregroundEpoch = 0;

  /// True while a still photo is being analysed.
  bool _analysing = false;

  bool get _interactionBusy {
    final companion = _companion;
    return companion != null &&
        companion.active &&
        (companion.committing || companion.pendingAction != null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final assistant = widget.assistant;
    assistant?.setCameraPhotoRequester(_requestCameraPhoto);
    assistant?.addListener(_onAssistantChanged);
    final userId = widget.userId;
    if (assistant != null && userId != null) {
      final briefings = ProductBriefingService(userId: userId);
      _companion = ShoppingCompanionController(
        assistant: assistant,
        briefingLoader: briefings.describe,
        onShowDetails: _showDetails,
      )..addListener(_onCompanionChanged);
    }
    unawaited(_restoreScan());
    if (ScanPage.isSupported) _startCamera();
  }

  Future<void> _restoreScan() async {
    if (widget.userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('scan.last.${widget.userId}');
      if (!mounted || raw == null || _lastResult != null || _analysing) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final product = ProductIdentification.fromJson(
        saved['product'] as Map<String, dynamic>,
      );
      setState(() {
        _lastResult = AnalysisResult(identification: product);
        _lastScanAt = DateTime.tryParse(saved['scannedAt'] as String);
      });
      if (_companion?.active ?? false) {
        unawaited(_companion!.updateProduct(product, scannedAt: _lastScanAt));
      }
    } catch (_) {
      // An invalid snapshot should never prevent opening the camera.
    }
  }

  Future<void> _saveScan() async {
    final product = _lastResult?.identification;
    if (widget.userId == null || product == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'scan.last.${widget.userId}',
        jsonEncode({
          'product': product.toJson(),
          'scannedAt': _lastScanAt?.toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _companion?.removeListener(_onCompanionChanged);
    _companion?.dispose();
    widget.assistant?.removeListener(_onAssistantChanged);
    widget.assistant?.setCameraPhotoRequester(null);
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
      _companion?.suspendForBackground();
      widget.assistant?.suspend();
    }
    if (state == AppLifecycleState.resumed) {
      _companion?.resumeFromBackground();
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

  void _onAssistantChanged() {
    final companion = _companion;
    final result = _lastResult?.identification;
    if (_assistantProductUpdatePending &&
        !(widget.assistant?.busy ?? false) &&
        companion?.active == true) {
      _assistantProductUpdatePending = false;
      unawaited(companion!.updateProduct(result, scannedAt: _lastScanAt));
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

  void _captureFromButton() {
    unawaited(_capture().then<void>((_) {}));
  }

  Future<Map<String, Object?>> _requestCameraPhoto() =>
      _capture(fromAssistant: true);

  Future<Map<String, Object?>> _capture({bool fromAssistant = false}) async {
    final controller = _controller;
    final analysis = _analysis;
    if (controller == null ||
        analysis == null ||
        _analysing ||
        _showingDetails ||
        _interactionBusy) {
      return {'available': false, 'error': 'Camera is busy or unavailable.'};
    }
    _analysing = true;
    final scannedAt = DateTime.now().toUtc();
    setState(() {});
    AnalysisResult result;
    try {
      if (!fromAssistant) await _companion?.scanning();
      if (!mounted || _controller != controller) {
        _analysing = false;
        return {'available': false, 'error': 'Camera is no longer available.'};
      }
      if (!fromAssistant) {
        widget.assistant?.setCurrentProduct({
          'status': 'scanning',
          'scannedAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
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
      _lastResult = result;
      _lastScanAt = scannedAt;
      unawaited(_saveScan());
      final product = result.identification;
      if (!fromAssistant) {
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
      }
      Map<String, Object?>? assessment;
      if (fromAssistant && (_companion?.active ?? false)) {
        // Keep the assistant's tool turn alive. Applying this product to the
        // companion is deferred until that turn finishes because a new
        // product normally cancels an in-flight companion turn.
        _assistantProductUpdatePending = true;
        if (product != null) assessment = await _companion!.assess(product);
      } else if (_companion?.active ?? false) {
        unawaited(_companion!.updateProduct(product, scannedAt: scannedAt));
      } else if (!fromAssistant &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        await _showResult(result);
      }
      return {
        'available': product != null,
        'scannedAt': scannedAt.toIso8601String(),
        if (product != null) ...{
          'status': product.status,
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
        'assessment': ?assessment,
        if (result.error != null) 'error': result.error,
      };
    }
    return {'available': false, 'error': 'Camera is no longer available.'};
  }

  Future<bool> _showResult(AnalysisResult result) async {
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
    if (tab != null && mounted) {
      Navigator.of(context).pop(tab);
      return true;
    }
    return false;
  }

  Future<void> _showDetails() async {
    final result = _lastResult;
    if (result == null || _showingDetails || _analysing) return;
    final wasActive = _companion?.active ?? false;
    final foregroundEpoch = _foregroundEpoch;
    _showingDetails = true;
    await _companion?.pause();
    if (!mounted) return;
    final leaving = await _showResult(result);
    _showingDetails = false;
    if (!mounted || leaving) return;
    if (wasActive &&
        foregroundEpoch == _foregroundEpoch &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await _companion?.start();
    }
  }

  Future<void> _openAssistant() async {
    final assistant = widget.assistant;
    if (assistant == null || _analysing) return;
    await _companion?.pause();
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan'),
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
                    onPressed: _captureFromButton,
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
