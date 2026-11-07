import 'package:flutter/material.dart';

import 'sources/blood_pressure_source.dart';

/// Shows recent heart-rate readings pulled from Health Connect (fed by
/// Samsung Health / the watch) over the last 7 days.
class HeartRatePage extends StatefulWidget {
  const HeartRatePage({super.key});

  @override
  State<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends State<HeartRatePage> {
  final _source = BloodPressureSource();

  List<Map<String, dynamic>> _readings = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final available = await _source.availability();
      if (available != 'available') {
        throw Exception('Health Connect is not available ($available).');
      }
      // Always run the request: previously-granted types (e.g. blood
      // pressure) make hasPermission() true even when heart rate is still
      // missing, and re-requesting only prompts for the missing ones.
      await _source.requestPermission();
      if (!await _source.hasPermission()) {
        throw Exception('Health data permission was not granted.');
      }
      final end = DateTime.now();
      final start = end.subtract(const Duration(days: 7));
      final readings = await _source.readHeartRate(start, end);
      readings.sort(
        (a, b) => (b['measuredAt'] as int).compareTo(a['measuredAt'] as int),
      );
      if (!mounted) return;
      setState(() {
        _readings = readings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Latest average bpm across the samples of the most recent session.
  int? get _latestBpm {
    if (_readings.isEmpty) return null;
    final samples = (_readings.first['bpmSamples'] as List<Object?>? ?? const [])
        .whereType<num>()
        .toList();
    if (samples.isEmpty) return null;
    return (samples.reduce((a, b) => a + b) / samples.length).round();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Heart rate')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : _readings.isEmpty
          ? const Center(child: Text('No heart-rate readings in the last 7 days.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_latestBpm != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite,
                            color: theme.colorScheme.error,
                            size: 40,
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_latestBpm bpm',
                                style: theme.textTheme.headlineMedium,
                              ),
                              const Text('Latest reading'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final reading in _readings.take(30))
                  ListTile(
                    leading: const Icon(Icons.monitor_heart),
                    title: Text(_bpmLabel(reading)),
                    subtitle: Text(_timeLabel(reading)),
                    trailing: Text(
                      (reading['sourceApp'] as String? ?? '').split('.').last,
                    ),
                  ),
              ],
            ),
    );
  }

  String _bpmLabel(Map<String, dynamic> reading) {
    final samples = (reading['bpmSamples'] as List<Object?>? ?? const [])
        .whereType<num>()
        .toList();
    if (samples.isEmpty) return '—';
    final min = samples.reduce((a, b) => a < b ? a : b);
    final max = samples.reduce((a, b) => a > b ? a : b);
    return '$min–$max bpm (${samples.length} samples)';
  }

  String _timeLabel(Map<String, dynamic> reading) {
    final at = DateTime.fromMillisecondsSinceEpoch(reading['measuredAt'] as int);
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-'
        '${at.day.toString().padLeft(2, '0')} '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }
}
