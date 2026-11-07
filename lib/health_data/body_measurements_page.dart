import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'models/body_measurements.dart';

/// Manual measurements, saved separately from the paused Health Connect feature.
class BodyMeasurementsPage extends StatefulWidget {
  const BodyMeasurementsPage({super.key, required this.userId});

  final String userId;

  @override
  State<BodyMeasurementsPage> createState() => _BodyMeasurementsPageState();
}

class _BodyMeasurementsPageState extends State<BodyMeasurementsPage> {
  final _formKey = GlobalKey<FormState>();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  String _heightUnit = 'cm';
  String _weightUnit = 'kg';

  String _format(double value) =>
      value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');

  double? get _heightCm {
    if (_heightUnit == 'cm') return _number(_height.text);
    final feet = _number(_feet.text);
    final inches = _number(_inches.text);
    if (feet == null ||
        inches == null ||
        !feet.isFinite ||
        feet < 0 ||
        feet != feet.truncateToDouble() ||
        !inches.isFinite ||
        inches < 0 ||
        inches >= 12) {
      return null;
    }
    return BodyMeasurements.heightFromImperial(feet, inches);
  }

  double? get _weightKg {
    final value = _number(_weight.text);
    if (value == null) return null;
    return _weightUnit == 'kg'
        ? value
        : BodyMeasurements.weightFromPounds(value);
  }

  BodyMeasurements? get _measurements {
    final height = _heightCm;
    final weight = _weightKg;
    if (height == null || weight == null) return null;
    final result = BodyMeasurements(heightCm: height, weightKg: weight);
    return result.isValid ? result : null;
  }

  void _fillHeight(double cm) {
    _height.text = _format(cm);
    // Round only display values, carrying 12 inches into the feet field.
    final total = double.parse(
      (cm / BodyMeasurements.centimetresPerInch).toStringAsFixed(6),
    );
    final feet = (total / 12).floor();
    _feet.text = '$feet';
    _inches.text = _format(total - feet * 12);
  }

  void _changeHeightUnit(String unit) {
    final cm = _heightCm;
    setState(() {
      if (cm != null && cm.isFinite && cm > 0 && cm <= 300) {
        _fillHeight(cm);
      } else {
        _height.clear();
        _feet.clear();
        _inches.clear();
      }
      _heightUnit = unit;
      _message = null;
    });
  }

  void _changeWeightUnit(String unit) {
    final kg = _weightKg;
    setState(() {
      _weight.text = kg != null && kg.isFinite && kg > 0 && kg <= 1000
          ? _format(unit == 'kg' ? kg : kg / BodyMeasurements.kilogramsPerPound)
          : '';
      _weightUnit = unit;
      _message = null;
    });
  }

  void _edited(String _) => setState(() => _message = null);
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _message;

  DocumentReference<Map<String, dynamic>> get _document => FirebaseFirestore
      .instance
      .collection('users')
      .doc(widget.userId)
      .collection('healthProfile')
      .doc('measurements');

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
      final snapshot = await _document.get();
      if (!mounted) return;
      final data = snapshot.data();
      _heightUnit = data?['heightUnit'] == 'ft_in' ? 'ft_in' : 'cm';
      _weightUnit = data?['weightUnit'] == 'lb' ? 'lb' : 'kg';
      final cm = (data?['heightCm'] as num?)?.toDouble();
      final kg = (data?['weightKg'] as num?)?.toDouble();
      if (cm != null) _fillHeight(cm);
      _weight.text = kg == null
          ? ''
          : _format(
              _weightUnit == 'kg'
                  ? kg
                  : kg / BodyMeasurements.kilogramsPerPound,
            );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load your measurements. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _number(String? value) =>
      double.tryParse((value ?? '').trim().replaceAll(',', '.'));

  String? _validate(String? value, String label, double maximum) {
    final number = _number(value);
    if (number == null || !number.isFinite || number <= 0 || number > maximum) {
      return 'Enter $label greater than 0 and up to ${maximum.toInt()}.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final measurements = _measurements;
    if (measurements == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      if (FirebaseAuth.instance.currentUser?.uid != widget.userId) {
        throw StateError('Account changed');
      }
      await _document.set({
        'heightCm': measurements.heightCm,
        'weightKg': measurements.weightKg,
        'bmi': measurements.bmi,
        'heightUnit': _heightUnit,
        'weightUnit': _weightUnit,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _message = 'Height, weight and BMI saved.');
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'permission-denied'
              ? 'Saving was denied. Check that the health profile security rules are deployed.'
              : 'Could not save your measurements. Check your connection and try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save. Sign in again and retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _feet.dispose();
    _inches.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your measurements',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your height and weight. You can update them here whenever they change.',
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: _heightUnit,
                  decoration: const InputDecoration(labelText: 'Height unit'),
                  items: const [
                    DropdownMenuItem(
                      value: 'cm',
                      child: Text('Centimetres (cm)'),
                    ),
                    DropdownMenuItem(
                      value: 'ft_in',
                      child: Text('Feet and inches'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => _changeHeightUnit(value!),
                ),
                const SizedBox(height: 16),
                if (_heightUnit == 'cm')
                  TextFormField(
                    key: const ValueKey('heightCm'),
                    controller: _height,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: _edited,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      suffixText: 'cm',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => _validate(value, 'height in cm', 300),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('heightFeet'),
                          controller: _feet,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onChanged: _edited,
                          decoration: const InputDecoration(
                            labelText: 'Feet',
                            suffixText: 'ft',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final feet = _number(value);
                            if (feet == null ||
                                !feet.isFinite ||
                                feet < 0 ||
                                feet > 9 ||
                                feet != feet.truncateToDouble()) {
                              return 'Enter whole feet (0–9).';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('heightInches'),
                          controller: _inches,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          onChanged: _edited,
                          decoration: const InputDecoration(
                            labelText: 'Inches',
                            suffixText: 'in',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final inches = _number(value);
                            if (inches == null ||
                                !inches.isFinite ||
                                inches < 0 ||
                                inches >= 12) {
                              return 'Enter 0 to under 12.';
                            }
                            final cm = _heightCm;
                            if (cm == null || cm <= 0 || cm > 300) {
                              return 'Check total height.';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _weightUnit,
                  decoration: const InputDecoration(labelText: 'Weight unit'),
                  items: const [
                    DropdownMenuItem(
                      value: 'kg',
                      child: Text('Kilograms (kg)'),
                    ),
                    DropdownMenuItem(value: 'lb', child: Text('Pounds (lb)')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => _changeWeightUnit(value!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: ValueKey(_weightUnit),
                  controller: _weight,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: _edited,
                  decoration: InputDecoration(
                    labelText: 'Weight',
                    suffixText: _weightUnit,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final kg = _weightKg;
                    if (kg == null || !kg.isFinite || kg <= 0 || kg > 1000) {
                      return _weightUnit == 'kg'
                          ? 'Enter weight greater than 0 and up to 1000 kg.'
                          : 'Enter weight greater than 0 and up to 2204.62 lb.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (!_saving) _save();
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _measurements == null
                          ? 'BMI will appear once height and weight are entered.'
                          : 'BMI: ${_measurements!.bmi.toStringAsFixed(1)} kg/m²',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save measurements'),
                ),
                if (_saving) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_message!, semanticsLabel: _message),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _load,
                    child: const Text('Reload saved measurements'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
