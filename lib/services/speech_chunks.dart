/// Small opening phrase lets local synthesis produce playable audio sooner.
/// Subsequent chunks are longer to retain natural phrasing and throughput.
List<String> speechChunks(String text) {
  final chunks = <String>[];
  var words = <String>[];
  var length = 0;
  for (final word in text.trim().split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final limit = chunks.isEmpty ? 80 : 180;
    if (words.isNotEmpty && length + word.length + 1 > limit) {
      chunks.add(words.join(' '));
      words = [];
      length = 0;
    }
    words.add(word);
    length += word.length + 1;
    if (RegExp(r'[.!?;:]$').hasMatch(word) ||
        (chunks.isEmpty && length >= 30 && word.endsWith(','))) {
      chunks.add(words.join(' '));
      words = [];
      length = 0;
    }
  }
  if (words.isNotEmpty) chunks.add(words.join(' '));
  return chunks;
}
