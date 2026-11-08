import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows OS notifications for pantry news. Android/iOS only, following the
/// ReceiptScanPage.isSupported platform guard.
class OsNotifier {
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    _initialized = true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } on Exception catch (e) {
      debugPrint('OsNotifier init failed: $e');
    }
  }

  Future<void> show({required String title, required String body}) async {
    if (!isSupported) return;
    await initialize();
    try {
      await _plugin.show(
        id: 1, // one pantry notification at a time; a new one replaces it
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'pantry-news',
            'Pantry news',
            channelDescription: 'Food-safety news about your pantry',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } on Exception catch (e) {
      debugPrint('OsNotifier.show failed: $e');
    }
  }
}
