import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

const _ink = Color(0xFF173B35);
const _paper = Color(0xFFF5F7EF);

class MiniGameInfo {
  const MiniGameInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.duration,
    required this.difficulty,
    required this.instructions,
  });
  final String title, subtitle, duration, difficulty, instructions;
  final IconData icon;
  final Color color;
}

const miniGames = <MiniGameInfo>[
  MiniGameInfo(
    title: 'Rainbow Match',
    subtitle: 'Find the colourful pairs',
    icon: Icons.grid_view_rounded,
    color: Color(0xFFE66F67),
    duration: '3–5 min',
    difficulty: 'Easy',
    instructions: 'Turn over two cards at a time and remember where each food belongs. Find all six pairs in as few moves as you can.',
  ),
  MiniGameInfo(
    title: 'Garden Recall',
    subtitle: 'Follow the garden melody',
    icon: Icons.local_florist_rounded,
    color: Color(0xFF66A878),
    duration: '2–4 min',
    difficulty: 'Gentle',
    instructions: 'Watch the garden tiles light up, then tap the same sequence. Each round adds one new tile. How far can your memory grow?',
  ),
  MiniGameInfo(
    title: 'Hydration Dash',
    subtitle: 'Catch drops, dodge leaves',
    icon: Icons.water_drop_rounded,
    color: Color(0xFF4B9EC5),
    duration: '45 sec',
    difficulty: 'Quick',
    instructions: 'Slide the cup left and right to catch falling water drops. Avoid the leaves. You have 45 seconds to make your best score.',
  ),
  MiniGameInfo(
    title: 'Focus Flow',
    subtitle: 'Find your moment',
    icon: Icons.brightness_5_rounded,
    color: Color(0xFF9A78C8),
    duration: '1–2 min',
    difficulty: 'Steady',
    instructions: 'A dot circles the ring. Tap when it passes through the glowing target arc. There are ten attempts; consecutive hits build a bonus.',
  ),
  MiniGameInfo(
    title: 'Market Sort',
    subtitle: 'A quick market mix-up',
    icon: Icons.shopping_basket_rounded,
    color: Color(0xFFE4A446),
    duration: '2–3 min',
    difficulty: 'Easy',
    instructions: 'Sort each market item into fruit, vegetable, or grain. Correct answers build a streak bonus. You’ll see all 12 items.',
  ),
  MiniGameInfo(
    title: 'Trail Tiles',
    subtitle: 'Put the landscape in order',
    icon: Icons.landscape_rounded,
    color: Color(0xFF4B9B91),
    duration: '3–6 min',
    difficulty: 'Thoughtful',
    instructions: 'Tap a tile beside the empty space to slide it. Arrange the numbered landscape tiles from 1 to 8. Every board is solvable.',
  ),
];

class MiniGamesSection extends StatelessWidget {
  const MiniGamesSection({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Mini games',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE5EFE7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '6 GAMES',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      const Text(
        'A little play, whenever you like.',
        style: TextStyle(color: Color(0xFF61736B)),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < miniGames.length; i++)
        _GameCard(info: miniGames[i], index: i),
    ],
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.info, required this.index});
  final MiniGameInfo info;
  final int index;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MiniGamePage(gameIndex: index),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: info.color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(info.icon, color: info.color, size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF65756E),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _Tag(info.duration),
                        const SizedBox(width: 6),
                        _Tag(info.difficulty),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: info.color,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F0),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: Color(0xFF52645C),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class MiniGamePage extends StatefulWidget {
  const MiniGamePage({super.key, required this.gameIndex});
  final int gameIndex;
  @override
  State<MiniGamePage> createState() => _MiniGamePageState();
}

