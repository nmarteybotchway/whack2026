import 'dart:async';

import 'package:flutter/foundation.dart';

import '../assistant/assistant_controller.dart';
import '../assistant/assistant_models.dart';
import 'shopping_companion_briefing.dart';
import 'product_identification_service.dart';

/// Foreground, explicit-action coordinator for the camera shopping companion.
/// It shares the app's assistant session but never starts the microphone itself.
class ShoppingCompanionController extends ChangeNotifier {
  ShoppingCompanionController({
    required this.assistant,
    required this.briefingLoader,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    assistant.addListener(_onAssistantChanged);
  }

  final AssistantController assistant;
  final Future<ProductBriefing> Function(ProductIdentification) briefingLoader;
  final DateTime Function() _now;
  static const Duration _repeatCooldown = Duration(seconds: 60);

  bool active = false;
  bool loading = false;
  String? error;
  String draft = '';
  ProductBriefing? briefing;
  AssistantMessage? reply;

  ProductIdentification? _latestProduct;
  String? _latestKey;
  DateTime? _scannedAt;
  final Map<String, DateTime> _announcedAt = {};
  ProductBriefing? _queuedBriefing;
  _BriefingRequest? _queuedLoad;
  Future<void>? _loaderTask;
  String? _activeLoadKey;
  int _generation = 0;
  bool _submitting = false;
  bool _ready = false;
  bool _disposed = false;

  bool get busy => assistant.busy || (active && !_ready);
  bool get listening => assistant.listening;
  bool get speaking => assistant.speaking;
  bool get committing => assistant.committing;
  AssistantAction? get pendingAction => assistant.pendingAction;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Map<String, Object?> _productMap(ProductIdentification p) => {
    'status': p.status,
    'name': p.displayName,
    'productName': p.productName,
    'source': 'camera',
    'scannedAt': _scannedAt?.toUtc().toIso8601String(),
    'brand': p.brand,
    'variant': p.variant,
    'packageSize': p.packageSize,
    'sku': p.sku,
    'gtin': p.gtin,
    'catalogProductId': p.catalogProductId,
    'confidence': p.confidence,
    'productNameConfidence': p.productNameConfidence,
    'brandConfidence': p.brandConfidence,
    'variantConfidence': p.variantConfidence,
    'skuConfidence': p.skuConfidence,
    'gtinConfidence': p.gtinConfidence,
    'evidence': p.evidence,
    'uncertainties': p.uncertainties,
  };

  Future<void> start() async {
    if (_disposed || active) return;
    active = true;
    _ready = false;
    _notify();
    await assistant.initialize();
    if (_disposed || !active) return;
    _ready = true;
    assistant.resumeForeground();
    final product = _latestProduct;
    if (product != null &&
        !loading &&
        (briefing == null || !_recentlyBriefed(_latestKey!))) {
      await updateProduct(product);
    }
    await _drainAnnouncement();
    _notify();
  }

  Future<void> stop() async {
    active = false;
    _ready = false;
    _generation++;
    loading = false;
    _queuedBriefing = null;
    _queuedLoad = null;
    _notify();
    if (assistant.busy &&
        assistant.pendingAction == null &&
        !assistant.committing) {
      await assistant.cancelTurn();
    }
    await assistant.stopListening();
    await assistant.stopAudio();
    _notify();
  }

  Future<void> pause() => stop();

  Future<void> scanning() async {
    _generation++;
    loading = false;
    error = null;
    reply = null;
    briefing = null;
    _latestProduct = null;
    _latestKey = null;
    _scannedAt = null;
    _queuedBriefing = null;
    _queuedLoad = null;
    assistant.setCurrentProduct(null);
    if (assistant.busy &&
        assistant.pendingAction == null &&
        !assistant.committing) {
      await assistant.cancelTurn();
    }
    await assistant.stopAudio();
    _notify();
  }

  Future<void> updateProduct(
    ProductIdentification? product, {
    DateTime? scannedAt,
  }) async {
    if (_disposed) return;
    if (product == null) {
      _generation++;
      _latestProduct = null;
      _latestKey = null;
      _scannedAt = null;
      briefing = null;
      reply = null;
      loading = false;
      _queuedBriefing = null;
      _queuedLoad = null;
      assistant.setCurrentProduct(null);
      if (assistant.busy &&
          assistant.pendingAction == null &&
          !assistant.committing) {
        await assistant.cancelTurn();
      }
      await assistant.stopAudio();
      _notify();
      return;
    }

    final key = productKeyFor(product);
    final isSame = key == _latestKey;
    _scannedAt = scannedAt ?? (isSame ? _scannedAt : null) ?? _now();
    _latestProduct = product;
    _latestKey = key;
    assistant.setCurrentProduct(_productMap(product));
    if (!isSame) {
      _generation++;
      reply = null;
      briefing = null;
      _queuedBriefing = null;
      if (assistant.busy &&
          assistant.pendingAction == null &&
          !assistant.committing) {
        await assistant.cancelTurn();
      }
      await assistant.stopAudio();
    }
    final inCooldown = _recentlyBriefed(key);
    if (isSame &&
        ((loading && _activeLoadKey == key) || _queuedLoad?.key == key)) {
      _notify();
      return;
    }
    if (inCooldown && briefing?.key == key) {
      _notify();
      return;
    }
    if (active) await _loadBriefing(product, key);
    _notify();
  }

  bool _recentlyBriefed(String key) =>
      _announcedAt[key] != null &&
      _now().difference(_announcedAt[key]!) < _repeatCooldown;

  Future<void> _loadBriefing(ProductIdentification product, String key) async {
    _queuedLoad = _BriefingRequest(product, key);
    loading = true;
    error = null;
    _notify();
    final existing = _loaderTask;
    if (existing != null) return existing;
    final task = _drainLoads();
    _loaderTask = task;
    return task;
  }

  Future<void> _drainLoads() async {
    while (!_disposed && _queuedLoad != null) {
      final request = _queuedLoad!;
      _queuedLoad = null;
      final generation = _generation;
      _activeLoadKey = request.key;
      try {
        final result = await briefingLoader(request.product)
            .timeout(const Duration(seconds: 15));
        if (!_disposed &&
            generation == _generation &&
            active &&
            request.key == _latestKey) {
          briefing = result;
          if (!_recentlyBriefed(request.key)) _queuedBriefing = result;
          _notify();
          await _drainAnnouncement();
        }
      } catch (_) {
        if (!_disposed &&
            generation == _generation &&
            request.key == _latestKey) {
          error = 'Product briefing is unavailable right now.';
        }
      }
      _activeLoadKey = null;
    }
    loading = false;
    _loaderTask = null;
    _notify();
  }

  bool get _assistantAvailable =>
      _ready &&
      !assistant.busy &&
      !assistant.listening &&
      assistant.pendingAction == null &&
      !assistant.committing &&
      !assistant.speaking &&
      !_submitting &&
      draft.trim().isEmpty;

  Future<void> _drainAnnouncement() async {
    final pending = _queuedBriefing;
    final product = _latestProduct;
    final key = _latestKey;
    if (!active ||
        pending == null ||
        product == null ||
        key == null ||
        !_assistantAvailable) {
      return;
    }
    _queuedBriefing = null;
    final generation = _generation;
    final text = [
      pending.text,
      for (final alternative in pending.alternatives)
        '${alternative.name}${alternative.detail.isEmpty ? '' : ': ${alternative.detail}'}',
    ].where((part) => part.trim().isNotEmpty).join('\n');
    final images = pending.alternatives
        .map((alternative) => alternative.image)
        .whereType<AssistantImage>()
        .toList();
    await assistant.announceCameraBriefing(
      text: text,
      product: _productMap(product),
      images: images,
    );
    if (_disposed ||
        !active ||
        generation != _generation ||
        key != _latestKey) {
      return;
    }
    reply = assistant.messages.isEmpty ? null : assistant.messages.last;
    _announcedAt[key] = _now();
    if (_announcedAt.length > 20) _announcedAt.remove(_announcedAt.keys.first);
    _notify();
    unawaited(
      assistant.speakAnnouncement(
        pending.text,
        isCurrent: () =>
            !_disposed &&
            active &&
            generation == _generation &&
            key == _latestKey &&
            !assistant.busy &&
            !assistant.listening &&
            assistant.pendingAction == null &&
            !assistant.committing &&
            !_submitting &&
            draft.trim().isEmpty,
      ),
    );
  }

  void _onAssistantChanged() {
    if (_disposed) return;
    _notify();
    if (_assistantAvailable && _queuedBriefing != null) {
      unawaited(_drainAnnouncement());
    }
  }

  void setDraft(String value) {
    draft = value;
    _notify();
    if (_assistantAvailable && _queuedBriefing != null) {
      unawaited(_drainAnnouncement());
    }
  }

  Future<void> submit([String? text]) async {
    if (text != null) draft = text;
    final query = draft.trim();
    final key = _latestKey;
    if (!active ||
        query.isEmpty ||
        busy ||
        pendingAction != null ||
        committing) {
      return;
    }
    final generation = _generation;
    final hasProduct = _latestProduct != null && key != null;
    final startIndex = assistant.messages.length;
    _submitting = true;
    draft = '';
    _notify();
    try {
      await assistant.sendCompanion(
        query,
        product: hasProduct ? _productMap(_latestProduct!) : null,
      );
    } finally {
      _submitting = false;
    }
    if (_disposed ||
        !active ||
        generation != _generation ||
        (hasProduct && key != _latestKey)) {
      return;
    }
    for (var i = assistant.messages.length - 1; i >= startIndex; i--) {
      if (assistant.messages[i].role == 'assistant') {
        reply = assistant.messages[i];
        break;
      }
    }
    _notify();
  }

  Future<void> listen() async {
    if (!active || busy || pendingAction != null || committing) return;
    await assistant.startListening((transcript) {
      if (!_disposed && active) {
        draft = transcript;
        _notify();
      }
    });
  }

  Future<void> stopListening() => assistant.stopListening();
  Future<void> stopSpeech() => assistant.stopAudio();
  Future<void> confirmAction() async {
    final start = assistant.messages.length;
    await assistant.confirmAction();
    for (var i = assistant.messages.length - 1; i >= start; i--) {
      if (assistant.messages[i].role == 'assistant') {
        reply = assistant.messages[i];
        break;
      }
    }
    _notify();
  }

  Future<void> cancelAction() async {
    await assistant.cancelAction();
    _notify();
  }

  Future<void> requestAlternatives() {
    if (_latestProduct == null) {
      error = 'Scan a product first to ask for alternatives.';
      _notify();
      return Future.value();
    }
    draft = 'What are the suitable alternatives for this product?';
    return submit();
  }

  Future<void> retryBriefing() async {
    final product = _latestProduct;
    final key = _latestKey;
    if (!active || product == null || key == null || loading) return;
    await _loadBriefing(product, key);
  }

  Future<void> replay() async {
    final text = reply?.text ?? briefing?.text;
    if (active && text != null && text.isNotEmpty) await assistant.replay(text);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    assistant.removeListener(_onAssistantChanged);
    super.dispose();
  }
}

class _BriefingRequest {
  const _BriefingRequest(this.product, this.key);
  final ProductIdentification product;
  final String key;
}
