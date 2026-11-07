import 'package:flutter/material.dart';

import 'blood_pressure_page.dart';
import 'health_tracking_controller.dart';

Future<void> showHealthTrackingIntro(
  BuildContext context,
  HealthTrackingController tracking,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => PopScope(
    canPop: false,
    child: AnimatedBuilder(
      animation: tracking,
      builder: (context, _) => AlertDialog(
        icon: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Connect health data?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Optionally connect Android Health Connect to track blood pressure. With your permission, readings from the last 29 days and their source details are uploaded to your account.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Tracking refreshes while the app is open. Data may be delayed or unavailable from your watch. You can connect later, stop tracking or delete uploads in Preferences.',
              ),
              if (tracking.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (tracking.status !=
                  'Not connected. No health data is being uploaded.') ...[
                const SizedBox(height: 12),
                Text(tracking.status),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: tracking.busy
                ? null
                : () async {
                    await tracking.markIntroSeen();
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: tracking.busy
                ? null
                : () async {
                    await tracking.markIntroSeen();
                    await tracking.connect();
                    if (context.mounted && tracking.enabled) {
                      Navigator.pop(context);
                    }
                  },
            child: const Text('Connect and upload'),
          ),
        ],
      ),
    ),
  ),
);

class HealthTrackingCard extends StatelessWidget {
  const HealthTrackingCard({super.key, required this.tracking});
  final HealthTrackingController tracking;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: tracking,
    builder: (context, _) => Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Health tracking'),
            subtitle: Text(
              !tracking.ready
                  ? 'Checking connection…'
                  : tracking.enabled
                  ? 'Blood pressure · Connected'
                  : tracking.status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (context) => FractionallySizedBox(
                heightFactor: 0.9,
                child: BloodPressurePage(tracking: tracking),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
