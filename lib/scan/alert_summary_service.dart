import 'dart:convert';

import 'package:hackathon/openrouter.dart' show OpenRouterService;
import 'package:hackathon/secrets.dart' show openRouterApiKey;

/// The JSON shape for [AlertSummaryService.summarize], enforced by
/// OpenRouter's strict structured-output mode.
const alertSummarySchema = {
  'type': 'object',
  'properties': {
    'summary': {
      'type': 'string',
      'description':
          'A single concise sentence summarising the news, at most 12 words. '
          'No quotes, no trailing full stop.',
    },
  },
  'required': ['summary'],
  'additionalProperties': false,
};

/// Summarises stored food-news and recommendation explanations into one
/// short sentence for the scan-result alert cards.
///
/// The stored `local_news` / `general_info` texts are web-search generated
/// and can run long; the alert cards show one summary line instead. Falls
/// back to a plain truncation when the AI call fails or no API key is set,
/// so alerts never go blank.
class AlertSummaryService {
  AlertSummaryService({OpenRouterService? ai}) : _ai = ai ?? _defaultAi();

  static OpenRouterService? _defaultAi() =>
      openRouterApiKey.trim().isEmpty ? null : OpenRouterService();

  final OpenRouterService? _ai;

  /// One sentence summarising [text], at most [maxWords] words.
  ///
  /// Fires one OpenRouter call per text; results are not cached here.
  Future<String> summarize(String text, {int maxWords = 12}) async {
    final ai = _ai;
    if (text.trim().isEmpty) return '';
    if (ai == null) return _truncate(text, maxWords);
    try {
      final raw = await ai.generate(
        prompt:
            'Summarise this food-safety note in one sentence of at most '
            '$maxWords words, keeping the key fact (e.g. what happened, or '
            'why to limit the food). Reply with JSON.\n\n$text',
        responseSchema: alertSummarySchema,
      );
      final summary = (jsonDecode(raw)['summary'] as String?)?.trim() ?? '';
      return summary.isEmpty ? _truncate(text, maxWords) : summary;
    } catch (_) {
      return _truncate(text, maxWords);
    }
  }

  /// Crude offline fallback: first sentence, hard-capped.
  String _truncate(String text, int maxWords) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final firstSentence = RegExp(r'^.*?[.!?]').firstMatch(trimmed)?.end;
    final sentence = trimmed.substring(0, firstSentence ?? trimmed.length);
    final words = sentence.split(' ');
    return words.length <= maxWords
        ? sentence
        : '${words.take(maxWords).join(' ')}…';
  }
}
