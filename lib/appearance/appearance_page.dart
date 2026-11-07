import 'package:flutter/material.dart';

import '../theme.dart';
import 'appearance_controller.dart';

/// Light/dark/auto override and accent colour picker.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mode', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dark'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.contrast),
                          label: Text('Auto'),
                        ),
                      ],
                      selected: {appearance.mode},
                      onSelectionChanged: (s) => appearance.setMode(s.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme colour', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Changes buttons, charts and highlights.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [
                      for (final accent in ThemeAccent.values)
                        _Swatch(
                          label: accent.label,
                          color: accent.color,
                          selected: accent == appearance.accent,
                          onTap: () => appearance.setAccent(accent),
                        ),
                      const _Swatch(
                        label: 'Orange',
                        color: Color(0xFFF7BC90),
                        locked: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Orange is off the menu. Every other colour is '
                            'fair game.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.color,
    this.selected = false,
    this.locked = false,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: locked ? null : onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color,
              child: selected
                  ? Icon(Icons.check, color: _onColor(color))
                  : locked
                  ? const Icon(Icons.lock_outline, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                decoration: locked ? TextDecoration.lineThrough : null,
                color: locked ? scheme.onSurfaceVariant : null,
              ),
            ),
            if (locked)
              Text(
                'Not available',
                style: textTheme.labelSmall?.copyWith(color: scheme.error),
              ),
          ],
        ),
      ),
    );
  }

  static Color _onColor(Color c) =>
      c.computeLuminance() > 0.4 ? Colors.black87 : Colors.white;
}
