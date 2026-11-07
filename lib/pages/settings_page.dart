import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../food/health_condition.dart';
import '../health_data/body_measurements_card.dart';
import '../health_data/health_data_card.dart';
import '../health_data/health_tracking_controller.dart';

/// Common religious beliefs offered as quick-pick options.
const _religionOptions = [
  'Christianity',
  'Islam',
  'Judaism',
  'Hinduism',
  'Buddhism',
  'Sikhism',
  'Atheist',
  'Agnostic',
];

/// Common dietary requirements offered as quick-pick options.
const _dietaryOptions = [
  'Gluten free',
  'Vegetarian',
  'Vegan',
  'Pescatarian',
  'Halal',
  'Kosher',
  'Dairy free',
  'Nut allergy',
];

/// User preferences stored in Firestore at `users/{uid}`.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.user, required this.tracking});

  final User user;
  final HealthTrackingController tracking;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<String> _religions = const [];
  List<String> _dietary = const [];
  List<String> _healthConditions = const [];
  bool _loading = true;
  bool _saving = false;

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
          .get();
      if (!mounted) return;
      final data = doc.data();
      setState(() {
        _religions = List<String>.from(data?['religion'] ?? const []);
        _dietary = List<String>.from(data?['dietary'] ?? const []);
        _healthConditions = List<String>.from(
          data?['health_conditions'] ?? const [],
        );
        _loading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load settings: ${e.message ?? e.code}'),
        ),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({
            'religion': _religions,
            'dietary': _dietary,
            'health_conditions': _healthConditions,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Preferences saved')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editOptions({
    required String title,
    required List<String> options,
    required List<String> selected,
    required ValueChanged<List<String>> onSaved,
  }) async {
    if (_saving) return;
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _OptionsSheet(title: title, options: options, initial: selected),
    );
    if (result != null && mounted) {
      onSaved(result);
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Preferences', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Tap a preference to view or update it.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.church),
            title: const Text('Religion & beliefs'),
            subtitle: Text(
              _religions.isEmpty ? 'Not set' : _religions.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _saving
                ? null
                : () => _editOptions(
                    title: 'Religion & beliefs',
                    options: _religionOptions,
                    selected: _religions,
                    onSaved: (value) => setState(() => _religions = value),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.restaurant),
            title: const Text('Dietary requirements'),
            subtitle: Text(
              _dietary.isEmpty ? 'Not set' : _dietary.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _saving
                ? null
                : () => _editOptions(
                    title: 'Dietary requirements',
                    options: _dietaryOptions,
                    selected: _dietary,
                    onSaved: (value) => setState(() => _dietary = value),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.medical_information_outlined),
            title: const Text('Health conditions'),
            subtitle: Text(
              _healthConditions.isEmpty
                  ? 'Not set'
                  : _healthConditions
                        .map(HealthCondition.fromId)
                        .whereType<HealthCondition>()
                        .map((condition) => condition.label)
                        .join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _saving
                ? null
                : () => _editOptions(
                    title: 'Health conditions',
                    options: [
                      for (final condition in HealthCondition.conditions)
                        condition.label,
                    ],
                    selected: [
                      for (final id in _healthConditions)
                        if (HealthCondition.fromId(id) case final condition?)
                          condition.label,
                    ],
                    onSaved: (labels) => setState(() {
                      _healthConditions = [
                        for (final condition in HealthCondition.conditions)
                          if (labels.contains(condition.label)) condition.id,
                      ];
                    }),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        BodyMeasurementsCard(
          key: ValueKey(widget.user.uid),
          userId: widget.user.uid,
        ),
        const SizedBox(height: 8),
        HealthDataCard(user: widget.user),
        if (_saving) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

/// Checkbox sheet listing common options plus a custom "Other" entry.
class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({
    required this.title,
    required this.options,
    required this.initial,
  });

  final String title;
  final List<String> options;
  final List<String> initial;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late final Set<String> _selected = widget.initial.toSet();
  final _otherController = TextEditingController();
  String? _otherValue;

  @override
  void initState() {
    super.initState();
    // Anything previously saved that isn't a common option shows as "Other".
    final extras = widget.initial
        .where((v) => !widget.options.contains(v))
        .toList();
    if (extras.isNotEmpty) {
      _otherValue = extras.join(', ');
      _otherController.text = _otherValue!;
      _selected.add(_otherValue!);
    }
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  void _toggle(String option, bool value) {
    setState(() {
      value ? _selected.add(option) : _selected.remove(option);
    });
  }

  void _applyOther(String value) {
    final trimmed = value.trim();
    if (_otherValue != null) _selected.remove(_otherValue);
    _otherValue = trimmed.isEmpty ? null : trimmed;
    if (_otherValue != null) _selected.add(_otherValue!);
    setState(() {});
  }

  void _done() {
    Navigator.of(context).pop(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final option in widget.options)
                      CheckboxListTile(
                        value: _selected.contains(option),
                        onChanged: (v) => _toggle(option, v ?? false),
                        title: Text(option),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: CheckboxListTile(
                        value: _otherValue != null,
                        onChanged: (_) {},
                        title: TextField(
                          controller: _otherController,
                          decoration: const InputDecoration(
                            labelText: 'Other (type your own)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: _applyOther,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(onPressed: _done, child: const Text('Done')),
            ),
          ],
        ),
      ),
    );
  }
}
