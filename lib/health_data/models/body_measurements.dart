/// Unit conversions and BMI calculation, without rounding stored values.
class BodyMeasurements {
  const BodyMeasurements({required this.heightCm, required this.weightKg});

  static const centimetresPerInch = 2.54;
  static const kilogramsPerPound = 0.45359237;

  final double heightCm;
  final double weightKg;

  static double heightFromImperial(double feet, double inches) =>
      (feet * 12 + inches) * centimetresPerInch;

  static double weightFromPounds(double pounds) => pounds * kilogramsPerPound;

  double get totalInches => heightCm / centimetresPerInch;
  double get pounds => weightKg / kilogramsPerPound;
  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  bool get isValid =>
      heightCm.isFinite &&
      heightCm > 0 &&
      heightCm <= 300 &&
      weightKg.isFinite &&
      weightKg > 0 &&
      weightKg <= 1000;
}
