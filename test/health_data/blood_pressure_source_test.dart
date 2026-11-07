import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/health_data/sources/blood_pressure_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sentinel/health_connect');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('preserves paired values and the requested time window', () async {
    final start = DateTime.utc(2026, 11, 1);
    final end = DateTime.utc(2026, 11, 2);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readBloodPressure');
      expect(call.arguments, {
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      });
      return [
        {'id': 'paired-record', 'systolic': 120.0, 'diastolic': 80.0},
      ];
    });
    final records = await BloodPressureSource().read(start, end);
    expect(records.single['id'], 'paired-record');
    expect(records.single['systolic'], 120);
    expect(records.single['diastolic'], 80);
  });

  test('propagates read failures instead of treating them as empty data', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'permission');
    });
    await expectLater(
      BloodPressureSource().read(DateTime.utc(2026), DateTime.utc(2027)),
      throwsA(isA<PlatformException>()),
    );
  });
}
