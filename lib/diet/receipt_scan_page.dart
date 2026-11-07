import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_parser.dart';
import 'receipt_review_sheet.dart';
import 'receipt_store.dart';

/// Camera page that photographs a receipt, reads it with the on-device ML Kit
/// text recogniser, and stores the items in the user's Firestore account.
///
/// Resolves to the number of items saved when the receipt is stored, or null
/// if the user backs out.
class ReceiptScanPage extends StatefulWidget {
  const ReceiptScanPage({super.key, required this.userId});

  final String userId;

  /// The camera plugin is only available on Android and iOS.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptScanPageState extends State<ReceiptScanPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;

  /// True while a photo is being taken, read, or saved.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ReceiptScanPage.isSupported) _startCamera();
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
        // Receipt text needs resolution more than frame rate.
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      setState(() => _error = null);
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
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final photo = await controller.takePicture();
      final items = await _recognise(photo);
      if (!mounted) return;

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'No items found. Make sure the whole receipt fills the frame '
            'and is well lit, then try again.',
          ),
        ));
        return;
      }

      final reviewed = await showReceiptReview(context, items);
      if (reviewed == null || reviewed.isEmpty || !mounted) return;

      await ReceiptStore(widget.userId).save(reviewed);
      if (!mounted) return;
      Navigator.of(context).pop(reviewed.length);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs the on-device ML Kit text recogniser over the photo and parses the
  /// receipt text into items.
  Future<List<ReceiptItem>> _recognise(XFile photo) async {
    final inputImage = InputImage.fromFilePath(photo.path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(inputImage);
      return parseReceiptItems(result.text);
    } finally {
      recognizer.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan receipt'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!ReceiptScanPage.isSupported) {
      return const _Message('Receipt scanning is only supported on Android and iOS.');
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
        const Positioned(
          left: 0,
          right: 0,
          bottom: 110,
          child: Center(
            child: Text(
              'Fit the whole receipt in the frame',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Center(
            child: SizedBox.square(
              dimension: 72,
              child: FloatingActionButton(
                tooltip: 'Capture receipt',
                shape: const CircleBorder(),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                onPressed: _busy ? null : _capture,
                child: _busy
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.receipt_long, size: 32),
              ),
            ),
          ),
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
