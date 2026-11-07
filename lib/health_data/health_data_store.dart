import 'package:cloud_firestore/cloud_firestore.dart';

import 'sources/blood_pressure_source.dart';

/// One snapshot of the user's health readings, stored in Firestore at
/// `users/{uid}/healthData`. Each field is the most recent reading of that
/// metric from Health Connect; null when the metric has no data.
///
/// Example document:
/// ```
/// heartRateBpm: 75
/// steps: 8432
/// sleepMinutes: 421
/// weightKg: 70.5
/// systolicMmHg: 118
/// diastolicMmHg: 76
/// updatedAt: <server timestamp>
/// ```
class HealthDataStore {
  HealthDataStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Reads the latest value of every metric from Health Connect and writes
  /// them to Firestore. Returns the snapshot that was stored.
  Future<Map<String, Object?>> collectAndStore(String userId) async {
    final source = BloodPressureSource();
    final now = DateTime.now();
    // Health Connect holds up to 30 days; a month window finds the latest
    // reading of each metric even if it was recorded days ago.
    final start = now.subtract(const Duration(days: 30));

    final snapshot = <String, Object?>{};

    final heartRate = await source.readHeartRate(start, now);
    final bpm = _latestHeartRate(heartRate);
    if (bpm != null) snapshot['heartRateBpm'] = bpm;

    final steps = await source.readSteps(start, now);
    final stepCount = _latestSteps(steps);
    if (stepCount != null) snapshot['steps'] = stepCount;

    final sleep = await source.readSleep(start, now);
    final sleepMinutes = _latestSleepMinutes(sleep);
    if (sleepMinutes != null) snapshot['sleepMinutes'] = sleepMinutes;

    final weight = await source.readWeight(start, now);
    final kg = _latestWeight(weight);
    if (kg != null) snapshot['weightKg'] = kg;

    final bloodPressure = await source.read(start, now);
    final bp = _latestBloodPressure(bloodPressure);
    if (bp != null) {
      snapshot['systolicMmHg'] = bp[0];
      snapshot['diastolicMmHg'] = bp[1];
    }

    if (snapshot.isEmpty) return snapshot;

    snapshot['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('healthData')
        .doc('latest')
        .set(snapshot, SetOptions(merge: true));
    return snapshot;
  }

  /// The stored snapshot for [userId], or null when nothing saved yet.
  Future<Map<String, Object?>?> load(String userId) async {
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('healthData')
        .doc('latest')
        .get();
    return doc.data();
  }

  int? _latestHeartRate(List<Map<String, dynamic>> records) {
    if (records.isEmpty) return null;
    records.sort(
      (a, b) => (b['measuredAt'] as int).compareTo(a['measuredAt'] as int),
    );
    final samples = (records.first['bpmSamples'] as List<Object?>? ?? const [])
        .whereType<num>()
        .toList();
    if (samples.isEmpty) return null;
    return (samples.reduce((a, b) => a + b) / samples.length).round();
  }

  int? _latestSteps(List<Map<String, dynamic>> records) {
    if (records.isEmpty) return null;
    // Sum today's step records for a daily total.
    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day)
        .millisecondsSinceEpoch;
    var total = 0;
    var any = false;
    for (final record in records) {
      if ((record['measuredAt'] as int) >= dayStart) {
        total += (record['count'] as num?)?.toInt() ?? 0;
        any = true;
      }
    }
    return any ? total : null;
  }

  int? _latestSleepMinutes(List<Map<String, dynamic>> records) {
    if (records.isEmpty) return null;
    records.sort(
      (a, b) => (b['measuredAt'] as int).compareTo(a['measuredAt'] as int),
    );
    return (records.first['durationMinutes'] as num?)?.toInt();
  }

  double? _latestWeight(List<Map<String, dynamic>> records) {
    if (records.isEmpty) return null;
    records.sort(
      (a, b) => (b['measuredAt'] as int).compareTo(a['measuredAt'] as int),
    );
    return (records.first['weightKg'] as num?)?.toDouble();
  }

  List<int>? _latestBloodPressure(List<Map<String, dynamic>> records) {
    if (records.isEmpty) return null;
    records.sort(
      (a, b) => (b['measuredAt'] as int).compareTo(a['measuredAt'] as int),
    );
    final systolic = (records.first['systolic'] as num?)?.toInt();
    final diastolic = (records.first['diastolic'] as num?)?.toInt();
    if (systolic == null || diastolic == null) return null;
    return [systolic, diastolic];
  }
}
