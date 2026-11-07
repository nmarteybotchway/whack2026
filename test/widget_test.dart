import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hackathon/pages/setup_page.dart';
import 'package:hackathon/scan/analysis_result_sheet.dart';
import 'package:hackathon/scan/camera_analysis.dart';
import 'package:hackathon/scan/scan_page.dart';

void main() {
  testWidgets('SetupPage shows welcome and guest button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SetupPage()));

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
  });

  testWidgets('ScanPage shows a message on unsupported platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(const MaterialApp(home: ScanPage()));

      expect(
        find.text('Scanning is only supported on Android and iOS.'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('AnalysisResultSheet shows the item and its alternative', (
    tester,
  ) async {
    const result = AnalysisResult(
      item: AnalysedItem(name: 'Crisps', score: 20, highlights: ['Salty']),
      alternative: AnalysedItem(
        name: 'Popcorn',
        score: 70,
        highlights: ['Less fat'],
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnalysisResultSheet(result: result)),
      ),
    );

    expect(find.text('Crisps'), findsOneWidget);
    expect(find.text('Try instead'), findsOneWidget);
    expect(find.text('Popcorn'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
  });
}
