import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/health_data/models/body_measurements.dart';

void main() {
  test('calculates BMI using height in metres', () {
    const measurements = BodyMeasurements(heightCm: 180, weightKg: 81);
    expect(measurements.bmi, closeTo(25, 0.0000001));
  });

  test('imperial inputs produce the same measurements and BMI', () {
    final measurements = BodyMeasurements(
      heightCm: BodyMeasurements.heightFromImperial(5, 10),
      weightKg: BodyMeasurements.weightFromPounds(154),
    );
    expect(measurements.heightCm, closeTo(177.8, 0.0000001));
    expect(measurements.weightKg, closeTo(69.85322498, 0.0000001));
    expect(measurements.bmi, closeTo(22.096472502945, 0.000001));
    expect(measurements.totalInches, closeTo(70, 0.0000001));
    expect(measurements.pounds, closeTo(154, 0.0000001));
  });

  test('rejects invalid measurements', () {
    for (final height in [0.0, -1.0, double.nan, double.infinity, 301.0]) {
      expect(BodyMeasurements(heightCm: height, weightKg: 70).isValid, isFalse);
    }
    for (final weight in [0.0, -1.0, double.nan, double.infinity, 1001.0]) {
      expect(
        BodyMeasurements(heightCm: 180, weightKg: weight).isValid,
        isFalse,
      );
    }
  });
}