class _MiniGamePageState extends State<MiniGamePage> {
  bool _started = false;
  int _round = 0;
  @override
  Widget build(BuildContext context) {
    final info = miniGames[widget.gameIndex];
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        foregroundColor: _ink,
        title: Text(
          info.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [_IconBadge(icon: info.icon, color: info.color)],
      ),
      body: SafeArea(child: _started ? _activeGame() : _intro(info)),
    );
  }

  Widget _intro(MiniGameInfo info) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: info.color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(info.icon, color: info.color, size: 54),
            ),
            const SizedBox(height: 24),
            Text(
              info.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: _ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              info.instructions,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Color(0xFF586B63),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Tag(info.duration),
                const SizedBox(width: 8),
                _Tag(info.difficulty),
              ],
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton.icon(
                onPressed: () => setState(() {
                  _started = true;
                  _round++;
                }),
                style: FilledButton.styleFrom(
                  backgroundColor: info.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Start game',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Just for fun · No health tracking',
              style: TextStyle(fontSize: 12, color: Color(0xFF79877F)),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _activeGame() {
    final key = ValueKey('game-${widget.gameIndex}-$_round');
    switch (widget.gameIndex) {
      case 0:
        return RainbowMatch(key: key, onReplay: _replay);
      case 1:
        return GardenRecall(key: key, onReplay: _replay);
      case 2:
        return HydrationDash(key: key, onReplay: _replay);
      case 3:
        return FocusFlow(key: key, onReplay: _replay);
      case 4:
        return MarketSort(key: key, onReplay: _replay);
      default:
        return TrailTiles(key: key, onReplay: _replay);
    }
  }

  void _replay() => setState(() => _round++);
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: Icon(icon, color: color),
  );
}

Widget _gameBody({required Widget child, required Widget header}) =>
    LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [header, const SizedBox(height: 18), child],
            ),
          ),
        ),
      ),
    );
Widget _stat(String label, String value, Color color) => Expanded(
  child: Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF75827C),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  ),
);
Widget _stats(List<Widget> children) => Row(
  children: [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) const SizedBox(width: 9),
      children[i],
    ],
  ],
);
Widget _status(String text, Color color) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .12),
    borderRadius: BorderRadius.circular(14),
  ),
  child: Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(color: color, fontWeight: FontWeight.w800),
  ),
);
Widget _result({
  required String title,
  required String detail,
  required Color color,
  required VoidCallback replay,
  String button = 'Play again',
}) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(22),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
  ),
  child: Column(
    children: [
      Icon(Icons.celebration_rounded, color: color, size: 40),
      const SizedBox(height: 8),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w900,
          color: _ink,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        detail,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF65756E)),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton.icon(
          onPressed: replay,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.replay_rounded),
          label: Text(button),
        ),
      ),
    ],
  ),
);

// Rainbow Match
class RainbowMatch extends StatefulWidget {
  const RainbowMatch({super.key, required this.onReplay});
  final VoidCallback onReplay;
  @override
  State<RainbowMatch> createState() => _RainbowMatchState();
}

class _RainbowMatchState extends State<RainbowMatch> {
  static const _faces = ['🍎', '🍌', '🍇', '🥕', '🥦', '🍓'];
  final _random = Random();
  late List<int> _cards;
  final Set<int> _open = {};
  final Set<int> _matched = {};
  Timer? _hide;
  int _moves = 0;
  bool _locked = false;
  @override
  void initState() {
    super.initState();
    _shuffle();
  }

  void _shuffle() {
    _cards = List.generate(12, (i) => i % 6)..shuffle(_random);
  }

