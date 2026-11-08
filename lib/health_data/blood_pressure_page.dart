import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'health_tracking_controller.dart';
import 'heart_rate_page.dart';

class BloodPressurePage extends StatefulWidget {
  const BloodPressurePage({super.key, required this.tracking});
  final HealthTrackingController tracking;

  @override
  State<BloodPressurePage> createState() => _BloodPressurePageState();
}

class _BloodPressurePageState extends State<BloodPressurePage> {
  late final _readings = widget.tracking.records
      .orderBy('measuredAt', descending: true)
      .limit(20)
      .snapshots(includeMetadataChanges: true);

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete uploaded readings?'),
        content: const Text(
          'This stops tracking and deletes blood pressure records from your cloud account, not Health Connect. Connecting again will reimport available readings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await widget.tracking.deleteUploaded();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.tracking,
    builder: (context, _) {
      final tracking = widget.tracking;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Health tracking',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect Health Connect to read blood pressure and save it to your account. Readings include measurement times and source details.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Checks the last 29 days, then refreshes every minute while the app is open. Readings can be delayed; Samsung watch blood pressure may not be exported.',
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.favorite,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Heart rate'),
              subtitle: const Text('View readings from Health Connect'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HeartRatePage()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(tracking.status),
          if (tracking.busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: tracking.busy || tracking.enabled || !tracking.ready
                    ? null
                    : tracking.connect,
                child: const Text('Connect and upload'),
              ),
              OutlinedButton(
                onPressed: tracking.busy || !tracking.enabled
                    ? null
                    : tracking.refresh,
                child: const Text('Refresh'),
              ),
              TextButton(
                onPressed: tracking.busy || !tracking.enabled
                    ? null
                    : tracking.stop,
                child: const Text('Stop tracking'),
              ),
              TextButton(
                onPressed: tracking.busy ? null : _delete,
                child: const Text('Delete uploaded readings'),
              ),
            ],
          ),
          const Text(
            'Stopping keeps existing readings. Revoke access in Health Connect settings to remove permission.',
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _readings,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Cannot load readings. Check your connection and account permissions.',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) return const Text('No uploaded readings yet.');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    snapshot.data!.metadata.isFromCache
                        ? 'Saved readings (cached)'
                        : 'Latest readings',
                  ),
                  for (final doc in docs)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${doc.data()['systolic']} / ${doc.data()['diastolic']} mmHg',
                        ),
                        subtitle: Text(
                          'Measured ${(doc.data()['measuredAt'] as Timestamp).toDate().toLocal()}\nSource: ${doc.data()['sourceApp']}',
                        ),
                        isThreeLine: true,
                        trailing: doc.metadata.hasPendingWrites
                            ? const Icon(
                                Icons.cloud_upload_outlined,
                                semanticLabel: 'Upload pending',
                              )
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}
