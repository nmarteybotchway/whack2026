import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hackathon/diet/nutrient_insights.dart';
import 'package:hackathon/garden/nutrient_garden.dart';
import 'package:hackathon/garden/nutrient_score_service.dart';

const _hint = 'Scan a receipt to grow your garden';

/// Stands in for the Rive trees: shows the progress it was given.
Widget _fakeTrees(BuildContext context, double progress) =>
    Text('progress ${progress.toStringAsFixed(2)}');

Widget _garden(Future<NutrientInsights> Function(String userId) loader) =>
    MaterialApp(
      home: Scaffold(
        body: NutrientGarden(
          userId: 'user-1',
          loader: loader,
          treesBuilder: _fakeTrees,
        ),
      ),
    );

NutrientInsights _insights(Map<DateTime, Map<String, double>> intake) =>
    NutrientInsights.fromDaily(intake, today: DateTime(2026, 1, 10), days: 7);

void main() {
  testWidgets('shows bare trees at zero while loading', (tester) async {
    final pending = Completer<NutrientInsights>();
    await tester.pumpWidget(_garden((_) => pending.future));

    expect(find.text('progress 0.00'), findsOneWidget);
    expect(find.text(_hint), findsNothing);

    pending.complete(_insights({}));
    await tester.pumpAndSettle();
  });

  testWidgets('shows the scan hint when no diet is tracked', (tester) async {
    String? requested;
    await tester.pumpWidget(
      _garden((userId) async {
        requested = userId;
        return _insights({});
      }),
    );
    await tester.pumpAndSettle();

    expect(requested, 'user-1');
    expect(find.text('progress 0.00'), findsOneWidget);
    expect(find.text(_hint), findsOneWidget);
  });

  testWidgets('falls back to zero when loading fails', (tester) async {
    await tester.pumpWidget(_garden((_) async => throw StateError('offline')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('progress 0.00'), findsOneWidget);
    expect(find.text(_hint), findsNothing);
  });

  testWidgets('grows the trees to the diet score', (tester) async {
    final insights = _insights({
      DateTime(2026, 1, 10): {
        for (final e in nutrientTargets.entries)
          e.key: e.value.isLimit ? 0 : e.value.daily / 2,
      },
    });
    final score = NutrientScoreService.scoreFromInsights(insights);
    expect(score, greaterThan(0));

    await tester.pumpWidget(_garden((_) async => insights));
    await tester.pumpAndSettle();

    expect(find.text('progress ${score.toStringAsFixed(2)}'), findsOneWidget);
    expect(find.text(_hint), findsNothing);
  });
}
