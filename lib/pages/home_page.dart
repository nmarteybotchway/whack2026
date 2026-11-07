import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../health_data/blood_pressure_page.dart';
import '../scan/scan_page.dart';
import '../services/text_to_speech_service.dart';

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
  _Tab('Track', Icons.timeline_outlined, Icons.timeline),
];

const _rightTabs = [
  _Tab('Health', Icons.favorite_outline, Icons.favorite),
  _Tab('Leaderboards', Icons.leaderboard_outlined, Icons.leaderboard),
];

const _tabs = [..._leftTabs, ..._rightTabs];

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final _textToSpeech = TextToSpeechService();

  Future<void> _speakDemo() async {
    try {
      await _textToSpeech.speak(
        'Hello! This is a demo of text to speech on your Android phone.',
        locale: 'en-GB',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not speak the demo text: $error')),
      );
    }
  }

  void _scan() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ScanPage()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: Text(_tabs[_index].label),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: _index == 0
          ? _HomeTab(user: widget.user, onSpeakDemo: _speakDemo)
          : _index == 2
          ? BloodPressurePage(
              key: ValueKey(widget.user.uid),
              userId: widget.user.uid,
            )
          : _PlaceholderTab(tab: _tabs[_index]),
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
  const _HomeTab({required this.user, required this.onSpeakDemo});

  final User user;
  final VoidCallback onSpeakDemo;

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
        for (var i = 1; i <= 5; i++)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: i == 1 ? const Icon(Icons.volume_up) : Text('$i'),
              ),
              title: Text(
                i == 1 ? 'Text-to-speech demo' : 'Placeholder item $i',
              ),
              subtitle: Text(i == 1 ? 'Tap to hear a sample' : 'Mock content'),
              trailing: Icon(i == 1 ? Icons.play_arrow : Icons.chevron_right),
              onTap: i == 1 ? onSpeakDemo : null,
            ),
          ),
      ],
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
