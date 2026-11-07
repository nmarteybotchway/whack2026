import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/food/food.dart';
import 'package:hackathon/food/food_recommendation_service.dart';
import 'package:hackathon/food_news.dart';
import 'package:hackathon/scan/analysis_result_sheet.dart';
import 'package:hackathon/scan/camera_analysis.dart';
import 'package:hackathon/scan/product_identification_service.dart';

const _product = ProductIdentification(
  status: 'identified',
  productName: 'Tofu',
  brand: null,
  variant: null,
  packageSize: null,
  sku: null,
  gtin: null,
  confidence: 90,
  productNameConfidence: 90,
  brandConfidence: 0,
  variantConfidence: 0,
  skuConfidence: 0,
  gtinConfidence: 0,
  evidence: [],
  uncertainties: [],
);

const _tofu = Food(name: 'Tofu', localNews: 'Recalled batch detected.');

Widget _sheet({
  required FoodNewsService news,
  required FoodRecommendationService recommendations,
}) => MaterialApp(
  home: Scaffold(
    body: AnalysisResultSheet(
      result: const AnalysisResult(identification: _product),
      newsService: news,
      recommendationService: recommendations,
      userId: 'u1',
    ),
  ),
);

void main() {
  testWidgets('rebuilds from the swap checkbox do not refetch', (tester) async {
    var newsFetches = 0;
    var foodFetches = 0;
    await tester.pumpWidget(
      _sheet(
        news: FoodNewsService(
          fetcher: (name) async {
            newsFetches++;
            return _tofu;
          },
        ),
        recommendations: FoodRecommendationService(
          fetcher: (name) async {
            foodFetches++;
            return _tofu;
          },
          userFetcher: (uid) async => null,
          insightsFetcher: (uid) async => throw StateError('no diet'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not recommended'), findsOneWidget);
    expect((newsFetches, foodFetches), (1, 1));

    // Toggling the checkbox calls setState on the sheet (and, with no
    // Firebase in tests, again when the save fails and is reverted).
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect((newsFetches, foodFetches), (1, 1));
  });

  testWidgets('failed loads show an error card instead of a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sheet(
        news: FoodNewsService(fetcher: (name) async => throw Exception('x')),
        recommendations: FoodRecommendationService(
          fetcher: (name) async => _tofu,
          userFetcher: (uid) async => throw Exception('permission-denied'),
          insightsFetcher: (uid) async => throw Exception('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Couldn’t load food news.'), findsOneWidget);
    expect(find.text('Couldn’t load a recommendation.'), findsOneWidget);
  });
}
