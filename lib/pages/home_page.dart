import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../diet/diet_history_page.dart';
import '../health_data/health_tracking_controller.dart';
import '../health_data/health_tracking_card.dart';
import '../scan/scan_page.dart';
import 'settings_page.dart';

/// Mock home page shown once a Firebase user is signed in.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.user});

  final User user;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _leftTabs = [
  _Tab('Home', Icons.home_outlined, Icons.home),
  _Tab('History', Icons.history_outlined, Icons.history),
];

const _rightTabs = [_Tab('Settings', Icons.settings_outlined, Icons.settings)];

const _tabs = [..._leftTabs, ..._rightTabs];

class _HomePageState extends State<HomePage> {
  int _index = 0;
  late final HealthTrackingController _tracking;

  @override
  void initState() {
    super.initState();
    _tracking = HealthTrackingController(widget.user.uid);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _tracking.initialize();
      if (mounted && !_tracking.introSeen) {
        await showHealthTrackingIntro(context, _tracking);
      }
    });
  }

  @override
  void dispose() {
    _tracking.dispose();
    super.dispose();
  }

  void _scan() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanPage(userId: widget.user.uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: Text(_tabs[_index].label),
      ),
      body: switch (_index) {
        0 => _HomeTab(user: widget.user),
        1 => DietHistoryPage(
          key: ValueKey(widget.user.uid),
          userId: widget.user.uid,
        ),
        2 => SettingsPage(
          key: ValueKey(widget.user.uid),
          user: widget.user,
          tracking: _tracking,
        ),
        _ => const SizedBox.shrink(),
      },
      bottomNavigationBar: _BottomBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
        onScan: _scan,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.onSelect,
    required this.onScan,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    Widget item(int i) => Expanded(
      child: _NavItem(
        tab: _tabs[i],
        selected: index == i,
        onTap: () => onSelect(i),
      ),
    );

    return BottomAppBar(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          for (var i = 0; i < _leftTabs.length; i++) item(i),
          Expanded(
            child: Center(child: _ScanButton(onPressed: onScan)),
          ),
          for (var i = _leftTabs.length; i < _tabs.length; i++) item(i),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: .center,
        children: [
          Icon(selected ? tab.selectedIcon : tab.icon, color: color),
          const SizedBox(height: 4),
          Text(
            tab.label,
            maxLines: 1,
            overflow: .ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 60,
      child: FloatingActionButton(
        heroTag: null,
        tooltip: 'Scan',
        shape: const CircleBorder(),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: onPressed,
        child: const Icon(Icons.qr_code_scanner, size: 30),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user.displayName ?? user.email ?? 'Guest';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Hi, $name', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('UID: ${user.uid}', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        const _SpeechToTextDemoCard(),
      ],
    );
  }
}

class _SpeechToTextDemoCard extends StatefulWidget {
  const _SpeechToTextDemoCard();

  @override
  State<_SpeechToTextDemoCard> createState() => _SpeechToTextDemoCardState();
}

class _SpeechToTextDemoCardState extends State<_SpeechToTextDemoCard> {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  bool _initializing = false;
  bool _listening = false;
  String _recognizedWords = '';
  String? _error;

  Future<void> _toggleListening() async {
    if (_speech.isListening) {
      await _speech.stop();
      return;
    }

    setState(() {
      _initializing = true;
      _recognizedWords = '';
      _error = null;
    });

    try {
      _available = await _speech.initialize(
        onStatus: _onStatus,
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _error = error.errorMsg;
            _listening = false;
          });
        },
      );
      if (!_available) {
        if (mounted) {
          setState(() => _error = 'Speech recognition is unavailable.');
        }
        return;
      }

      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: 'en-GB',
          partialResults: true,
          listenFor: Duration(seconds: 30),
          pauseFor: Duration(seconds: 5),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  void _onStatus(String status) {
    if (!mounted) return;
    setState(() {
      _listening = status == SpeechToText.listeningStatus;
    });
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() => _recognizedWords = result.recognizedWords);
  }

  @override
  void dispose() {
    if (_speech.isListening) unawaited(_speech.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle =
        _error ??
        (_listening
            ? (_recognizedWords.isEmpty
                  ? 'Listening… tap to stop'
                  : _recognizedWords)
            : _recognizedWords.isEmpty
            ? 'Tap to speak, then tap to stop'
            : 'Heard: $_recognizedWords');

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(_listening ? Icons.mic : Icons.mic_none),
        ),
        title: const Text('Speech-to-text test'),
        subtitle: Text(subtitle),
        trailing: _initializing
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_listening ? Icons.stop : Icons.mic),
        onTap: _initializing ? null : _toggleListening,
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.tab});

  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          Icon(tab.selectedIcon, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(tab.label, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Coming soon'),
        ],
      ),
    );
  }
}
