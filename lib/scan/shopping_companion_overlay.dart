import 'package:flutter/material.dart';

import '../assistant/assistant_models.dart';
import 'shopping_companion_briefing.dart';
import 'shopping_companion_controller.dart';

/// Compact shopping companion panel to place over the live camera preview.
/// The camera page owns the shared controller and its lifetime.
class ShoppingCompanionOverlay extends StatefulWidget {
  const ShoppingCompanionOverlay({
    super.key,
    required this.controller,
    this.scanning = false,
    this.onShowDetails,
  });

  final ShoppingCompanionController controller;
  final bool scanning;
  final VoidCallback? onShowDetails;

  @override
  State<ShoppingCompanionOverlay> createState() =>
      _ShoppingCompanionOverlayState();
}

class _ShoppingCompanionOverlayState extends State<ShoppingCompanionOverlay> {
  final _draftController = TextEditingController();
  bool _expanded = false;
  bool _updatingFromController = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _syncDraft();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncDraft();
    setState(() {});
  }

  void _syncDraft() {
    final value = widget.controller.draft;
    if (value == _draftController.text) return;
    _updatingFromController = true;
    _draftController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _updatingFromController = false;
  }

  @override
  void didUpdateWidget(covariant ShoppingCompanionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _syncDraft();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _draftController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await widget.controller.start();
    if (mounted && widget.controller.active) setState(() => _expanded = true);
  }

  Future<void> _collapse() async {
    setState(() => _expanded = false);
    // A collapsed panel should never leave a hidden microphone running.
    if (widget.controller.listening) {
      await widget.controller.stopListening();
    }
    if (widget.controller.speaking) {
      await widget.controller.stopSpeech();
    }
  }

  Future<void> _submit() async {
    final draft = _draftController.text.trim();
    if (draft.isEmpty ||
        widget.controller.busy ||
        widget.controller.committing) {
      return;
    }
    await widget.controller.submit(draft);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        _syncDraft();
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height * .55;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Material(
                color: Colors.black.withValues(alpha: .84),
                elevation: 12,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white),
                  child: IconTheme(
                    data: const IconThemeData(color: Colors.white),
                    child: controller.active
                        ? _activePanel(controller)
                        : _inactivePanel(controller),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _inactivePanel(ShoppingCompanionController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Shopping companion',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                if (controller.error != null)
                  Text(
                    controller.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: controller.loading ? null : _start,
            icon: controller.loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Widget _activePanel(ShoppingCompanionController controller) {
    final status = widget.scanning
        ? 'Scanning product…'
        : controller.listening
        ? 'Listening'
        : controller.busy
        ? 'Thinking'
        : controller.speaking
        ? 'Speaking'
        : 'Shopping companion active';
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 6),
          child: Row(
            children: [
              Icon(
                controller.listening
                    ? Icons.mic_rounded
                    : controller.speaking
                    ? Icons.volume_up_rounded
                    : Icons.shopping_bag_outlined,
                color: scheme.primaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (controller.speaking)
                IconButton(
                  tooltip: 'Stop speech',
                  onPressed: controller.stopSpeech,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              IconButton(
                tooltip: _expanded ? 'Collapse companion' : 'Expand companion',
                onPressed: _expanded
                    ? _collapse
                    : () => setState(() => _expanded = true),
                icon: Icon(_expanded ? Icons.expand_more : Icons.expand_less),
              ),
              if (widget.onShowDetails != null)
                IconButton(
                  tooltip: 'Show scan details',
                  onPressed: widget.onShowDetails,
                  icon: const Icon(Icons.open_in_new_rounded),
                ),
              IconButton(
                tooltip: 'Stop shopping companion',
                onPressed: controller.committing ? null : controller.stop,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (_expanded)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.briefing case final briefing?) ...[
                    _BriefingCard(briefing: briefing),
                  ],
                  if (controller.reply case final reply?)
                    _ReplyCard(reply: reply, onReplay: controller.replay),
                  if (controller.error != null)
                    _ErrorBanner(
                      message: controller.error!,
                      onRetry: controller.retryBriefing,
                    ),
                  if (controller.pendingAction case final action?)
                    _PendingActionCard(
                      action: action,
                      busy: controller.committing,
                      onConfirm: controller.confirmAction,
                      onCancel: controller.cancelAction,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed:
                          controller.active &&
                              controller.briefing != null &&
                              !controller.busy &&
                              !controller.committing
                          ? controller.requestAlternatives
                          : null,
                      icon: const Icon(Icons.compare_arrows_rounded),
                      label: const Text('Show alternatives'),
                    ),
                  ),
                  if (controller.briefing == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Ask a general question now, or scan a product for a tailored briefing.',
                      ),
                    ),
                  _composer(controller),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _composer(ShoppingCompanionController controller) {
    final waiting = controller.busy || controller.committing;
    final canInteract = controller.active && !waiting;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton.filledTonal(
            key: const ValueKey('companion-mic'),
            tooltip: controller.listening
                ? 'Stop listening'
                : 'Speak a question',
            onPressed: controller.listening
                ? controller.stopListening
                : !canInteract
                ? null
                : controller.listen,
            icon: Icon(
              controller.listening
                  ? Icons.stop_rounded
                  : Icons.mic_none_rounded,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _draftController,
              enabled: canInteract,
              minLines: 1,
              maxLines: 3,
              onChanged: (value) {
                if (!_updatingFromController) controller.setDraft(value);
              },
              onSubmitted: (_) => _submit(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: controller.briefing == null
                    ? 'Ask a general question or scan a product…'
                    : 'Ask about this product…',
                hintStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .12),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: 'Send question',
            onPressed: !canInteract ? null : _submit,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({required this.briefing});
  final ProductBriefing briefing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  briefing.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(briefing.text),
          for (final alternative in briefing.alternatives)
            _AlternativeCard(alternative: alternative),
        ],
      ),
    );
  }
}

class _AlternativeCard extends StatelessWidget {
  const _AlternativeCard({required this.alternative});
  final CompanionAlternative alternative;

  @override
  Widget build(BuildContext context) {
    final image = alternative.image;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image?.url.isNotEmpty == true)
            Image.network(
              image!.url,
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 76,
                height: 76,
                child: Icon(Icons.broken_image_outlined),
              ),
            )
          else
            const SizedBox(
              width: 76,
              height: 76,
              child: Icon(Icons.restaurant_outlined),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alternative.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (alternative.detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(alternative.detail),
                  ],
                  if (image?.sourcePage.isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    SelectableText(
                      image!.sourcePage,
                      style: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({required this.reply, required this.onReplay});
  final AssistantMessage reply;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text('Assistant')),
              IconButton(
                tooltip: 'Replay reply',
                onPressed: onReplay,
                icon: const Icon(Icons.volume_up_outlined, size: 18),
              ),
            ],
          ),
          SelectableText(reply.text),
          for (final image in reply.images)
            _AlternativeCard(
              alternative: CompanionAlternative(name: image.name, image: image),
            ),
        ],
      ),
    );
  }
}

class _PendingActionCard extends StatelessWidget {
  const _PendingActionCard({
    required this.action,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
  });

  final AssistantAction action;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.shade900,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirm this change?',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(action.summary),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : onCancel,
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy ? null : onConfirm,
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade900,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
