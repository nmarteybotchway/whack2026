import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'health_data_store.dart';

/// Settings card asking whether the user wants their health data collected
/// from Health Connect and stored in Firestore.
///
/// On opt-in, the latest heart rate, steps, sleep, weight and blood pressure
/// are read from Health Connect and written to `users/{uid}/healthData`.
/// Opting out stops collection; stored data remains until deleted.
class HealthDataCard extends StatefulWidget {
  const HealthDataCard({super.key, required this.user});

  final User user;

  @override
  State<HealthDataCard> createState() => _HealthDataCardState();
}

class _HealthDataCardState extends State<HealthDataCard> {
  final _store = HealthDataStore();

  bool? _enabled;
  Map<String, Object?>? _snapshot;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('healthData')
          .doc('latest')
          .get();
      if (!mounted) return;
      setState(() {
        _snapshot = doc.data();
        _enabled = doc.data()?['optedIn'] as bool? ?? false;
      });
    } on FirebaseException {
      if (!mounted) return;
      setState(() => _enabled = false);
    }
  }

  Future<void> _setOptIn(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Map<String, Object?>? snapshot;
      if (value) {
        snapshot = await _store.collectAndStore(widget.user.uid);
        snapshot['optedIn'] = true;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('healthData')
          .doc('latest')
          .set({'optedIn': value}, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _enabled = value;
        if (snapshot != null) _snapshot = snapshot;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? (_snapshot == null || _snapshot!.length <= 1
                      ? 'Connected, but no health data was found to store yet.'
                      : 'Health data stored in Firestore.')
                : 'Health data collection turned off.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not collect health data. Check the connection and try again.';
      });
    }
  }

  Future<void> _deleteStored() async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('healthData')
          .doc('latest')
          .delete();
      if (!mounted) return;
      setState(() {
        _snapshot = null;
        _enabled = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Stored health data deleted.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  String _summary() {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.length <= 1) return 'No data stored yet.';
    final parts = <String>[];
    final hr = snapshot['heartRateBpm'];
    if (hr != null) parts.add('$hr bpm');
    final steps = snapshot['steps'];
    if (steps != null) parts.add('$steps steps');
    final sleep = snapshot['sleepMinutes'];
    if (sleep != null) parts.add('${(sleep as num) ~/ 60}h ${sleep % 60}m sleep');
    final weight = snapshot['weightKg'];
    if (weight != null) parts.add('$weight kg');
    final sys = snapshot['systolicMmHg'];
    final dia = snapshot['diastolicMmHg'];
    if (sys != null && dia != null) parts.add('$sys/$dia mmHg');
    return parts.isEmpty ? 'No data stored yet.' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _enabled ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Health data',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: _busy ? null : (v) => _setOptIn(v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              enabled
                  ? 'Collecting your readings from Health Connect (Samsung Health) and storing them in Firestore.'
                  : 'Allow the app to read your health data (heart rate, steps, sleep, weight, blood pressure) and store it in Firestore.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(_summary(), style: theme.textTheme.bodySmall),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (enabled && _snapshot != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: .centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _deleteStored,
                  child: const Text('Delete stored data'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
