import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../sources/blood_pressure_source.dart';

class BloodPressureSync {
  BloodPressureSync(this.userId);
  final String userId;
  final source = BloodPressureSource();
  bool _stopped = false;
  bool _busy = false;

  CollectionReference<Map<String, dynamic>> get records => FirebaseFirestore
      .instance.collection('users').doc(userId).collection('bloodPressure');

  void stop() => _stopped = true;

  void _checkUser() {
    if (_stopped || FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Sync stopped or signed-in account changed.');
    }
  }

  /// Reconcile a bounded window, including source corrections and deletions.
  /// Older uploaded records remain until explicitly deleted by the user.
  Future<int> refresh() async {
    if (_busy) return 0;
    _busy = true;
    try {
      _checkUser();
      final end = DateTime.now().toUtc();
      final start = end.subtract(const Duration(days: 29));
      final incoming = await source.read(start, end);
      _checkUser();
      final existing = await records
          .where('measuredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('measuredAt', isLessThan: Timestamp.fromDate(end))
          .get(const GetOptions(source: Source.server));
      final old = {for (final doc in existing.docs) doc.id: doc.data()};
      final writes = <String, Map<String, dynamic>>{};
      for (final record in incoming) {
        final id = record['id'] as String;
        final data = <String, dynamic>{
          ...record,
          'measuredAt': Timestamp.fromMillisecondsSinceEpoch(record['measuredAt'] as int),
          'sourceModifiedAt': Timestamp.fromMillisecondsSinceEpoch(record['sourceModifiedAt'] as int),
          'unit': 'mmHg',
          'provider': 'health_connect',
        };
        if (!mapEquals(old.remove(id), data)) writes[id] = data;
      }
      var batch = FirebaseFirestore.instance.batch();
      var count = 0;
      Future<void> flush() async {
        if (count == 0) return;
        _checkUser();
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        count = 0;
      }
      for (final entry in writes.entries) {
        batch.set(records.doc(entry.key), entry.value);
        if (++count == 400) await flush();
      }
      for (final id in old.keys) {
        batch.delete(records.doc(id));
        if (++count == 400) await flush();
      }
      await flush();
      return incoming.length;
    } finally {
      _busy = false;
    }
  }

  Future<void> deleteUploaded() async {
    if (_busy) throw StateError('Wait for the current sync to finish.');
    _busy = true;
    try {
      while (true) {
        _checkUser();
        final page = await records.limit(400).get(const GetOptions(source: Source.server));
        if (page.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        _checkUser();
        await batch.commit();
      }
    } finally {
      _busy = false;
    }
  }
}
