import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Device-level appearance: light/dark/auto mode and the accent colour.
/// Saved locally so the app opens in the right theme before sign-in.
class AppearanceController extends ChangeNotifier {
  AppearanceController._(this._prefs, this._mode, this._accent);

  static const _modeKey = 'appearance.mode';
  static const _accentKey = 'appearance.accent';

  final SharedPreferences? _prefs;
  ThemeMode _mode;
  ThemeAccent _accent;

  ThemeMode get mode => _mode;
  ThemeAccent get accent => _accent;

  /// Loads the saved choice; falls back to auto + fresh green.
  static Future<AppearanceController> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // Storage unavailable — keep defaults for this session.
    }
    final mode = ThemeMode.values.asNameMap()[prefs?.getString(_modeKey)];
    final accent = ThemeAccent.values.asNameMap()[prefs?.getString(_accentKey)];
    return AppearanceController._(
      prefs,
      mode ?? ThemeMode.system,
      accent ?? ThemeAccent.freshGreen,
    );
  }

  void setMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    _prefs?.setString(_modeKey, mode.name);
  }

  void setAccent(ThemeAccent accent) {
    if (accent == _accent) return;
    _accent = accent;
    notifyListeners();
    _prefs?.setString(_accentKey, accent.name);
  }
}

/// Exposes the [AppearanceController] to every route below the app.
class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppearanceController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()!.notifier!;
}
