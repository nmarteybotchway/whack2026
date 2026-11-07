import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'sources/blood_pressure_source.dart';
import 'sync/blood_pressure_sync.dart';

/// Owns opt-in collection for the signed-in session, independently of sheets.
class HealthTrackingController extends ChangeNotifier
    with WidgetsBindingObserver {
  HealthTrackingController(this.userId) {
    WidgetsBinding.instance.addObserver(this);
  }
  final String userId;
  final source = BloodPressureSource();
  bool introSeen = true;
  bool enabled = false;
  bool busy = false;
  bool ready = false;
  String availability = 'unavailable';
  String status = 'Not connected. No health data is being uploaded.';
  bool _active = true;
  bool _disposed = false;
  Timer? _timer;
  BloodPressureSync? _sync;

  CollectionReference<Map<String, dynamic>> get records => FirebaseFirestore
      .instance
      .collection('users')
      .doc(userId)
      .collection('bloodPressure');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      ready = true;
      status = 'Health Connect tracking is available on Android.';
      _notify();
      return;
    }
    try {
      final saved = await source.trackingSettings(userId);
      if (_disposed) return;
      introSeen = saved['introSeen'] == true;
      availability = await source.availability();
      if (_disposed) return;
      if (saved['enabled'] == true &&
          availability == 'available' &&
          await source.hasPermission()) {
        if (_disposed) return;
        _start();
      }
    } catch (_) {
      status = 'Could not check Health Connect. You can retry in Preferences.';
    } finally {
      ready = true;
      _notify();
    }
    if (enabled) await refresh();
  }

  Future<void> markIntroSeen() async {
    introSeen = true;
    try {
      await source.saveTrackingSettings(userId, introSeen: true);
    } catch (_) {
      status =
          'Could not remember this choice. You may see the introduction again.';
    }
    _notify();
  }

  void _start() {
    _sync?.stop();
    _sync = BloodPressureSync(userId);
    enabled = true;
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> connect() async {
    if (busy || !ready || _disposed) return;
    busy = true;
    _notify();
    try {
      availability = await source.availability();
      if (_disposed) return;
      if (availability != 'available') {
        status = availability == 'updateRequired'
            ? 'Install or update Health Connect on this phone, then try again.'
            : 'Health Connect needs a compatible Android phone.';
        return;
      }
      final granted = await source.requestPermission();
      if (_disposed) return;
      if (!granted) {
        status = 'Blood pressure permission was not granted. Check Health Connect app permissions to allow access.';
        return;
      }
      await source.saveTrackingSettings(userId, enabled: true, introSeen: true);
      if (_disposed) return;
      introSeen = true;
      _start();
      status = 'Connected. Checking for blood pressure readings…';
    } catch (_) {
      status = 'Could not connect. Check Health Connect and try again.';
    } finally {
      busy = false;
      _notify();
    }
    if (enabled) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!enabled || busy || !_active || _disposed) return;
    busy = true;
    final sync = _sync!;
    _notify();
    try {
      if (!await source.hasPermission()) {
        sync.stop();
        _timer?.cancel();
        enabled = false;
        status = 'Read permission was revoked. Connect again to allow access.';
      } else {
        final count = await sync.refresh();
        if (!_disposed && identical(sync, _sync) && enabled) {
          status = count == 0
              ? 'No blood pressure records in the last 29 days. Your source app may not export them.'
              : 'Last checked ${DateTime.now().toLocal().toString().substring(0, 16)} · $count readings.';
        }
      }
    } catch (_) {
      if (!_disposed && enabled) status = 'Sync failed. Check your connection and Health Connect permission, then retry.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    enabled = false;
    _timer?.cancel();
    _sync?.stop();
    status = 'Tracking stopped. Uploaded readings remain saved.';
    _notify();
    try {
      await source.saveTrackingSettings(userId, enabled: false);
    } catch (_) {
      status = 'Stopped for this session, but could not save the setting. Retry before restarting the app.';
    }
    _notify();
  }

  Future<void> deleteUploaded() async {
    if (busy || _disposed) return;
    await stop();
    if (_disposed) return;
    busy = true;
    final deletion = BloodPressureSync(userId);
    _sync = deletion;
    _notify();
    try {
      await deletion.deleteUploaded();
      status = 'Uploaded blood pressure readings deleted.';
    } catch (_) {
      status =
          'Could not delete all readings. Check your connection and retry.';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _sync?.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
