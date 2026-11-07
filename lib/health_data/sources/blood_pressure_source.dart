import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Read-only Android bridge. A record contains both blood pressure components.
class BloodPressureSource {
  static const _channel = MethodChannel('sentinel/health_connect');

  Future<String> availability() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'unavailable';
    }
    return await _channel.invokeMethod<String>('availability') ?? 'unavailable';
  }

  Future<Map<String, dynamic>> trackingSettings(String userId) async =>
      Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>('trackingSettings', {
              'userId': userId,
            }) ??
            {},
      );

  Future<void> saveTrackingSettings(
    String userId, {
    bool? introSeen,
    bool? enabled,
  }) => _channel.invokeMethod<void>('saveTrackingSettings', {
    'userId': userId,
    'introSeen': ?introSeen,
    'enabled': ?enabled,
  });

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<List<Map<String, dynamic>>> read(DateTime start, DateTime end) async {
    final records = await _channel.invokeListMethod<dynamic>(
      'readBloodPressure',
      {
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      },
    );
    return (records ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }
}
