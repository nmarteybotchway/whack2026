import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/health_data/health_tracking_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sentinel/health_connect');
  final calls = <MethodCall>[];
  late HealthTrackingController tracking;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    tracking = HealthTrackingController('test-user');
  });
  tearDown(() {
    tracking.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mock({
    bool introSeen = false,
    bool enabled = false,
    bool granted = false,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'trackingSettings' => {'introSeen': introSeen, 'enabled': enabled},
            'availability' => 'available',
            'hasPermission' || 'requestPermission' => granted,
            'saveTrackingSettings' => null,
            _ => throw StateError(
              'Unexpected platform request: ${call.method}',
            ),
          };
        });
  }

  test(
    'first run offers an introduction without requesting access or collecting',
    () async {
      mock();
      await tracking.initialize();
      expect(tracking.introSeen, isFalse);
      expect(tracking.enabled, isFalse);
      expect(calls.map((c) => c.method), ['trackingSettings', 'availability']);
      await tracking.markIntroSeen();
      expect(calls.last.arguments, {'userId': 'test-user', 'introSeen': true});
    },
  );

  test('dismissed introduction stays dismissed', () async {
    mock(introSeen: true);
    await tracking.initialize();
    expect(tracking.introSeen, isTrue);
    expect(tracking.enabled, isFalse);
  });

  test('denied permission never enables tracking or reads records', () async {
    mock();
    await tracking.initialize();
    await tracking.connect();
    expect(tracking.enabled, isFalse);
    expect(tracking.status, contains('not granted'));
    expect(calls.any((c) => c.method == 'readBloodPressure'), isFalse);
    expect(calls.any((c) => c.method == 'saveTrackingSettings'), isFalse);
  });

  test(
    'previous consent does not restart tracking after permission revocation',
    () async {
      mock(introSeen: true, enabled: true, granted: false);
      await tracking.initialize();
      expect(tracking.enabled, isFalse);
      expect(calls.any((c) => c.method == 'requestPermission'), isFalse);
      expect(calls.any((c) => c.method == 'readBloodPressure'), isFalse);
      await tracking.stop();
      expect(calls.last.arguments, {'userId': 'test-user', 'enabled': false});
    },
  );
}
