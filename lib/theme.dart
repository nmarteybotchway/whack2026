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

/// App-wide theme: a minimal, white-first look with a single accent colour
/// picked from [ThemeAccent]. The blue/purple from the Figma palette survive
/// as quiet tints for info chips.
///
/// All widgets should pull colors from `Theme.of(context).colorScheme` so
/// light, dark and every accent stay consistent. Semantic statuses
/// (pass/fail, score bands) live in [statusColors] so success/danger never
/// fight the brand palette.
abstract final class AppTheme {
  /// Default accent — vivid green.
  static const Color seed = Color(0xFF13A35A);

  /// Blue — quiet accent for info chips.
  static const Color blue = Color(0xFF2868E8);

  /// Purple — quiet accent, sparing use.
  static const Color purple = Color(0xFF6858E8);

  static const _lightCanvas = Color(0xFFF5F7F4);
  static const _darkCanvas = Color(0xFF141614);
  static const _darkSurface = Color(0xFF1C1F1D);

  /// Readable foreground for text/icons drawn on [background].
  static Color _on(Color background) => background.computeLuminance() > 0.4
      ? const Color(0xFF1A1A12)
      : Colors.white;

  static ThemeData light([ThemeAccent accent = ThemeAccent.freshGreen]) {
    final primary = accent.color;
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: _on(primary),
      primaryContainer: Color.lerp(Colors.white, primary, 0.12)!,
      onPrimaryContainer: Color.lerp(primary, Colors.black, 0.6)!,
      secondary: blue,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFEEF3FC),
      onSecondaryContainer: const Color(0xFF1E3A6E),
      tertiary: purple,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFF1EFFB),
      onTertiaryContainer: const Color(0xFF37306E),
      error: const Color(0xFFC4453C),
      onError: Colors.white,
      errorContainer: const Color(0xFFFDEEEC),
      onErrorContainer: const Color(0xFF7A221B),
      surface: Colors.white,
      onSurface: const Color(0xFF191C1A),
      surfaceContainerHighest: const Color(0xFFF2F3F2),
      onSurfaceVariant: const Color(0xFF74796F),
      outline: const Color(0xFFDFE2DE),
      outlineVariant: const Color(0xFFEDEFEA),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: _lightCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightCanvas,
        foregroundColor: Color(0xFF191C1A),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
    );
  }

  /// Dark theme — neutral charcoal with the accent lifted towards white so
  /// it keeps contrast (very dark accents like Midnight are lifted further).
  static ThemeData dark([ThemeAccent accent = ThemeAccent.freshGreen]) {
    final base = accent.color;
    final lift = base.computeLuminance() < 0.1 ? 0.65 : 0.25;
    final primary = Color.lerp(base, Colors.white, lift)!;
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: _on(primary),
      primaryContainer: Color.lerp(_darkSurface, primary, 0.3)!,
      onPrimaryContainer: Color.lerp(primary, Colors.white, 0.75)!,
      secondary: const Color(0xFF9DBCF5),
      onSecondary: const Color(0xFF12233F),
      secondaryContainer: const Color(0xFF24344F),
      onSecondaryContainer: const Color(0xFFDCE7FA),
      tertiary: const Color(0xFFB7AFF2),
      onTertiary: const Color(0xFF221E45),
      tertiaryContainer: const Color(0xFF37325C),
      onTertiaryContainer: const Color(0xFFE6E2F8),
      error: const Color(0xFFE57368),
      onError: const Color(0xFF4A0E08),
      errorContainer: const Color(0xFF7A221B),
      onErrorContainer: const Color(0xFFFDE7E4),
      surface: _darkSurface,
      onSurface: const Color(0xFFE2E3E0),
      surfaceContainerHighest: const Color(0xFF282B29),
      onSurfaceVariant: const Color(0xFF9FA39B),
      outline: const Color(0xFF434643),
      outlineVariant: const Color(0xFF2D302E),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: _darkCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkCanvas,
        foregroundColor: Color(0xFFE2E3E0),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
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
