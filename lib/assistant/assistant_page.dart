import 'package:flutter/material.dart';

import 'assistant_controller.dart';
import 'assistant_models.dart';
import 'message_spans.dart';
import 'assistant_settings_page.dart';

/// Conversation surface intended to live inside the signed-in home shell.
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.controller});
  final AssistantController controller;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _input.text = widget.controller.inputDraft;
    _input.addListener(_saveDraft);
    widget.controller.initialize().then((_) {
      if (mounted && _input.text.isEmpty) {
        _input.text = widget.controller.inputDraft;
      }
    });
    widget.controller.addListener(_changed);
  }

  void _saveDraft() => widget.controller.setInputDraft(_input.text);

  void _changed() {
    if (!mounted) return;
    final count = widget.controller.messages.length;
    if (count != _lastCount) {
      _lastCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
          );
        }
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.suspend();
    _input.removeListener(_saveDraft);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _input.text.trim();
    if (value.isEmpty ||
        widget.controller.busy ||
        widget.controller.pendingAction != null) {
      return;
    }
    _input.clear();
    await widget.controller.send(value);
  }

  Future<void> _toggleVoiceOutput() async {
    final settings = widget.controller.settings;
    try {
      await widget.controller.setSettings(
        AssistantSettings.fromMap({
          ...settings.toMap(),
          'voiceEnabled': !settings.voiceEnabled,
        }),
      );
      if (mounted) setState(() => _localError = null);
    } catch (e) {
      if (mounted) {
        setState(() => _localError = 'Could not save voice setting: $e');
      }
    }
  }

  void _retry() {
    final messages = widget.controller.messages;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') {
        widget.controller.send(messages[i].text);
        return;
      }
    }
  }

  Future<void> _settings() async {
    await widget.controller.suspend();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssistantSettingsPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final settings = c.settings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 450;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                compact ? 4 : 12,
                compact ? 4 : 8,
                compact ? 2 : 8,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: Icon(
                      Icons.auto_awesome,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          settings.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          c.busy
                              ? 'Working on your answer…'
                              : c.preparingSpeech
                              ? 'Preparing voice…'
                              : c.listening
                              ? 'Listening…'
                              : c.speaking
                              ? 'Speaking…'
                              : settings.tone,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (c.speaking)
                    IconButton(
                      tooltip: 'Stop playback',
                      onPressed: c.stopAudio,
                      icon: const Icon(Icons.stop_circle_outlined),
                    )
                  else
                    IconButton(
                      tooltip: settings.voiceEnabled
                          ? 'Voice output on'
                          : 'Voice output off',
                      onPressed: _toggleVoiceOutput,
                      icon: Icon(
                        settings.voiceEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Assistant settings',
                    onPressed: _settings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  IconButton(
                    tooltip: 'New conversation',
                    onPressed: c.committing ? null : c.clear,
                    icon: const Icon(Icons.add_comment_outlined),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              flex: c.pendingAction == null ? 1 : 2,
              child: c.messages.isEmpty
                  ? _Welcome(name: settings.name)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: c.messages.length + (c.busy ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == c.messages.length) {
                          return const _Thinking();
                        }
                        final message = c.messages[index];
                        return _MessageBubble(message: message, controller: c);
                      },
                    ),
            ),
            if (c.pendingAction != null ||
                c.error != null ||
                _localError != null)
              Flexible(
                flex: 1,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.pendingAction != null)
                        _ActionCard(controller: c, action: c.pendingAction!),
                      if (c.error != null || _localError != null)
                        _ErrorCard(
                          message: c.error ?? _localError!,
                          onRetry: c.error == null
                              ? null
                              : c.pendingAction != null
                              ? c.confirmAction
                              : _retry,
                        ),
                    ],
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  compact ? 2 : 8,
                  12,
                  compact ? 4 : 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton.filledTonal(
                      tooltip: c.listening
                          ? 'Stop listening'
                          : 'Start voice input',
                      onPressed: c.listening
                          ? c.stopListening
                          : c.busy || c.pendingAction != null
                          ? null
                          : () => c.startListening((text) {
                              if (!mounted) return;
                              _input.value = TextEditingValue(
                                text: text,
                                selection: TextSelection.collapsed(
                                  offset: text.length,
                                ),
                              );
                            }),
                      icon: Icon(
                        c.listening
                            ? Icons.stop_rounded
                            : Icons.mic_none_rounded,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: !c.busy && c.pendingAction == null,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Ask about food, preferences…',
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: c.busy || c.pendingAction != null
                          ? null
                          : _send,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 38,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text('Hi, I’m $name', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Ask about ingredients, alternatives, or your food preferences.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.controller});
  final AssistantMessage message;
  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final mine = message.role == 'user';
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(13),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .84,
        ),
        decoration: BoxDecoration(
          color: mine
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText.rich(
              TextSpan(
                children: messageSpans(message.text),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            for (final image in message.images) _ImageCard(image: image),
            if (!mine && message.text.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Read aloud',
                  onPressed: () => controller.replay(message.text),
                  icon: const Icon(Icons.volume_up_outlined, size: 19),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({required this.image});
  final AssistantImage image;
  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: image.url.isEmpty
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(
                      image.url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Icon(Icons.broken_image_outlined, size: 48),
                      ),
                    ),
                  ),
                ),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image.url.isNotEmpty)
              Image.network(
                image.url,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 150,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 100,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    image.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (image.sourcePage.isNotEmpty)
                    SelectableText(
                      image.sourcePage,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.controller, required this.action});
  final AssistantController controller;
  final AssistantAction action;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm this change?',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(action.summary),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: controller.committing
                    ? null
                    : controller.cancelAction,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: controller.committing
                    ? null
                    : controller.confirmAction,
                child: const Text('Confirm'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Thinking extends StatelessWidget {
  const _Thinking();
  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.all(12),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    child: ListTile(
      leading: const Icon(Icons.error_outline),
      title: Text(message),
      trailing: onRetry == null
          ? null
          : TextButton(onPressed: onRetry, child: const Text('Retry')),
    ),
  );
}
