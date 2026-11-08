import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pantry_news_controller.dart';

/// The breaking-news banner over the Home tab. Slides in when the
/// controller announces news; the X button dismisses it.
class PantryNewsCard extends StatefulWidget {
  const PantryNewsCard({super.key, required this.controller});

  final PantryNewsController controller;

  @override
  State<PantryNewsCard> createState() => _PantryNewsCardState();
}

class _PantryNewsCardState extends State<PantryNewsCard> {
  /// Drives the slide-in: flipped once the card is on screen so the first
  /// build starts off-screen and animates in.
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // The card can also be mounted before the controller delivers (e.g. in
    // widget tests); listen so a late announcement still slides it in.
    widget.controller.addListener(_onNews);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.announcedNews != null) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void didUpdateWidget(PantryNewsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onNews);
      widget.controller.addListener(_onNews);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onNews);
    super.dispose();
  }

  /// Slides the card in when news arrives while it is mounted, and slides
  /// it back out when the controller's news is cleared (dismiss).
  void _onNews() {
    if (!mounted) return;
    final has = widget.controller.announcedNews != null;
    if (has == _visible) return;
    if (has) {
      // Next frame so the slide starts from the off-screen offset.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.announcedNews != null) {
          setState(() => _visible = true);
        }
      });
    } else {
      setState(() => _visible = false);
    }
  }

  void _showSources(BuildContext context, List<String> sources) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('News sources'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final source in sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InkWell(
                  onTap: () => _launch(dialogContext, source),
                  child: Text(
                    '• $source',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens [url] in the browser, reporting failures through a snackbar.
  Future<void> _launch(BuildContext dialogContext, String url) async {
    final uri = Uri.tryParse(url);
    try {
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('launchUrl returned false');
      }
    } on Exception catch (e) {
      debugPrint('Could not open $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.controller.announcedNews;
    final food = widget.controller.announcedFood;
    final theme = Theme.of(context);
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, -1.2),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Breaking news: $food',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'News sources',
                        icon: const Icon(Icons.info_outline),
                        onPressed: item == null
                            ? null
                            : () => _showSources(context, item.sources),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        icon: const Icon(Icons.close),
                        onPressed: widget.controller.dismiss,
                      ),
                    ],
                  ),
                  if (item != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Local news: ${item.news}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (widget.controller.announcedAlternatives.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    // From FoodRecommendationService.recommend, as on the
                    // scan result sheet.
                    Text('Try instead:', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final alt
                            in widget.controller.announcedAlternatives)
                          Chip(label: Text(alt)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
