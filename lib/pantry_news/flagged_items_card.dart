import 'package:flutter/material.dart';

import 'demo_news.dart';
import 'pantry_news_controller.dart';

/// History-tab section listing foods the pantry tracker flagged this
/// session, shown between the AI diet review and the receipt purchases.
class FlaggedItemsCard extends StatelessWidget {
  const FlaggedItemsCard({super.key, required this.controller});

  final PantryNewsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.flagged.isEmpty) return const SizedBox.shrink();
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.flag),
            title: Text('Flagged items', style: theme.textTheme.titleMedium),
            subtitle: Text(
              '${controller.flagged.length} flagged after purchase',
            ),
            children: [
              for (final food in controller.flagged)
                ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(food),
                  subtitle: Text(
                    '${demoPantryNews[food]!.news}\n'
                    'Try instead: '
                    '${controller.announcedAlternatives.join(', ')}',
                  ),
                  isThreeLine: true,
                ),
            ],
          ),
        );
      },
    );
  }
}
