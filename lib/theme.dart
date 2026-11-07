import 'package:flutter/material.dart';

/// App-wide theme: a minimal, white-first look with a single green accent.
/// Almost everything is white or neutral gray — buttons, the scan FAB and
/// selected states are the only saturated green, and the blue/purple from
/// the Figma palette survive as quiet tints for info chips.
///
/// All widgets should pull colors from `Theme.of(context).colorScheme` so
/// light and dark stay consistent. Semantic statuses (pass/fail, score
/// bands) live in [statusColors] so success/danger never fight the brand
/// palette.
abstract final class AppTheme {
  /// Vivid green — the single accent: buttons, FABs, selected states.
  static const Color seed = Color(0xFF12A058);

  /// Blue — quiet accent for info chips.
  static const Color blue = Color(0xFF2868E8);

  /// Purple — quiet accent, sparing use.
  static const Color purple = Color(0xFF6858E8);

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: seed,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEAF6F0),
      onPrimaryContainer: Color(0xFF0B3B29),
      secondary: blue,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEEF3FC),
      onSecondaryContainer: Color(0xFF1E3A6E),
      tertiary: purple,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFF1EFFB),
      onTertiaryContainer: Color(0xFF37306E),
      error: Color(0xFFC4453C),
      onError: Colors.white,
      errorContainer: Color(0xFFFDEEEC),
      onErrorContainer: Color(0xFF7A221B),
      surface: Colors.white,
      onSurface: Color(0xFF191C1A),
      surfaceContainerHighest: Color(0xFFF2F3F2),
      onSurfaceVariant: Color(0xFF74796F),
      outline: Color(0xFFDFE2DE),
      outlineVariant: Color(0xFFEDEFEA),
    );
    return _base(scheme).copyWith(
      // A very light green-white canvas so pages don't read stark white.
      scaffoldBackgroundColor: const Color(0xFFF7FBF8),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7FBF8),
        foregroundColor: Color(0xFF191C1A),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
    );
  }

  /// Dark theme — neutral charcoal rather than green-black, so it reads
  /// softer than the previous near-black green.
  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF5BC98D),
      onPrimary: Color(0xFF00391D),
      primaryContainer: Color(0xFF173B2B),
      onPrimaryContainer: Color(0xFFC8ECD9),
      secondary: Color(0xFF9DBCF5),
      onSecondary: Color(0xFF12233F),
      secondaryContainer: Color(0xFF24344F),
      onSecondaryContainer: Color(0xFFDCE7FA),
      tertiary: Color(0xFFB7AFF2),
      onTertiary: Color(0xFF221E45),
      tertiaryContainer: Color(0xFF37325C),
      onTertiaryContainer: Color(0xFFE6E2F8),
      error: Color(0xFFE57368),
      onError: Color(0xFF4A0E08),
      errorContainer: Color(0xFF7A221B),
      onErrorContainer: Color(0xFFFDE7E4),
      surface: Color(0xFF1B1D1B),
      onSurface: Color(0xFFE2E3E0),
      surfaceContainerHighest: Color(0xFF262926),
      onSurfaceVariant: Color(0xFF9FA39B),
      outline: Color(0xFF434643),
      outlineVariant: Color(0xFF2B2D2B),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF141614),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF141614),
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
