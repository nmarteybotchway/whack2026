import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/pantry_news/demo_news.dart';
import 'package:hackathon/pantry_news/os_notifier.dart';
import 'package:hackathon/pantry_news/pantry_news_controller.dart';

class _FakeNotifier implements OsNotifier {
  final calls = <({String title, String body})>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({required String title, required String body}) async {
    calls.add((title: title, body: body));
  }
}

PantryNewsController _controller(_FakeNotifier notifier) =>
    PantryNewsController(notifier: notifier, delay: Duration.zero);

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('PantryNewsController', () {
    test('delivers the demo news after the delay', () async {
      final notifier = _FakeNotifier();
      final controller = _controller(notifier);

      controller.start();
      await _pump();

      expect(controller.flagged, ['Strawberries']);
      expect(controller.announcedFood, 'Strawberries');
      expect(controller.announcedNews, demoPantryNews['Strawberries']);
      // The recommendation service produced the alternatives to try.
      expect(controller.announcedAlternatives, ['blueberries', 'kiwi', 'banana']);
      expect(
        notifier.calls.single,
        (title: 'Breaking news: Strawberries', body: demoPantryNews['Strawberries']!.news),
      );
    });

    test('dismiss before the delay cancels the delivery', () async {
      final notifier = _FakeNotifier();
      final controller = PantryNewsController(
        notifier: notifier,
        delay: const Duration(hours: 1),
      );

      controller.start();
      controller.dismiss();
      await _pump();

      expect(controller.flagged, isEmpty);
      expect(notifier.calls, isEmpty);
    });

    test('dismiss after delivery hides the banner but keeps the flag', () async {
      final notifier = _FakeNotifier();
      final controller = _controller(notifier);

      controller.start();
      await _pump();
      controller.dismiss();

      expect(controller.announcedFood, isNull);
      expect(controller.announcedNews, isNull);
      expect(controller.announcedAlternatives, isEmpty);
      expect(controller.flagged, ['Strawberries']);
    });

    test('start is idempotent', () async {
      final notifier = _FakeNotifier();
      final controller = _controller(notifier);

      controller.start();
      controller.start();
      await _pump();

      expect(notifier.calls, hasLength(1));
    });
  });
}
