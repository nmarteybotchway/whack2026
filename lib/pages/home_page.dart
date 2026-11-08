import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../assistant/assistant_controller.dart';
import '../assistant/assistant_page.dart';
import '../assistant/assistant_repository.dart';
import '../diet/diet_history_page.dart';
import '../garden/nutrient_garden.dart';
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

const _rightTabs = [
  _Tab('Assistant', Icons.chat_bubble_outline, Icons.chat_bubble),
  _Tab('Settings', Icons.settings_outlined, Icons.settings),
];

const _tabs = [..._leftTabs, ..._rightTabs];

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _index = 0;

  /// Receipt scans finished this session; keys the home tab so its nutrient
  /// cards reload with the new data.
  int _scans = 0;
  late final HealthTrackingController _tracking;
  late final AssistantController _assistant;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _assistant = AssistantController(
      data: FirestoreAssistantRepository(
        userId: widget.user.uid,
        profile: {
          'displayName': widget.user.displayName,
          'email': widget.user.email,
          'isAnonymous': widget.user.isAnonymous,
          'emailVerified': widget.user.emailVerified,
          'phoneNumber': widget.user.phoneNumber,
          'photoURL': widget.user.photoURL,
          'createdAt': widget.user.metadata.creationTime
              ?.toUtc()
              .toIso8601String(),
          'lastSignInAt': widget.user.metadata.lastSignInTime
              ?.toUtc()
              .toIso8601String(),
        },
      ),
    );
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
    WidgetsBinding.instance.removeObserver(this);
    _assistant.dispose();
    _tracking.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A microphone permission dialog can make the app briefly inactive.
    // Stop capture when it actually leaves the foreground, without cancelling
    // the user's first microphone request while permission is being granted.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _assistant.suspend();
    }
  }

  void _selectTab(int index) {
    if (_index == index) return;
    if (_index == 2) _assistant.suspend();
    if (index == 2) _assistant.initialize();
    setState(() => _index = index);
  }

  Future<void> _scan() async {
    await _assistant.suspend();
    if (!mounted) return;
    final tab = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) =>
            ScanPage(userId: widget.user.uid, assistant: _assistant),
      ),
    );
    if (!mounted) return;
    // Returning a tab index means the user tapped a tab on the scan-result
    // sheet's navigation bar; land them on it. Otherwise treat it as a scan.
    if (tab != null) {
      setState(() => _index = tab);
      return;
    }
    setState(() => _scans++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tabs[_index].label)),
      body: switch (_index) {
        // Keyed by scan count so the nutrient cards reload after a scan.
        0 => _HomeTab(key: ValueKey(_scans), user: widget.user),
        1 => DietHistoryPage(
          key: ValueKey(widget.user.uid),
          userId: widget.user.uid,
        ),
        2 => AssistantPage(controller: _assistant),
        3 => SettingsPage(
          key: ValueKey(widget.user.uid),
          user: widget.user,
          tracking: _tracking,
          assistant: _assistant,
        ),
        _ => const SizedBox.shrink(),
      },
      bottomNavigationBar: _BottomBar(
        index: _index,
        onSelect: _selectTab,
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
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 2,
        onPressed: onPressed,
        child: const Icon(Icons.qr_code_scanner, size: 30),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user.displayName ?? user.email?.split('@').first ?? 'there';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Hi, $name',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your health, in one place.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        NutrientGarden(key: ValueKey(user.uid), userId: user.uid),
      ],
    );
  }
}
