import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'sync/blood_pressure_sync.dart';

class BloodPressurePage extends StatefulWidget {
  const BloodPressurePage({super.key, required this.userId});
  final String userId;

  @override
  State<BloodPressurePage> createState() => _BloodPressurePageState();
}

class _BloodPressurePageState extends State<BloodPressurePage>
    with WidgetsBindingObserver {
  late final BloodPressureSync _sync;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _readings;
  Timer? _timer;
  bool _enabled = false;
  bool _busy = false;
  bool _active = true;
  String _status = 'Not connected. No health data is being uploaded.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync = BloodPressureSync(widget.userId);
    _readings = _sync.records.orderBy('measuredAt', descending: true).limit(20).snapshots();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && _enabled) unawaited(_refresh());
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final available = await _sync.source.availability();
      if (!mounted) return;
      if (available != 'available') {
        setState(() => _status = available == 'updateRequired'
            ? 'Install or update Health Connect, then try again.'
            : 'Collection needs a compatible Android phone with Health Connect.');
        return;
      }
      final granted = await _sync.source.requestPermission();
      if (!mounted) return;
      if (!granted) {
        setState(() => _status = 'Blood pressure permission was not granted. Check Health Connect app permissions.');
        return;
      }
      _enabled = true;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (_active && _enabled) unawaited(_refresh());
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not connect. Check Health Connect and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _enabled) await _refresh();
  }

  Future<void> _refresh() async {
    if (_busy || !_enabled || !_active) return;
    setState(() => _busy = true);
    try {
      final count = await _sync.refresh();
      if (!mounted) return;
      setState(() => _status = count == 0
          ? 'No blood pressure records in the last 29 days. Check whether your source app exports them to Health Connect.'
          : 'Checked $count readings at ${TimeOfDay.now().format(context)}.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Sync failed. Check your connection, Health Connect permission, and Firebase setup. Tap Refresh to retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _enabled = false;
      _status = 'Sync stopped. Previously uploaded readings remain saved.';
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete uploaded readings?'),
      content: const Text('This deletes your blood pressure records from Firebase, not Health Connect. Connecting again will reimport available readings.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    _stop();
    setState(() => _busy = true);
    try {
      await _sync.deleteUploaded();
      if (mounted) setState(() => _status = 'Uploaded blood pressure readings deleted.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not delete all readings. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sync.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Blood pressure', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('Connect and upload reads the last 29 days of blood pressure from Health Connect and stores it in your Firebase account. Includes measurement times and source metadata. Refreshes every minute while this tab is open and the app is active.'),
      const SizedBox(height: 8),
      const Text('Readings may be delayed. This does not measure blood pressure or force your watch to sync. Samsung watch blood pressure may not be exported to Health Connect.'),
      const SizedBox(height: 12),
      Text(_status, semanticsLabel: _status),
      if (_busy) const LinearProgressIndicator(),
      Wrap(spacing: 8, children: [
        FilledButton(onPressed: _busy || _enabled ? null : _connect, child: const Text('Connect and upload')),
        OutlinedButton(onPressed: _busy || !_enabled ? null : _refresh, child: const Text('Refresh')),
        TextButton(onPressed: !_enabled ? null : _stop, child: const Text('Stop sync')),
        TextButton(onPressed: _busy ? null : _delete, child: const Text('Delete uploaded readings')),
      ]),
      const Text('Revoke read access in Health Connect settings. Stopping sync does not delete uploaded data.'),
      const SizedBox(height: 16),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _readings,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('Cannot load cloud readings. Check Firebase Authentication, Firestore, and security rules.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Text('No uploaded readings yet.');
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(snapshot.data!.metadata.isFromCache ? 'Saved readings (cached)' : 'Latest uploaded readings'),
            for (final doc in docs)
              Builder(builder: (context) {
                final data = doc.data();
                final date = (data['measuredAt'] as Timestamp).toDate().toLocal();
                return Card(child: ListTile(
                  title: Text('${data['systolic']} / ${data['diastolic']} mmHg'),
                  subtitle: Text('Measured $date\nSource: ${data['sourceApp']}'),
                  isThreeLine: true,
                  trailing: doc.metadata.hasPendingWrites ? const Icon(Icons.cloud_upload_outlined, semanticLabel: 'Upload pending') : null,
                ));
              }),
          ]);
        },
      ),
    ],
  );
}