  void _tap(int i) {
    if (_locked || _matched.contains(i) || _open.contains(i)) return;
    setState(() {
      _open.add(i);
      if (_open.length == 2) {
        _moves++;
        final pair = _open.toList();
        if (_cards[pair[0]] == _cards[pair[1]]) {
          _matched.addAll(pair);
          _open.clear();
        } else {
          _locked = true;
          _hide = Timer(const Duration(milliseconds: 850), () {
            if (mounted) {
              setState(() {
                _open.clear();
                _locked = false;
              });
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final won = _matched.length == 12;
    return _gameBody(
      header: _stats([
        _stat('MOVES', '$_moves', const Color(0xFFE66F67)),
        _stat('PAIRS', '${_matched.length ~/ 2} / 6', const Color(0xFF66A878)),
      ]),
      child: Column(
        children: [
          if (!won) ...[
            const Text(
              'Tap two cards to find a pair',
              style: TextStyle(color: Color(0xFF65756E)),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.15,
              ),
              itemBuilder: (context, i) {
                final face = _open.contains(i) || _matched.contains(i);
                return Semantics(
                  key: ValueKey('memory-card-$i'),
                  button: true,
                  label: face ? 'Card ${_faces[_cards[i]]}' : 'Face down card',
                  child: InkWell(
                    onTap: () => _tap(i),
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: face ? Colors.white : const Color(0xFF315F56),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _matched.contains(i)
                              ? const Color(0xFF66A878)
                              : Colors.white,
                          width: _matched.contains(i) ? 3 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          face ? _faces[_cards[i]] : '✦',
                          style: TextStyle(
                            fontSize: face ? 34 : 27,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ] else
            _result(
              title: 'A perfect match!',
              detail: 'You found all 6 pairs in $_moves moves.',
              color: const Color(0xFFE66F67),
              replay: widget.onReplay,
            ),
        ],
      ),
    );
  }
}

// Garden Recall
class GardenRecall extends StatefulWidget {
  const GardenRecall({super.key, required this.onReplay});
  final VoidCallback onReplay;
  @override
  State<GardenRecall> createState() => _GardenRecallState();
}

class _GardenRecallState extends State<GardenRecall>
    with WidgetsBindingObserver {
  final _rng = Random();
  final List<int> _sequence = [];
  final List<int> _input = [];
  Timer? _timer;
  int _lit = -1;
  int _round = 0;
  bool _watching = true;
  bool _over = false;
  bool _paused = false;
  String _message = 'Watch the garden';
  static const _colors = [
    Color(0xFFE66F67),
    Color(0xFFE4A446),
    Color(0xFF4B9B91),
    Color(0xFF9A78C8),
  ];
  static const _icons = [
    Icons.local_florist,
    Icons.wb_sunny,
    Icons.eco,
    Icons.water_drop,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nextRound();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_over) {
      _timer?.cancel();
      setState(() {
        _paused = true;
        _lit = -1;
        _message = 'Paused when you left';
      });
    } else if (state == AppLifecycleState.resumed && _paused) {
      setState(() {
        _paused = false;
        _watching = true;
        _input.clear();
        _message = 'Watch the garden';
      });
      _playSequence();
    }
  }

  void _nextRound() {
    _sequence.add(_rng.nextInt(4));
    _round = _sequence.length;
    _input.clear();
    _watching = true;
    _message = 'Watch the garden';
    _playSequence();
  }

  void _playSequence() {
    var index = 0;
    final unit = max(380, 720 - (_round * 25));
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: unit), (t) {
      if (!mounted || _paused) {
        t.cancel();
        return;
      }
      setState(() {
        final pulse = index ~/ 2;
        _lit = index < _sequence.length * 2 && index.isEven
            ? _sequence[pulse]
            : -1;
        if (index >= _sequence.length * 2 + 1) {
          t.cancel();
          _watching = false;
          _lit = -1;
          _message = 'Your turn · Repeat the sequence';
        }
      });
      index++;
    });
  }

  void _tap(int i) {
    if (_watching || _over || _paused) return;
    setState(() {
      _lit = i;
      _input.add(i);
      if (_input.last != _sequence[_input.length - 1]) {
        _over = true;
        _message = 'That was close!';
        _lit = -1;
        return;
      }
      if (_input.length == _sequence.length) {
        _round = _sequence.length;
        _watching = true;
        _message = 'Lovely recall!';
        _lit = -1;
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 850), () {
          if (mounted && !_over && !_paused) setState(_nextRound);
        });
      } else {
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 260), () {
          if (mounted) setState(() => _lit = -1);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _gameBody(
    header: _stats([
      _stat('ROUND', '$_round', const Color(0xFF66A878)),
      _stat(
        'TILES',
        '${_input.length} / ${_sequence.length}',
        const Color(0xFF4B9B91),
      ),
    ]),
    child: Column(
      children: [
        if (!_over) ...[
          _status(_paused ? 'Paused' : _message, const Color(0xFF66A878)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
            ),
            itemBuilder: (context, i) => Semantics(
              button: true,
              label: 'Garden tile ${i + 1}',
              child: InkWell(
                onTap: () => _tap(i),
                borderRadius: BorderRadius.circular(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: _lit == i
                        ? _colors[i]
                        : _colors[i].withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _colors[i], width: 2),
                  ),
                  child: Icon(
                    _icons[i],
                    size: 43,
                    color: _lit == i ? Colors.white : _colors[i],
                  ),
                ),
              ),
            ),
          ),
        ] else
          _result(
            title: 'Your garden grew to round $_round',
            detail:
                'You completed $_round ${_round == 1 ? 'round' : 'rounds'}.',
            color: const Color(0xFF66A878),
            replay: widget.onReplay,
          ),
      ],
    ),
  );
}

// Hydration Dash
class _Falling {
  _Falling(this.x, this.y, this.drop, this.speed);
  double x, y, speed;
  final bool drop;
}

class HydrationDash extends StatefulWidget {
  const HydrationDash({super.key, required this.onReplay});
  final VoidCallback onReplay;
  @override
  State<HydrationDash> createState() => _HydrationDashState();
}

class _HydrationDashState extends State<HydrationDash>
    with WidgetsBindingObserver {
  final _rng = Random();
  final List<_Falling> _things = [];
  Timer? _loop;
  DateTime? _last;
  double _cup = .5;
  double _spawn = 0;
  double _elapsed = 0;
  int _score = 0;
  bool _paused = false;
  bool _over = false;
  bool _started = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _begin() {
    _started = true;
    _paused = false;
    _last = DateTime.now();
    _loop = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _started && !_over) {
      _loop?.cancel();
      setState(() => _paused = true);
    } else if (state == AppLifecycleState.resumed && _paused && _started) {
      setState(() => _paused = false);
      _last = DateTime.now();
      _loop = Timer.periodic(const Duration(milliseconds: 16), _tick);
    }
  }

  void _tick(Timer timer) {
    if (!mounted || _paused || _over) return;
    final now = DateTime.now();
    final dt = min(.05, now.difference(_last ?? now).inMicroseconds / 1000000);
    _last = now;
    setState(() {
      _elapsed += dt;
      _spawn += dt;
      if (_spawn > max(.28, .82 - _elapsed * .008)) {
        _spawn = 0;
        _things.add(
          _Falling(
            _rng.nextDouble() * .88 + .06,
            -.05,
            _rng.nextBool(),
            .42 + min(.65, _elapsed * .009) + _rng.nextDouble() * .18,
          ),
        );
      }
      for (final object in _things) {
        object.y += object.speed * dt;
        if ((object.y - .84).abs() < .07 && (object.x - _cup).abs() < .12) {
          object.y = 2;
          _score = max(0, _score + (object.drop ? 1 : -1));
        }
      }
      _things.removeWhere((o) => o.y > 1.12 || o.y == 2);
      if (_elapsed >= 45) {
        _over = true;
        _loop?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _loop?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = max(0, 45 - _elapsed).ceil();
    return _gameBody(
      header: _stats([
        _stat('TIME', '${left}s', const Color(0xFF4B9EC5)),
        _stat('SCORE', '$_score', const Color(0xFF4B9EC5)),
      ]),
      child: Column(
        children: [
          if (!_over) ...[
            if (!_started)
              _status('Catch drops · Dodge leaves', const Color(0xFF4B9EC5))
            else if (_paused)
              _status(
                'Paused · Tap resume when ready',
                const Color(0xFF4B9EC5),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 350,
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  final h = box.maxHeight;
                  return GestureDetector(
                    onHorizontalDragUpdate: (d) => setState(
                      () => _cup = (_cup + d.delta.dx / w).clamp(.06, .94),
                    ),
                    child: Container(
                      width: w,
                      height: h,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4F7),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFC4E3EA)),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 14,
                            top: 12,
                            child: Text('🌤️', style: TextStyle(fontSize: 25)),
                          ),
                          ..._things.map(
                            (o) => Positioned(
                              left: (o.x * w - 16).clamp(0, w - 32),
                              top: (o.y * h).clamp(-10, h - 25),
                              child: Text(
                                o.drop ? '💧' : '🍃',
                                style: const TextStyle(fontSize: 27),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (_cup * w - 32).clamp(0, w - 64),
                            bottom: 16,
                            child: const Text(
                              '🥤',
                              style: TextStyle(fontSize: 48),
                            ),
                          ),
                          if (_started && !_paused)
                            Positioned(
                              right: 8,
                              top: 6,
                              child: IconButton.filledTonal(
                                tooltip: 'Pause game',
                                onPressed: () {
                                  _loop?.cancel();
                                  setState(() => _paused = true);
                                },
                                icon: const Icon(Icons.pause_rounded),
                              ),
                            ),
                          if (!_started || _paused)
                            Center(
                              child: FilledButton.icon(
                                onPressed: () {
                                  if (!_started) {
                                    _begin();
                                  } else {
                                    setState(() {
                                      _paused = false;
                                      _last = DateTime.now();
                                    });
                                    _loop = Timer.periodic(
                                      const Duration(milliseconds: 16),
                                      _tick,
                                    );
                                  }
                                },
                                icon: Icon(
                                  _started
                                      ? Icons.play_arrow
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(
                                  _started ? 'Resume' : 'Start round',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF4B9EC5),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: FilledButton.tonalIcon(
                      onPressed: _started && !_paused
                          ? () => setState(() => _cup = max(.06, _cup - .14))
                          : null,
                      icon: const Icon(Icons.arrow_left_rounded, size: 30),
                      label: const Text('Left'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: FilledButton.tonalIcon(
                      onPressed: _started && !_paused
                          ? () => setState(() => _cup = min(.94, _cup + .14))
                          : null,
                      icon: const Icon(Icons.arrow_right_rounded, size: 30),
                      label: const Text('Right'),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            _result(
              title: 'Dash complete!',
              detail:
                  'You caught $_score ${_score == 1 ? 'drop' : 'drops'} worth of points.',
              color: const Color(0xFF4B9EC5),
              replay: widget.onReplay,
            ),
        ],
      ),
    );
  }
}

// Focus Flow
class FocusFlow extends StatefulWidget {
  const FocusFlow({super.key, required this.onReplay});
  final VoidCallback onReplay;
  @override
  State<FocusFlow> createState() => _FocusFlowState();
}

class _FocusFlowState extends State<FocusFlow> with WidgetsBindingObserver {
  final _rng = Random();
  Timer? _timer;
  double _angle = 0;
  double _target = 1.2;
  double _speed = 1.8;
  int _attempts = 0;
  int _score = 0;
  int _streak = 0;
  String _feedback = 'Tap when the dot enters the arc';
  bool _paused = false;
  bool _started = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _start() {
    _started = true;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (!mounted || _paused) return;
      setState(() => _angle = (_angle + _speed * .016) % (pi * 2));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _started && !_done) {
      _timer?.cancel();
      setState(() => _paused = true);
    } else if (state == AppLifecycleState.resumed &&
        _paused &&
        _started &&
        !_done) {
      setState(() => _paused = false);
      _timer = Timer.periodic(const Duration(milliseconds: 16), (t) {
        if (!mounted || _paused) return;
        setState(() => _angle = (_angle + _speed * .016) % (pi * 2));
      });
    }
  }

  bool get _done => _attempts >= 10;
  double _distance(double a, double b) =>
      ((a - b + pi * 3) % (pi * 2) - pi).abs();
  void _hit() {
    if (!_started) {
      _start();
      return;
    }
    if (_paused || _done) return;
    final good = _distance(_angle, _target) < .48;
    setState(() {
      _attempts++;
      if (good) {
        _streak++;
        _score += 10 + max(0, _streak - 1) * 2;
        _feedback = _streak > 1
            ? 'Lovely timing · $_streak in a row!'
            : 'Right on cue! +10';
      } else {
        _streak = 0;
        _feedback = 'Missed that one · Keep flowing';
      }
      _target = _rng.nextDouble() * pi * 2;
      _speed = min(3.4, _speed + .12);
    });
    if (_done) _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _gameBody(
    header: _stats([
      _stat('ATTEMPTS', '${min(_attempts, 10)} / 10', const Color(0xFF9A78C8)),
      _stat('SCORE', '$_score', const Color(0xFF9A78C8)),
    ]),
    child: Column(
      children: [
        _done
            ? _result(
                title: 'Flow complete',
                detail: 'You scored $_score points over ten attempts.',
                color: const Color(0xFF9A78C8),
                replay: widget.onReplay,
              )
            : Column(
                children: [
                  _status(
                    _paused ? 'Paused' : _feedback,
                    const Color(0xFF9A78C8),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 270,
                    height: 270,
                    child: CustomPaint(
                      painter: _OrbitPainter(
                        angle: _angle,
                        target: _target,
                        active: _started && !_paused,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 62,
                    child: FilledButton(
                      onPressed: _paused ? null : _hit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF9A78C8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        !_started
                            ? 'Start · then tap in the arc'
                            : _paused
                            ? 'Paused'
                            : 'Tap now',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Target arc is marked in lavender',
                    style: TextStyle(color: Color(0xFF75827C), fontSize: 12),
                  ),
                  if (_started)
                    TextButton.icon(
                      onPressed: () {
                        if (_paused) {
                          setState(() => _paused = false);
                          _timer = Timer.periodic(
                            const Duration(milliseconds: 16),
                            (t) {
                              if (!mounted || _paused || _done) {
                                t.cancel();
                                return;
                              }
                              setState(
                                () => _angle =
                                    (_angle + _speed * .016) % (pi * 2),
                              );
                            },
                          );
                        } else {
                          _timer?.cancel();
                          setState(() => _paused = true);
                        }
                      },
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      label: Text(_paused ? 'Resume' : 'Pause'),
                    ),
                ],
              ),
      ],
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.angle,
    required this.target,
    required this.active,
  });
  final double angle, target;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * .38;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFFE8E2F2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      target - .48,
      .96,
      false,
      Paint()
        ..color = const Color(0xFFBCA4DC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 5, Paint()..color = const Color(0xFF9A78C8));
    final p = Offset(c.dx + cos(angle) * r, c.dy + sin(angle) * r);
    canvas.drawCircle(
      p,
      14,
      Paint()
        ..color = active ? const Color(0xFF58417D) : const Color(0xFFBBA9CE),
    );
    canvas.drawCircle(p, 6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.angle != angle || old.target != target || old.active != active;
}

// Market Sort
class _MarketItem {
  const _MarketItem(this.name, this.emoji, this.category);
  final String name, emoji, category;
}

const _market = [
  _MarketItem('Apple', '🍎', 'Fruit'),
  _MarketItem('Pear', '🍐', 'Fruit'),
  _MarketItem('Blueberry', '🫐', 'Fruit'),
  _MarketItem('Mango', '🥭', 'Fruit'),
  _MarketItem('Carrot', '🥕', 'Vegetable'),
  _MarketItem('Broccoli', '🥦', 'Vegetable'),
  _MarketItem('Spinach', '🥬', 'Vegetable'),
  _MarketItem('Pepper', '🫑', 'Vegetable'),
  _MarketItem('Oats', '🌾', 'Grain'),
  _MarketItem('Rice', '🍚', 'Grain'),
  _MarketItem('Quinoa', '🌱', 'Grain'),
  _MarketItem('Barley', '🌾', 'Grain'),
];

class MarketSort extends StatefulWidget {
  const MarketSort({super.key, required this.onReplay});
  final VoidCallback onReplay;
  @override
  State<MarketSort> createState() => _MarketSortState();
}

class _MarketSortState extends State<MarketSort> {
  final _rng = Random();
  late List<_MarketItem> _items;
  int _index = 0, _score = 0, _streak = 0, _correct = 0;
  String? _feedback;
  bool _answered = false;
  @override
  void initState() {
    super.initState();
    _items = List.of(_market)..shuffle(_rng);
  }

  void _choose(String category) {
    if (_answered) return;
    final item = _items[_index];
    final ok = category == item.category;
    setState(() {
      _answered = true;
      if (ok) {
        _correct++;
        _streak++;
        _score += 10 + max(0, _streak - 1) * 2;
        _feedback = 'That’s right! +${10 + max(0, _streak - 1) * 2}';
      } else {
        _streak = 0;
        _feedback = '${item.name} belongs in ${item.category.toLowerCase()}.';
      }
    });
  }

  void _next() {
    setState(() {
      _index++;
      _answered = false;
      _feedback = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _index >= _items.length;
    final item = done ? null : _items[_index];
    return _gameBody(
      header: _stats([
        _stat(
          'ITEM',
          done ? '12 / 12' : '${_index + 1} / 12',
          const Color(0xFFE4A446),
        ),
        _stat('SCORE', '$_score', const Color(0xFFE4A446)),
        _stat('STREAK', '$_streak', const Color(0xFF66A878)),
      ]),
      child: done
          ? _result(
              title: 'Market sorted!',
              detail: '$_correct of 12 correct · $_score points',
              color: const Color(0xFFE4A446),
              replay: widget.onReplay,
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 28,
                    horizontal: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Text(item!.emoji, style: const TextStyle(fontSize: 68)),
                      const SizedBox(height: 10),
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Which basket does it belong in?',
                        style: TextStyle(color: Color(0xFF65756E)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final choice in ['Fruit', 'Vegetable', 'Grain'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.tonalIcon(
                        onPressed: _answered ? null : () => _choose(choice),
                        icon: Icon(
                          choice == 'Fruit'
                              ? Icons.apple
                              : choice == 'Vegetable'
                              ? Icons.eco
                              : Icons.grain,
                        ),
                        label: Text(
                          choice,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF4E1),
                          foregroundColor: _ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_feedback != null) ...[
                  _status(
                    _feedback!,
                    _feedback!.startsWith('That')
                        ? const Color(0xFF66A878)
                        : const Color(0xFFE08D48),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE4A446),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_index == 11 ? 'See results' : 'Next item'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

// Trail Tiles
class TrailTiles extends StatefulWidget {
  const TrailTiles({super.key, required this.onReplay});
  final VoidCallback onReplay;
  @override
  State<TrailTiles> createState() => _TrailTilesState();
}

class _TrailTilesState extends State<TrailTiles> {
  final _rng = Random();
  late List<int> _board;
  int _moves = 0;
  bool _won = false;
  @override
  void initState() {
    super.initState();
    _newBoard();
  }

  void _newBoard() {
    _board = List.generate(9, (i) => i + 1);
    _board[8] = 0;
    var blank = 8;
    for (var step = 0; step < 80; step++) {
      final options = <int>[];
      final row = blank ~/ 3, col = blank % 3;
      if (row > 0) options.add(blank - 3);
      if (row < 2) options.add(blank + 3);
      if (col > 0) options.add(blank - 1);
      if (col < 2) options.add(blank + 1);
      final next = options[_rng.nextInt(options.length)];
      _board[blank] = _board[next];
      _board[next] = 0;
      blank = next;
    }
    if (_solved) _newBoard();
    _moves = 0;
    _won = false;
  }

  bool get _solved => List.generate(
    9,
    (i) => i == 8 ? 0 : i + 1,
  ).asMap().entries.every((e) => _board[e.key] == e.value);
  void _move(int i) {
    if (_won) return;
    final blank = _board.indexOf(0);
    if ((i ~/ 3 - blank ~/ 3).abs() + (i % 3 - blank % 3).abs() != 1) return;
    setState(() {
      _board[blank] = _board[i];
      _board[i] = 0;
      _moves++;
      _won = _solved;
    });
  }

  void _reset() => setState(_newBoard);
  @override
  Widget build(BuildContext context) => _gameBody(
    header: _stats([
      _stat('MOVES', '$_moves', const Color(0xFF4B9B91)),
      _stat('GOAL', '1 → 8', const Color(0xFF4B9B91)),
    ]),
    child: Column(
      children: [
        if (!_won) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE4F0EB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.landscape, color: Color(0xFF4B9B91)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Goal: arrange the landscape',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: const [
                    Text(
                      '1  2  3',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    Text(
                      '4  5  6',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    Text(
                      '7  8  ·',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 9,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, i) {
                final n = _board[i];
                final colors = [
                  const Color(0xFF72AFA1),
                  const Color(0xFF85B7A0),
                  const Color(0xFF9FC6A3),
                  const Color(0xFF6DA5A0),
                  const Color(0xFF79B0A1),
                  const Color(0xFF95BE9C),
                  const Color(0xFF5F9A91),
                  const Color(0xFF79AA91),
                ];
                return Semantics(
                  key: ValueKey('trail-tile-$i'),
                  button: n != 0,
                  label: n == 0 ? 'Empty space' : 'Tile $n',
                  child: InkWell(
                    onTap: () => _move(i),
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: n == 0
                            ? const Color(0xFFE7EEE9)
                            : colors[(n - 1) % colors.length],
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: n == 0
                            ? []
                            : [
                                BoxShadow(
                                  color: colors[(n - 1) % colors.length]
                                      .withValues(alpha: .25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: n == 0
                          ? const Icon(
                              Icons.auto_awesome,
                              color: Color(0xFFB4C6BC),
                            )
                          : Stack(
                              children: [
                                Positioned(
                                  top: 8,
                                  left: 9,
                                  child: Text(
                                    '$n',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Icon(
                                    [
                                      Icons.park,
                                      Icons.wb_sunny,
                                      Icons.terrain,
                                      Icons.water,
                                      Icons.forest,
                                      Icons.cloud,
                                      Icons.landscape,
                                      Icons.nature,
                                    ][n - 1],
                                    color: Colors.white.withValues(alpha: .85),
                                    size: 27,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('New puzzle'),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tap a tile beside the sparkle to slide it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF65756E), fontSize: 12),
                ),
              ),
            ],
          ),
        ] else
          _result(
            title: 'Trail complete!',
            detail: 'Solved in $_moves moves. The landscape is back in order.',
            color: const Color(0xFF4B9B91),
            replay: widget.onReplay,
            button: 'New puzzle',
          ),
      ],
    ),
  );
}
