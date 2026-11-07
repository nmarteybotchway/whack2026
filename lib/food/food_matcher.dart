import 'known_foods.g.dart';

/// Words that never identify a food on their own.
const _stopWords = {'and', 'the', 'of', 'with', 'in', 'a'};

/// Lowercase word tokens of [text], crudely singularised so "Apples" and
/// "apple" match.
List<String> _tokens(String text) => [
  for (final t in text.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
    if (t.isNotEmpty && !_stopWords.contains(t)) _singular(t),
];

String _singular(String t) {
  if (t.length > 4 && t.endsWith('ies')) {
    return '${t.substring(0, t.length - 3)}y';
  }
  if (t.length > 3 && t.endsWith('s') && !t.endsWith('ss')) {
    return t.substring(0, t.length - 1);
  }
  return t;
}

/// [scanned] matches [food] exactly, or abbreviates it ("veg" in "vegetable").
bool _tokenMatches(String food, Iterable<String> scanned) =>
    scanned.any((s) => s == food || (food.length >= 3 && s.startsWith(food)));

/// Indexes of [food]'s words found in [scanned]: each word on its own, or a
/// run of them written as one word ("redbull" for "Red Bull").
Set<int> _hits(List<String> food, Set<String> scanned) => {
  for (var i = 0; i < food.length; i++)
    if (_tokenMatches(food[i], scanned)) i,
  for (var i = 0; i < food.length; i++)
    for (var j = i + 2; j <= food.length; j++)
      if (_tokenMatches(food.sublist(i, j).join(), scanned))
        for (var k = i; k < j; k++) k,
};

/// The known food a scanned product name refers to, or null when none fits.
///
/// Catalogue names like "Tesco Granny Smith Apples 6 Pack" rarely equal a
/// stored food name, so this scores each [KnownFood] by the share of its
/// name's words found in [scannedName], also when run together ("redbull").
/// Text in brackets ("Bread (Toast)") is optional, and the last word, the
/// food's head noun, must be present so "Red Bull" does not match on "red"
/// alone. Of foods with at least half their words present, the one with the
/// most matching words wins, so "Fruit Shoot Apple" is a Fruit Shoot rather
/// than apples; ties go to the higher share.
KnownFood? matchKnownFood(String scannedName) {
  final scanned = _tokens(scannedName).toSet();
  if (scanned.isEmpty) return null;
  KnownFood? best;
  var bestHits = 0;
  var bestScore = 0.0;
  for (final known in KnownFood.values) {
    final required = _tokens(
      known.food.name.replaceAll(RegExp(r'\([^)]*\)'), ' '),
    );
    if (required.isEmpty) continue;
    final hitIndexes = _hits(required, scanned);
    if (!hitIndexes.contains(required.length - 1)) continue;
    final hits = hitIndexes.length;
    final score = hits / required.length;
    if (score < 0.5) continue;
    if (hits > bestHits || (hits == bestHits && score > bestScore)) {
      best = known;
      bestHits = hits;
      bestScore = score;
    }
  }
  return best;
}
