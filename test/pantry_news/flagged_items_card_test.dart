import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/pantry_news/flagged_items_card.dart';
import 'package:hackathon/pantry_news/os_notifier.dart';
import 'package:hackathon/pantry_news/pantry_news_controller.dart';

class _FakeNotifier implements OsNotifier {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({required String title, required String body}) async {}
}

Future<void> _pump(WidgetTester tester, PantryNewsController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [FlaggedItemsCard(controller: controller)],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders nothing before anything is flagged', (tester) async {
    await _pump(
      tester,
      PantryNewsController(notifier: _FakeNotifier()),
    );

    expect(find.text('Flagged items'), findsNothing);
  });

  testWidgets('lists the flagged food with news and alternatives', (tester) async {
    final controller = PantryNewsController(
      notifier: _FakeNotifier(),
      delay: Duration.zero,
    );
    controller.start();
    await tester.pump(const Duration(seconds: 1)); // fires the delivery timer
    await _pump(tester, controller);

    expect(find.text('Flagged items'), findsOneWidget);
    expect(find.text('Strawberries'), findsOneWidget);
    expect(find.textContaining('Coventry and across the West Midlands'), findsOneWidget);
    expect(find.textContaining('Try instead: blueberries'), findsOneWidget);
  });
}
