import 'package:flutter/material.dart';

/// Selectable theme colours from the Figma "Appearance & themes" screen.
/// Each accent drives buttons, the scan FAB, charts and selected states;
/// everything else stays neutral.
enum ThemeAccent {
  freshGreen('Fresh green', Color(0xFF13A35A)),
  ocean('Ocean', Color(0xFF2F6FED)),
  berry('Berry', Color(0xFF8E3FD8)),
  mint('Mint', Color(0xFF14B8A6)),
  rose('Rose', Color(0xFFE11D74)),
  lemon('Lemon', Color(0xFFEAB308)),
  slate('Slate', Color(0xFF475569)),
  midnight('Midnight', Color(0xFF111827));

  const ThemeAccent(this.label, this.color);

  final String label;
  final Color color;
}

/// App-wide Material 3 theme generated from the accent picked in
/// [ThemeAccent]: every surface, container and outline carries a subtle tint
/// of the accent, in both light and dark.
///
/// All widgets should pull colors from `Theme.of(context).colorScheme` so
/// light, dark and every accent stay consistent. Semantic statuses
/// (pass/fail, score bands) live in [statusColors] so success/danger never
/// fight the brand palette.
abstract final class AppTheme {
  /// Default accent — vivid green.
  static const Color seed = Color(0xFF13A35A);

  /// Readable foreground for text/icons drawn on [background].
  static Color _on(Color background) => background.computeLuminance() > 0.4
      ? const Color(0xFF1A1A12)
      : Colors.white;

  /// Light theme — buttons use the exact Figma accent; pages sit on a
  /// lightly tinted canvas with near-white cards.
  static ThemeData light([ThemeAccent accent = ThemeAccent.freshGreen]) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent.color,
      primary: accent.color,
      onPrimary: _on(accent.color),
    );
    return _base(
      scheme,
      canvas: scheme.surfaceContainerLow,
      card: scheme.surfaceContainerLowest,
    );
  }

  /// Dark theme — tonal palette from the same seed, so the accent is lifted
  /// to a readable tone and the dark surfaces share its hue.
  static ThemeData dark([ThemeAccent accent = ThemeAccent.freshGreen]) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent.color,
      brightness: Brightness.dark,
    );
    return _base(scheme, canvas: scheme.surface, card: scheme.surfaceContainer);
  }

  static ThemeData _base(
    ColorScheme scheme, {
    required Color canvas,
    required Color card,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        indicatorColor: scheme.primaryContainer,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }

  /// Semantic status colors that sit outside the brand palette: green means
  /// good, amber caution, red problem — used for score badges and verdicts.
  static const statusColors = (
    good: seed,
    warn: Color(0xFFD9A72C),
    bad: Color(0xFFC4453C),
  );
}
