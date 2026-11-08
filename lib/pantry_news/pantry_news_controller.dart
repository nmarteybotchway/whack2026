import 'dart:async';

import 'package:flutter/foundation.dart';

import '../food/food_recommendation_service.dart';
import 'demo_news.dart';
import 'os_notifier.dart';

/// Fires the hardcoded pantry news on a delay after startup, runs it
/// through the recommendation service, and tracks what has been announced
/// this session (for the History "flagged" list).
class PantryNewsController extends ChangeNotifier {
  PantryNewsController({OsNotifier? notifier, Duration? delay})
    : notifier = notifier ?? OsNotifier(),
      delay = delay ?? pantryNewsDelay;

  final OsNotifier notifier;
  final Duration delay;

  /// Foods announced this session, newest first (drives the History card).
  final List<String> flagged = [];

  bool _started = false;

  /// "Unless disabled": a dismiss cancels the pending delivery and keeps
  /// later ones off for the rest of the session.
  bool _cancelled = false;
  Timer? _timer;

  /// Announced item, its news, and the recommendation-service alternatives;
  /// null when the banner is hidden.
  String? announcedFood;
  PantryNewsItem? announcedNews;
  List<String> announcedAlternatives = const [];

  /// Called once from HomePage's post-frame callback.
  void start() {
    if (_started || !pantryNewsEnabled) return;
    _started = true;
    _timer = Timer(delay, _deliver);
  }

  Future<void> _deliver() async {
    if (_cancelled) return;
    final entry = demoPantryNews.entries.first; // one demo item today
    // Hardcoded reuse of the recommender: the same pure decide() the scan
    // sheet relies on, fed the hardcoded Food and an empty profile.
    final verdict = FoodRecommendationService.recommend(entry.value.food);
    flagged.insert(0, entry.key);
    announcedFood = entry.key;
    announcedNews = entry.value;
    announcedAlternatives = verdict.alternatives;
    notifyListeners();
    await notifier.show(
      title: 'Breaking news: ${entry.key}',
      body: entry.value.news,
    );
  }

  /// Dismisses the banner and cancels a pending notification.
  void dismiss() {
    _cancelled = true;
    _timer?.cancel();
    announcedFood = null;
    announcedNews = null;
    announcedAlternatives = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
