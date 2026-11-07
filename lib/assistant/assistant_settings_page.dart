import 'package:flutter/material.dart';

import 'assistant_controller.dart';
import 'assistant_models.dart';

class AssistantSettingsPage extends StatefulWidget {
  const AssistantSettingsPage({super.key, required this.controller});
  final AssistantController controller;

  @override
  State<AssistantSettingsPage> createState() => _AssistantSettingsPageState();
}

class _AssistantSettingsPageState extends State<AssistantSettingsPage> {
  late AssistantSettings _settings;
  late final TextEditingController _name;
  late final TextEditingController _instructions;
  late final TextEditingController _locale;
  List<Map<String, String>> _voices = const [];
  bool _saving = false, _loadingVoices = true, _previewing = false;
  bool _previewSpeaking = false;
  int _formRevision = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _settings = widget.controller.settings;
    _name = TextEditingController(text: _settings.name);
    _instructions = TextEditingController(text: _settings.instructions);
    _locale = TextEditingController(text: _settings.locale);
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await widget.controller.availableVoices().timeout(
        const Duration(seconds: 6),
        onTimeout: () => const <Map<String, String>>[],
      );
      if (mounted) {
        setState(() {
          _voices = voices;
          _loadingVoices = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVoices = false);
    }
  }

  AssistantSettings _compose() => AssistantSettings.fromMap({
    ..._settings.toMap(),
    'name': _name.text.trim().isEmpty ? 'Assistant' : _name.text.trim(),
    'instructions': _instructions.text,
  });

  void _update(Map<String, Object?> fields) => setState(
    () => _settings = AssistantSettings.fromMap({
      ..._settings.toMap(),
      ...fields,
    }),
  );

  List<Map<String, String>> get _uniqueVoices {
    final seen = <String>{};
    return _voices.where((voice) {
      final name = voice['name'] ?? voice['identifier'] ?? '';
      return name.isNotEmpty && seen.add(name);
    }).toList();
  }

  void _chooseVoice(String? name) {
    final selected = _uniqueVoices
        .where((voice) => (voice['name'] ?? voice['identifier'] ?? '') == name)
        .firstOrNull;
    final locale = selected?['locale'];
    if (locale != null && locale.isNotEmpty) _locale.text = locale;
    _update({
      'voiceName': name ?? '',
      if (locale != null && locale.isNotEmpty) 'locale': locale,
    });
  }

  Future<void> _readPreview(String sample, AssistantSettings settings) async {
    if (_previewSpeaking) {
      await widget.controller.stopAudio();
      if (mounted) setState(() => _previewSpeaking = false);
      return;
    }
    try {
      if (mounted) setState(() => _previewSpeaking = true);
      await widget.controller.replay(sample, preferences: settings);
    } catch (e) {
      if (mounted) setState(() => _error = 'Preview speech failed: $e');
    } finally {
      if (mounted) setState(() => _previewSpeaking = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final value = _compose();
    if (_instructions.text.length > 1000) {
      setState(
        () => _error = 'Instructions must be 1,000 characters or fewer.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.setSettings(value);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save settings: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _preview() async {
    if (_previewing) return;
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final sample = await widget.controller.previewSettings(_compose());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Personality preview'),
          content: SelectableText(sample),
          actions: [
            if (_settings.voiceEnabled)
              TextButton.icon(
                onPressed: () => _readPreview(sample, _compose()),
                icon: Icon(
                  _previewSpeaking ? Icons.stop : Icons.volume_up_outlined,
                ),
                label: Text(_previewSpeaking ? 'Stop preview' : 'Read aloud'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Preview failed: $e');
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  void _reset() {
    setState(() {
      _settings = const AssistantSettings();
      _name.text = _settings.name;
      _instructions.text = '';
      _locale.text = _settings.locale;
      _formRevision++;
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant personality'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _reset,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Make your assistant feel right for you.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Assistant name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('tone-$_formRevision'),
            initialValue: _settings.tone,
            decoration: const InputDecoration(
              labelText: 'Tone',
              border: OutlineInputBorder(),
            ),
            items: const [
              'Friendly coach',
              'Calm guide',
              'Direct assistant',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) {
              if (v != null) _update({'tone': v});
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('length-$_formRevision'),
            initialValue: _settings.answerLength,
            decoration: const InputDecoration(
              labelText: 'Answer length',
              border: OutlineInputBorder(),
            ),
            items: const ['short', 'balanced', 'detailed']
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v[0].toUpperCase() + v.substring(1)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _update({'answerLength': v});
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Supportive encouragement'),
            value: _settings.supportive,
            onChanged: (v) => _update({'supportive': v}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Light humor'),
            value: _settings.humor,
            onChanged: (v) => _update({'humor': v}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _instructions,
            maxLength: 1000,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Additional instructions',
              hintText: 'For example: Be practical and avoid emojis.',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text('Voice', style: theme.textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Speak assistant replies'),
            value: _settings.voiceEnabled,
            onChanged: (v) => _update({'voiceEnabled': v}),
          ),
          if (_loadingVoices) const LinearProgressIndicator(),
          if (_uniqueVoices.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey('voice-$_formRevision'),
              isExpanded: true,
              initialValue:
                  _uniqueVoices.any(
                    (v) =>
                        (v['name'] ?? v['identifier'] ?? '') ==
                        _settings.voiceName,
                  )
                  ? _settings.voiceName
                  : '',
              decoration: const InputDecoration(
                labelText: 'Device voice',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('System default'),
                ),
                ..._uniqueVoices.map((v) {
                  final name = v['name'] ?? v['identifier'] ?? '';
                  final locale = v['locale'] ?? '';
                  return DropdownMenuItem(
                    value: name,
                    child: Text(
                      locale.isEmpty ? name : '$name · $locale',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: _chooseVoice,
            ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('locale-$_formRevision'),
            controller: _locale,
            decoration: const InputDecoration(
              labelText: 'Voice locale',
              hintText: 'en-GB',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _update({'locale': v}),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Speech speed'),
              Expanded(
                child: Slider(
                  value: _settings.speechRate.clamp(.2, .8),
                  min: .2,
                  max: .8,
                  divisions: 6,
                  label: _settings.speechRate.toStringAsFixed(1),
                  onChanged: (v) => _update({'speechRate': v}),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _previewing ? null : _preview,
            icon: _previewing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(
              _previewing ? 'Creating preview…' : 'Preview personality',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save settings'),
          ),
        ],
      ),
    );
  }
}
