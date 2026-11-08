import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/pantry_news/os_notifier.dart';
import 'package:hackathon/pantry_news/pantry_news_card.dart';
import 'package:hackathon/pantry_news/pantry_news_controller.dart';

class _FakeNotifier implements OsNotifier {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({required String title, required String body}) async {}
}

/// Pumps the card with [controller] delivered: 1s of fake time fires the
/// zero-delay timer, then the card's listener schedules the slide-in and
/// the animation settles.
Future<void> _pumpCard(WidgetTester tester, PantryNewsController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PantryNewsCard(controller: controller),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1)); // fires the delivery timer
  await tester.pump(); // runs the card's post-frame setState
  await tester.pump(const Duration(milliseconds: 400)); // slide-in settles
}

PantryNewsController _controller() => PantryNewsController(
  notifier: _FakeNotifier(),
  delay: Duration.zero,
);

void main() {
  testWidgets('shows the breaking news with alternatives', (tester) async {
    final controller = _controller()..start();
    await _pumpCard(tester, controller);

    expect(find.text('Breaking news: Strawberries'), findsOneWidget);
    expect(
      find.textContaining('Coventry and across the West Midlands'),
      findsOneWidget,
    );
    expect(find.text('Try instead:'), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(3));
    expect(find.text('blueberries'), findsOneWidget);
  });

  testWidgets('the dismiss button hides the banner', (tester) async {
    final controller = _controller()..start();
    await _pumpCard(tester, controller);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text('Breaking news: Strawberries'), findsNothing);
  });

  testWidgets('the sources button opens the sources dialog', (tester) async {
    final controller = _controller()..start();
    await _pumpCard(tester, controller);

    await tester.tap(find.byTooltip('News sources'));
    await tester.pumpAndSettle();

    expect(find.text('News sources'), findsOneWidget);
    expect(find.textContaining('food.gov.uk'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('News sources'), findsNothing);
  });
}
