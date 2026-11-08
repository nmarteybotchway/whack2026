import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'diet_summary_card.dart';
import 'diet_window_service.dart';
import 'nutrient_tracker_page.dart';
import 'receipt_parser.dart';
import 'receipt_scan_page.dart';
import 'swap_points.dart' show kSwapPoints;

/// Diet history: scan grocery receipts and browse the stored diet, organised
/// by the day the food was bought.
class DietHistoryPage extends StatefulWidget {
  const DietHistoryPage({super.key, required this.userId});

  final String userId;

  @override
  State<DietHistoryPage> createState() => _DietHistoryPageState();
}

class _DietHistoryPageState extends State<DietHistoryPage>
    with WidgetsBindingObserver {
  /// Created once so rebuilds keep the same stream, and shared with the scan
  /// page so a saved receipt wakes this page's stream straight away.
  late final DietWindowService _diet = DietWindowService(widget.userId);
  late final Stream<List<DietDay>> _days = _diet.recentDaysStream();

  /// Swaps banked this session toward the weekly goal ring. Seeded to a
  /// starting value and reset whenever the app leaves the foreground so a
  /// hackathon demo always has a fresh-looking goal without waiting a week.
  int _weekSwaps = 3;

  static const int _weeklyGoal = 10;

  String get userId => widget.userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app restarts the weekly goal so the ring never sits full;
    // the leaderboard still shows the real banked total.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      setState(() => _weekSwaps = 3);
    }
  }

  Future<void> _scan(BuildContext context) async {
    if (!ReceiptScanPage.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Receipt scanning is only supported on Android and iOS.',
          ),
        ),
      );
      return;
    }
    final saved = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ReceiptScanPage(userId: userId, diet: _diet),
      ),
    );
    if (saved == null || saved == 0 || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved $saved foods to your diet.')));
  }

  Future<void> _delete(
    BuildContext context,
    DietWindowService diet,
    String id,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this day?'),
        content: const Text(
          'This deletes every food stored for that day from Firebase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await diet.deleteDay(id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete. Check your connection and retry.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diet = _diet;
    // The home scaffold extends the body behind the bottom bar, so pad the
    // list by the bar's height to keep the last card reachable.
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text('Diet history', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Scan grocery receipts to build a record of what you eat. Foods are '
          'grouped by the day you got them, and the last two weeks are kept.',
        ),
        const SizedBox(height: 12),
        _WeeklyGoalCard(goal: _weeklyGoal, base: _weekSwaps),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: IconButton.filledTonal(
                onPressed: () => _scan(context),
                tooltip: 'Scan receipt',
                icon: const Icon(Icons.receipt_long),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NutrientTrackerPage(userId: userId),
                  ),
                ),
                tooltip: 'Nutrient tracker',
                icon: const Icon(Icons.insights),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: IconButton.filledTonal(
                onPressed: () => showLeaderboardModal(context, userId),
                tooltip: 'Leaderboard',
                icon: const Icon(Icons.emoji_events_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DietSummaryCard(userId: userId),
        const SizedBox(height: 8),
        StreamBuilder<List<DietDay>>(
          stream: _days,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text(
                'Cannot load your diet. Check Firebase Authentication, '
                'Firestore, and security rules.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final days = snapshot.data!;
            return Column(
              crossAxisAlignment: .stretch,
              children: [
                if (days.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No receipt purchases tracked yet.'),
                  ),
                for (final day in days) ...[
                  _DayCard(
                    day: day,
                    onDelete: () => _delete(context, diet, day.id),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.onDelete});

  final DietDay day;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = day.date;
    final foods = day.foods;
    final nutrition = day.nutrition;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(_formatDay(date)),
        subtitle: Text(
          day.items.isEmpty
              ? '${foods.length} foods'
              : '${foods.length} foods · ${formatPrice(day.spent)}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: .centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final food in foods)
                    Chip(label: Text(_foodLabel(food, day.items[food]))),
                ],
              ),
            ),
          ),
          if (nutrition.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: .centerLeft,
                child: Text(
                  'Nutrients hit',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: .centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in nutrition.entries)
                      _NutrientBox(shorthand: entry.key, value: entry.value),
                  ],
                ),
              ),
            ),
          ],
          Align(
            alignment: .centerLeft,
            child: TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete day'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A food's chip label, e.g. `Milk ×2 · £3.30`. Days saved before
/// quantities were stored have no [totals] and show the name alone.
String _foodLabel(String food, DietItemTotals? totals) => totals == null
    ? food
    : '$food ×${totals.quantity} · ${formatPrice(totals.spent)}';

/// A small box showing one nutrient's shorthand and aggregated amount.
class _NutrientBox extends StatelessWidget {
  const _NutrientBox({required this.shorthand, required this.value});

  final String shorthand;
  final double value;

  static const _labels = {
    'CA': ('Calcium', 'MG'),
    'NA': ('Sodium', 'MG'),
    'FE': ('Iron', 'MG'),
    'K': ('Potassium', 'MG'),
    'MG': ('Magnesium', 'MG'),
    'ZN': ('Zinc', 'MG'),
    'VITA': ('Vitamin A', 'UG'),
    'VITB6': ('Vitamin B6', 'MG'),
    'VITB12': ('Vitamin B12', 'UG'),
    'VITC': ('Vitamin C', 'MG'),
    'VITD': ('Vitamin D', 'UG'),
    'VITE': ('Vitamin E', 'MG'),
    'VITK': ('Vitamin K', 'UG'),
    'FOL': ('Folate', 'UG'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (label, unit) = _labels[shorthand] ?? (shorthand, '');
    final amount = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(value >= 10 ? 1 : 2);
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(
              shorthand,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$amount${unit == 'UG' ? 'µg' : 'mg'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weekly healthy-swap goal card: a progress ring that fills as points are
/// banked, listening live to the user's Firestore total.
class _WeeklyGoalCard extends StatefulWidget {
  const _WeeklyGoalCard({required this.base, required this.goal});

  /// Demo starting offset so the ring begins partway through.
  final int base;

  final int goal;

  @override
  State<_WeeklyGoalCard> createState() => _WeeklyGoalCardState();
}

class _WeeklyGoalCardState extends State<_WeeklyGoalCard> {
  /// Banked swap points from Firestore; null until the first snapshot.
  int? _bankedPoints;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    final page = context.findAncestorStateOfType<_DietHistoryPageState>();
    if (page != null) {
      _sub = FirebaseFirestore.instance
          .collection('users')
          .doc(page.userId)
          .snapshots()
          .listen(
            (snap) {
              if (!mounted) return;
              final points = snap.data()?['swapPoints'];
              setState(
                () => _bankedPoints = points is num ? points.toInt() : 0,
              );
            },
            onError: (_) {},
          );
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  int get _progress {
    // Each banked swap is worth kSwapPoints points; the session base offsets
    // the ring start.
    final swaps = (_bankedPoints ?? 0) ~/ kSwapPoints;
    return (widget.base + swaps).clamp(0, widget.goal);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final clamped = _progress;
    final done = clamped >= widget.goal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: clamped / widget.goal,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: colors.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                      done ? Colors.green.shade600 : colors.primary,
                    ),
                  ),
                  Center(
                    child: done
                        ? Icon(Icons.check, color: Colors.green.shade600)
                        : Text(
                            '$clamped/${widget.goal}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly swap goal', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? 'Goal hit! Every extra swap still counts.'
                        : '${widget.goal - clamped} more healthy '
                            '${widget.goal - clamped == 1 ? 'swap' : 'swaps'} '
                            'this week. Pick a "Try instead" bar after '
                            'scanning.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
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

String _formatDay(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// Opens the weekly health-points leaderboard. Podium rivals are demo data;
/// your own total is read live from Firestore and grows 10 per healthy swap.
Future<void> showLeaderboardModal(BuildContext context, String userId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _LeaderboardSheet(userId: userId),
  );
}

class _LeaderboardEntry {
  const _LeaderboardEntry(this.name, this.points);

  final String name;
  final int points;
}

/// Demo podium standings — deliberately far out of reach so the leaderboard
/// rewards slow, steady swapping rather than a single scan.
const _leaderboardEntries = [
  _LeaderboardEntry('Amara', 480),
  _LeaderboardEntry('Jonny', 410),
  _LeaderboardEntry('Priya', 350),
  _LeaderboardEntry('Sam', 300),
];

/// Your entry shows the real banked total; 0 until the first swap.
const _LeaderboardEntry _you = _LeaderboardEntry('You', 0);

class _LeaderboardSheet extends StatefulWidget {
  const _LeaderboardSheet({required this.userId});

  final String userId;

  @override
  State<_LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<_LeaderboardSheet> {
  static const _podiumHeights = [96.0, 72.0, 56.0, 44.0, 36.0];
  static const _medalColors = [
    Color(0xFFFFD54F), // gold
    Color(0xFFCFD8DC), // silver
    Color(0xFFFFAB91), // bronze
    Color(0xFFE0E0E0),
    Color(0xFFE0E0E0),
  ];
  static const _medalIcons = [
    Icons.emoji_events,
    Icons.emoji_events,
    Icons.emoji_events,
    null,
    null,
  ];

  /// Everything needed to render before the user's total arrives.
  int? _yourPoints;
  bool _loadingPoints = true;

  @override
  void initState() {
    super.initState();
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (!mounted) return;
      final points = doc.data()?['swapPoints'];
      setState(() {
        _yourPoints = points is num ? points.toInt() : 0;
        _loadingPoints = false;
      });
    } on FirebaseException {
      if (mounted) setState(() => _loadingPoints = false);
    }
  }

  /// The five standings: the four demo rivals, then the user's live total
  /// ranked by points. Podium spots (top 3) keep their block styling; rows 4
  /// and 5 render as list tiles.
  List<(_LeaderboardEntry, int)> get _standings {
    final you = _LeaderboardEntry('You', _yourPoints ?? 0);
    final all = [..._leaderboardEntries, you]
      ..sort((a, b) => b.points.compareTo(a.points));
    return [for (final (i, e) in all.indexed) (e, i + 1)];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final standings = _standings;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Healthy swaps leaderboard',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Earn 10 points each time you choose the healthier option.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Silver: 2nd place stands to the left.
                _podiumColumn(context, standings[1]),
                const SizedBox(width: 10),
                // Gold: 1st place in the middle, tallest.
                _podiumColumn(context, standings[0]),
                const SizedBox(width: 10),
                // Bronze: 3rd place to the right.
                _podiumColumn(context, standings[2]),
              ],
            ),
            if (_loadingPoints)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            const SizedBox(height: 16),
            // Ranks 4 and 5 render as simple rows; with the demo podium far
            // ahead, "You" normally sits here at 5th.
            for (final (entry, rank) in standings.skip(3))
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: _medalColors[rank - 1],
                  child: Text(
                    '$rank',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(entry.name),
                trailing: Text(
                  '${entry.points} pts',
                  style: theme.textTheme.titleSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _podiumColumn(
    BuildContext context,
    (_LeaderboardEntry, int) standing,
  ) {
    final theme = Theme.of(context);
    final (entry, rank) = standing;
    final color = _medalColors[rank - 1];
    final icon = _medalIcons[rank - 1];
    final isYou = entry.name == 'You';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: isYou
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.secondaryContainer,
          child: Text(
            entry.name[0],
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(entry.name, style: theme.textTheme.bodyMedium),
        Text(
          '${entry.points} pts',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        // The podium block itself, tall for gold, shorter for the rest.
        Container(
          width: 84,
          height: _podiumHeights[rank - 1],
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 8),
          child: icon == null
              ? Text(
                  '$rank',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Icon(icon, color: Colors.brown, size: 28),
        ),
      ],
    );
  }
}
