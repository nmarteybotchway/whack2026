import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'body_measurements_page.dart';
import 'models/body_measurements.dart';

/// A preferences row matching the beliefs and dietary editors.
class BodyMeasurementsCard extends StatefulWidget {
  const BodyMeasurementsCard({super.key, required this.userId});
  final String userId;

  @override
  State<BodyMeasurementsCard> createState() => _BodyMeasurementsCardState();
}

class _BodyMeasurementsCardState extends State<BodyMeasurementsCard> {
  late final _stream = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.userId)
      .collection('healthProfile')
      .doc('measurements')
      .snapshots();

  String _number(num value) =>
      value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

  String _summary(Map<String, dynamic>? data) {
    final height = data?['heightCm'];
    final weight = data?['weightKg'];
    if (height is! num || weight is! num) return 'Not set';
    final measurements = BodyMeasurements(
      heightCm: height.toDouble(),
      weightKg: weight.toDouble(),
    );
    if (!measurements.isValid) return 'Update your measurements';
    var heightText = '${_number(height)} cm';
    if (data?['heightUnit'] == 'ft_in') {
      final total = (measurements.totalInches * 10).round();
      heightText = '${total ~/ 120} ft ${_number((total % 120) / 10)} in';
    }
    final weightText = data?['weightUnit'] == 'lb'
        ? '${_number(measurements.pounds)} lb'
        : '${_number(weight)} kg';
    return '$heightText · $weightText · BMI ${measurements.bmi.toStringAsFixed(1)}';
  }

  Future<void> _edit() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: BodyMeasurementsPage(userId: widget.userId, closeOnSave: true),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) => Card(
          child: ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Height, weight & BMI'),
            subtitle: Text(
              snapshot.hasError
                  ? 'Could not load measurements. Tap to retry.'
                  : !snapshot.hasData
                  ? 'Loading…'
                  : _summary(snapshot.data!.data()),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _edit,
          ),
        ),
      );
}
