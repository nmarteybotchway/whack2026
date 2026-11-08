import 'dart:async';

import 'package:flutter/foundation.dart';

import '../assistant/assistant_controller.dart';
import '../assistant/assistant_models.dart';
import 'product_identification_service.dart';
import 'shopping_companion_briefing.dart';

/// Owns the foreground voice session while [AssistantController] owns the
/// shared conversation, model turns, tools, and audio implementation.
class ShoppingCompanionController extends ChangeNotifier {
  ShoppingCompanionController({
    required this.assistant,
    required this.briefingLoader,
    this.onShowDetails,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    assistant.addListener(_onAssistantChanged);
  }

  final AssistantController assistant;
  final Future<ProductBriefing> Function(ProductIdentification) briefingLoader;
  final void Function()? onShowDetails;
  final DateTime Function() _now;

  static const _greeting =
      'Hi, I’m your shopping companion. Ask me about a product, its ingredients, or suitable alternatives.';
  static const _silenceDelay = Duration(seconds: 2);
  static const _repeatCooldown = Duration(seconds: 60);

  bool active = false;
  bool loading = false;
  String? error;
  String draft = '';
  ProductBriefing? briefing;
  AssistantMessage? reply;

  ProductIdentification? _product;
  String? _productKey;
  DateTime? _scannedAt;
  final Map<String, DateTime> _announcedAt = {};
  int _session = 0;
  int _command = 0;
  int _submission = 0;
  Future<void>? _stopping;
  int _productEpoch = 0;
  int _recognition = 0;
  bool _ready = false;
  bool _micPaused = false;
  bool _scanPaused = false;
  bool _micStarting = false;
  bool _submitting = false;
  bool _greetingPlaying = false;
  bool _interrupting = false;
  bool _disposed = false;
  Timer? _silenceTimer;
  Timer? _listenTimer;
  ProductBriefing? _pendingBriefing;

  /// Assessments loaded for assistant-requested photos, keyed by product.
  final Map<String, ProductBriefing> _assessed = {};

  bool get busy => assistant.busy || (active && !_ready);
  bool get listening => assistant.listening;
  bool get speaking => assistant.speaking;
  bool get preparingSpeech => assistant.preparingSpeech;
  bool get committing => assistant.committing;
  bool get micPaused => _micPaused;
  String? get speechError =>
      assistant.speechError ??
      (error != null &&
              (error!.contains('Speech recognition') ||
                  error!.startsWith('error_'))
          ? error
          : null);
  AssistantAction? get pendingAction => assistant.pendingAction;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Map<String, Object?> _productMap(ProductIdentification product) => {
    if (briefing case final b? when b.key == productKeyFor(product))
      'assessment': b.facts,
    'status': product.status,
    'name': product.displayName,
    'productName': product.productName,
    'source': 'camera',
    'scannedAt': _scannedAt?.toUtc().toIso8601String(),
    'brand': product.brand,
    'variant': product.variant,
    'packageSize': product.packageSize,
    'sku': product.sku,
    'gtin': product.gtin,
    'catalogProductId': product.catalogProductId,
    'confidence': product.confidence,
    'productNameConfidence': product.productNameConfidence,
    'brandConfidence': product.brandConfidence,
    'variantConfidence': product.variantConfidence,
    'skuConfidence': product.skuConfidence,
    'gtinConfidence': product.gtinConfidence,
    'evidence': product.evidence,
    'uncertainties': product.uncertainties,
  };

  Future<void> start() async {
    final command = ++_command;
    if (_disposed || active) return;
    await _stopping;
    if (_disposed || active || command != _command) return;
    active = true;
    _micPaused = false;
    error = null;
    assistant.speechError = null;
    _ready = false;
    _scanPaused = false;
    _greetingPlaying = false;
    final session = ++_session;
    assistant.sessionVoiceEnabled = true;
    _notify();
    try {
      await assistant.initialize();
    } catch (e) {
      if (_isSession(session)) {
        error = 'Could not start the shopping companion.';
        _ready = true;
        _notify();
      }
      return;
    }
    if (!_isSession(session)) return;
    assistant.resumeForeground();
    assistant.sessionVoiceEnabled = true;
    assistant.speech.duplexEnabled = false;
    assistant.configureLiveVoice(false);
    try {
      await assistant.prepareLiveVoice();
    } catch (_) {
      if (!_isSession(session)) return;
      assistant.speechError =
          'Voice playback failed. Tap Retry speech to try again.';
      error = assistant.speechError;
    }
    if (!_isSession(session)) return;
    _ready = true;
    _greetingPlaying = true;
    _notify();
    // Speak first; the microphone opens after playback finishes. The explicit
    // Interrupt and talk button can stop the greeting and open the microphone.
    try {
      await assistant.speakSession(_greeting);
    } catch (_) {
      if (_isSession(session)) error = 'Could not play the greeting.';
    } finally {
      if (_isSession(session)) _greetingPlaying = false;
    }
    if (!_isSession(session)) return;
    await _announcePending();
    _scheduleListening();
  }

  Future<void> stop() {
    ++_command;
    final pending = _stopping;
    if (pending != null) return pending;
    final task = _stopSession();
    _stopping = task;
    return task.whenComplete(() {
      if (identical(_stopping, task)) _stopping = null;
    });
  }

  Future<void> _stopSession() async {
    ++_session;
    ++_submission;
    _submitting = false;
    draft = '';
    ++_productEpoch;
    active = false;
    _ready = false;
    _scanPaused = true;
    _greetingPlaying = false;
    loading = false;
    _pendingBriefing = null;
    _cancelTimers();
    _recognition++;
    _notify();
    if (assistant.busy &&
        assistant.pendingAction == null &&
        !assistant.committing) {
      await assistant.cancelTurn();
    }
    await assistant.stopListening();
    await assistant.stopAudio();
    assistant.sessionVoiceEnabled = false;
    assistant.configureLiveVoice(false);
    assistant.speech.duplexEnabled = false;
    assistant.tts.setConversationMode(false);
    _notify();
  }

  Future<void> pause() => stop();

  Future<void> scanning() async {
    _scanPaused = true;
    ++_productEpoch;
    _pendingBriefing = null;
    _cancelTimers();
    _recognition++;
    await assistant.stopListening();
    loading = false;
    draft = '';
    error = null;
    reply = null;
    briefing = null;
    _product = null;
    _productKey = null;
    _scannedAt = null;
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
      ++_productEpoch;
      _product = null;
      _productKey = null;
      _scannedAt = null;
      _pendingBriefing = null;
      briefing = null;
      reply = null;
      loading = false;
      error = 'Could not identify that product. Try holding it steady and scanning again.';
      assistant.setCurrentProduct(null);
      if (assistant.busy &&
          assistant.pendingAction == null &&
          !assistant.committing) {
        await assistant.cancelTurn();
      }
      await assistant.stopAudio();
      if (active) {
        _scanPaused = false;
        _scheduleListening();
      }
      _notify();
      return;
    }

    final key = productKeyFor(product);
    final same = key == _productKey;
    if (!same) {
      ++_productEpoch;
      _pendingBriefing = null;
      briefing = null;
      reply = null;
      if (assistant.busy &&
          assistant.pendingAction == null &&
          !assistant.committing) {
        await assistant.cancelTurn();
      }
      await assistant.stopAudio();
    }
    _product = product;
    _productKey = key;
    _scannedAt = scannedAt ?? (same ? _scannedAt : null) ?? _now();
    assistant.setCurrentProduct(_productMap(product));
    if (active) _scanPaused = false;
    if (same && briefing?.key == key && _recentlyAnnounced(key)) {
      _notify();
      return;
    }
    if (_assessed.remove(key) case final assessed?) {
      // The assistant already photographed, assessed and answered about this
      // product in its own turn, so only adopt the result.
      briefing = assessed;
      _pendingBriefing = null;
      loading = false;
      error = null;
      _captureReply(0);
      _notify();
      _scheduleListening();
      return;
    }
    final epoch = _productEpoch;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await briefingLoader(product)
          .timeout(const Duration(seconds: 15));
      if (!_isProduct(epoch, key)) return;
      briefing = result;
      _pendingBriefing = _recentlyAnnounced(key) ? null : result;
    } catch (_) {
      if (_isProduct(epoch, key)) {
        error = 'Product briefing is unavailable right now.';
      }
    } finally {
      if (_isProduct(epoch, key)) {
        loading = false;
        _notify();
        await _announcePending();
        _scheduleListening();
      }
    }
  }

  bool _recentlyAnnounced(String key) =>
      _announcedAt[key] != null &&
      _now().difference(_announcedAt[key]!) < _repeatCooldown;

  bool _isSession(int id) => !_disposed && active && id == _session;
  bool _isProduct(int id, String key) =>
      !_disposed && id == _productEpoch && key == _productKey;

  Future<void> _announcePending() async {
    final pending = _pendingBriefing;
    final product = _product;
    final key = _productKey;
    if (pending == null ||
        product == null ||
        key == null ||
        !active ||
        !_ready ||
        loading ||
        _submitting ||
        _greetingPlaying ||
        assistant.busy ||
        assistant.pendingAction != null ||
        assistant.committing ||
        draft.trim().isNotEmpty ||
        assistant.speaking ||
        assistant.preparingSpeech) {
      return;
    }
    _pendingBriefing = null;
    final session = _session;
    final productEpoch = _productEpoch;
    final start = assistant.messages.length;
    final submission = ++_submission;
    _announcedAt[key] = _now();
    _submitting = true;
    _notify();
    try {
      await assistant.reactToScan(
        'I just scanned this. What do you think of it for me?',
        product: {..._productMap(product), 'assessment': pending.facts},
      );
    } finally {
      if (submission == _submission) _submitting = false;
    }
    if (submission != _submission ||
        !_isSession(session) ||
        !_isProduct(productEpoch, key)) {
      return;
    }
    _captureReply(start);
    final answered =
        reply != null && assistant.messages.indexOf(reply!) >= start;
    if (!answered && assistant.error != null) {
      // The model is unreachable: fall back to the deterministic wording.
      assistant.error = null;
      await _announceFallback(pending, product, session, productEpoch, key);
    }
    if (_isSession(session) && _isProduct(productEpoch, key)) {
      _notify();
      _scheduleListening();
    }
  }

  Future<void> _announceFallback(
    ProductBriefing pending,
    ProductIdentification product,
    int session,
    int productEpoch,
    String key,
  ) async {
    final text = [
      pending.text,
      for (final item in pending.alternatives)
        '${item.name}${item.detail.isEmpty ? '' : ': ${item.detail}'}',
    ].where((part) => part.trim().isNotEmpty).join('\n');
    await assistant.announceCameraBriefing(
      text: text,
      product: _productMap(product),
    );
    if (!_isSession(session) || !_isProduct(productEpoch, key)) return;
    reply = assistant.messages.isEmpty ? null : assistant.messages.last;
    await assistant.speakAnnouncement(
      pending.text,
      isCurrent: () => _isSession(session) && _isProduct(productEpoch, key),
    );
  }

  /// Loads the personal assessment for a product the assistant photographed
  /// mid-turn. The result is cached so the follow-up [updateProduct] adopts
  /// it instead of reloading and announcing it a second time.
  Future<Map<String, Object?>> assess(ProductIdentification product) async {
    final key = productKeyFor(product);
    try {
      final result = await briefingLoader(product)
          .timeout(const Duration(seconds: 15));
      _assessed[key] = result;
      _announcedAt[key] = _now();
      return result.facts;
    } catch (_) {
      return const {'verdict': 'unavailable'};
    }
  }

  void _onAssistantChanged() {
    if (_disposed) return;
    final speechFailure = assistant.error;
    if (active &&
        !assistant.listening &&
        speechFailure != null &&
        !assistant.busy &&
        !_submitting &&
        (speechFailure.contains('Speech recognition') ||
            speechFailure.startsWith('error_'))) {
      error =
          speechFailure == 'error_no_match' ||
              speechFailure == 'error_speech_timeout'
          ? null
          : speechFailure;
      if (error != null) _micPaused = true;
    }
    _notify();
    if (_pendingBriefing != null) unawaited(_announcePending());
    if (active &&
        !assistant.listening &&
        !assistant.speaking &&
        !assistant.preparingSpeech &&
        draft.trim().isEmpty) {
      _scheduleListening();
    }
  }

  void setDraft(String value) {
    draft = value;
    _silenceTimer?.cancel();
    _notify();
    if (draft.trim().isEmpty && _pendingBriefing != null) {
      unawaited(_announcePending());
    }
  }

  Future<void> submit([String? text]) async {
    if (text != null) draft = text;
    _silenceTimer?.cancel();
    final query = draft.trim();
    if (_detailsIntent(query)) {
      draft = '';
      _notify();
      onShowDetails?.call();
      _scheduleListening();
      return;
    }
    if (!active ||
        query.isEmpty ||
        busy ||
        pendingAction != null ||
        committing ||
        _submitting) {
      return;
    }
    final session = _session;
    final productEpoch = _productEpoch;
    final key = _productKey;
    final startIndex = assistant.messages.length;
    final submission = ++_submission;
    _submitting = true;
    draft = '';
    _notify();
    try {
      await assistant.sendCompanion(
        query,
        product: _product == null ? null : _productMap(_product!),
      );
    } finally {
      if (submission == _submission) _submitting = false;
    }
    if (submission != _submission ||
        !_isSession(session) ||
        productEpoch != _productEpoch ||
        key != _productKey) {
      return;
    }
    for (var i = assistant.messages.length - 1; i >= startIndex; i--) {
      if (assistant.messages[i].role == 'assistant') {
        reply = assistant.messages[i];
        break;
      }
    }
    _notify();
    if (_pendingBriefing != null) await _announcePending();
    _scheduleListening();
  }

  Future<void> listen() => resumeListening();

  Future<void> pauseListening() async {
    _micPaused = true;
    _recognition++;
    _listenTimer?.cancel();
    _silenceTimer?.cancel();
    await assistant.stopListening();
    _notify();
  }

  Future<void> resumeListening() async {
    _micPaused = false;
    error = null;
    assistant.error = null;
    _scheduleListening(Duration.zero);
  }

  Future<void> retrySpeech() async {
    assistant.speechError = null;
    error = null;
    if (_micPaused) {
      await resumeListening();
      return;
    }
    if (active) {
      await assistant.replay(reply?.text ?? briefing?.text ?? _greeting);
    }
    _scheduleListening();
    _notify();
  }

  void _scheduleListening([
    Duration delay = const Duration(milliseconds: 250),
  ]) {
    _listenTimer?.cancel();
    if (!_canListen) return;
    _listenTimer = Timer(delay, () => unawaited(_beginListening()));
  }

  bool get _canListen =>
      active &&
      _ready &&
      !_micPaused &&
      !_scanPaused &&
      !_disposed &&
      !_micStarting &&
      !_interrupting &&
      !_greetingPlaying &&
      !_submitting &&
      !(_silenceTimer?.isActive ?? false) &&
      !loading &&
      _pendingBriefing == null &&
      !assistant.listening &&
      assistant.pendingAction == null &&
      !assistant.committing &&
      !assistant.busy &&
      !assistant.speaking &&
      !assistant.preparingSpeech;

  Future<void> _beginListening() async {
    if (!_canListen) return;
    _micStarting = true;
    final session = _session;
    final run = ++_recognition;
    final initialDraft = draft;
    var heardText = false;
    try {
      await assistant.startListening(
        (transcript) {
          if (!_isSession(session) ||
              run != _recognition ||
              transcript.trim().isEmpty) {
            return;
          }
          final value = _joinTranscript(initialDraft, transcript.trim());
          if (value == draft && heardText) return;
          // Ignore delayed callbacks from a recognizer whose turn has ended.
          if (assistant.busy ||
              assistant.speaking ||
              assistant.preparingSpeech) {
            return;
          }
          heardText = true;
          draft = value;
          _armSilenceTimer();
          _notify();
        },
        onFinal: () {
          if (!_isSession(session) || run != _recognition) return;
          if (draft.trim().isNotEmpty && !(_silenceTimer?.isActive ?? false)) {
            _armSilenceTimer();
          }
        },
        onEnded: () {
          if (!_isSession(session) || run != _recognition) return;
          if (draft.trim().isNotEmpty && !(_silenceTimer?.isActive ?? false)) {
            _armSilenceTimer();
          }
          _scheduleListening(const Duration(milliseconds: 100));
        },
        keepPlayback: false,
        allowWhileBusy: false,
      );
    } finally {
      _micStarting = false;
      if (_canListen && !assistant.listening) {
        _scheduleListening(const Duration(milliseconds: 250));
      }
      _notify();
    }
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    if (!active || _micPaused || draft.trim().isEmpty || _disposed) return;
    final session = _session;
    _silenceTimer = Timer(_silenceDelay, () async {
      if (!_isSession(session) || draft.trim().isEmpty || _submitting) return;
      if (assistant.listening) {
        _recognition++;
        await assistant.stopListening();
      }
      if (_isSession(session) && draft.trim().isNotEmpty) await submit();
    });
  }

  String _joinTranscript(String prior, String next) {
    final left = prior.trim();
    if (left.isEmpty || next.toLowerCase().startsWith(left.toLowerCase())) {
      return next;
    }
    final a = left.split(RegExp(r'\s+'));
    final b = next.split(RegExp(r'\s+'));
    for (var n = a.length < b.length ? a.length : b.length; n > 0; n--) {
      if (a.skip(a.length - n).join(' ').toLowerCase() ==
          b.take(n).join(' ').toLowerCase()) {
        return '$left ${b.skip(n).join(' ')}'.trim();
      }
    }
    return '$left $next';
  }

  Future<void> stopListening() => pauseListening();

  Future<void> interruptAndListen() async {
    if (_disposed || !active || _interrupting) return;
    final session = _session;
    _interrupting = true;
    _recognition++;
    ++_submission;
    _submitting = false;
    _micPaused = false;
    _silenceTimer?.cancel();
    _listenTimer?.cancel();
    try {
      if (assistant.pendingAction == null &&
          !assistant.committing &&
          assistant.busy) {
        await assistant.cancelTurn();
      }
      await assistant.stopListening();
      await assistant.stopAudio();
      if (!_isSession(session)) return;
      _greetingPlaying = false;
      // An explicit interruption takes priority over queued automatic briefings.
      _pendingBriefing = null;
      assistant.sessionVoiceEnabled = true;
    } finally {
      _interrupting = false;
    }
    if (!_isSession(session)) return;
    _notify();
    _scheduleListening();
  }

  Future<void> stopSpeech() => assistant.stopAudio();

  Future<void> confirmAction() async {
    final start = assistant.messages.length;
    await assistant.confirmAction();
    _captureReply(start);
    _scheduleListening();
    _notify();
  }

  Future<void> cancelAction() async {
    await assistant.cancelAction();
    _scheduleListening();
    _notify();
  }

  void _captureReply(int start) {
    for (var i = assistant.messages.length - 1; i >= start; i--) {
      if (assistant.messages[i].role == 'assistant') {
        reply = assistant.messages[i];
        return;
      }
    }
  }

  Future<void> requestAlternatives() {
    if (_product == null) {
      error = 'Scan a product first to ask for alternatives.';
      _notify();
      return Future.value();
    }
    draft = 'What are the suitable alternatives for this product?';
    return submit();
  }

  Future<void> retryBriefing() async {
    final product = _product;
    if (!active || product == null || loading) return;
    final key = _productKey;
    if (key != null) _announcedAt.remove(key);
    await updateProduct(product, scannedAt: _scannedAt);
  }

  Future<void> replay() async {
    final text = reply?.text ?? briefing?.text;
    if (active && text != null && text.isNotEmpty) await assistant.replay(text);
  }

  void _cancelTimers() {
    _listenTimer?.cancel();
    _silenceTimer?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_command;
    ++_submission;
    ++_session;
    ++_productEpoch;
    _cancelTimers();
    assistant.speech.duplexEnabled = false;
    assistant.configureLiveVoice(false);
    assistant.sessionVoiceEnabled = false;
    assistant.removeListener(_onAssistantChanged);
    unawaited(assistant.stopListening());
    unawaited(assistant.stopAudio());
    super.dispose();
  }

  bool _detailsIntent(String text) {
    final value = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return RegExp(
          r'\b(show|open|see|view|display)\b.*\b(details?|more information|full results|scan results)\b',
        ).hasMatch(value) ||
        RegExp(r'\b(show me more|tell me more|open the details)\b')
            .hasMatch(value);
  }
}
