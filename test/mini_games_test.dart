import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/games/mini_games_page.dart';

void main() {
  group('mini game collection', () {
    testWidgets('catalog cards open the selected game instructions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ListView(children: const [MiniGamesSection()])),
        ),
      );
      await tester.tap(find.text('Rainbow Match'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Turn over two cards at a time and remember where each food belongs. Find all six pairs in as few moves as you can.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start game'), findsOneWidget);
    });

    testWidgets('all six games open and fit a narrow phone viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (var i = 0; i < miniGames.length; i++) {
        await tester.pumpWidget(MaterialApp(home: MiniGamePage(gameIndex: i)));
        expect(find.text(miniGames[i].title), findsWidgets);
        expect(find.text('Start game'), findsOneWidget);
        await tester.tap(find.text('Start game'));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: miniGames[i].title);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      }
    });

    testWidgets('Rainbow Match locks input while a mismatch turns back', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: MiniGamePage(gameIndex: 0)),
      );
      await tester.tap(find.text('Start game'));
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      String label(int index) => tester
          .widget<Semantics>(find.byKey(ValueKey('memory-card-$index')))
          .properties
          .label!;

      var moves = 0;
      var lockedPair = false;
      for (var first = 0; first < 12 && !lockedPair; first++) {
        if (label(first) != 'Face down card') continue;
        await tester.tap(find.byKey(ValueKey('memory-card-$first')));
        await tester.pump();
        final firstFace = label(first);
        for (var second = first + 1; second < 12; second++) {
          if (label(second) != 'Face down card') continue;
          await tester.tap(find.byKey(ValueKey('memory-card-$second')));
          await tester.pump();
          moves++;
          if (label(second) != firstFace) {
            final third = List.generate(12, (index) => index).firstWhere(
              (index) =>
                  index != first &&
                  index != second &&
                  label(index) == 'Face down card',
            );
            await tester.tap(find.byKey(ValueKey('memory-card-$third')));
            await tester.pump();
            expect(label(third), 'Face down card');
            expect(find.text('$moves'), findsOneWidget);
            lockedPair = true;
            break;
          }
          break;
        }
      }
      expect(lockedPair, isTrue);
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('Garden Recall ignores tile taps during playback', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: MiniGamePage(gameIndex: 1)),
      );
      await tester.tap(find.text('Start game'));
      await tester.pump();
      expect(find.text('Watch the garden'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Garden tile 1'));
      await tester.pump();
      expect(find.text('0 / 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Market Sort completes twelve prompts and can replay', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: MiniGamePage(gameIndex: 4)),
      );
      await tester.tap(find.text('Start game'));
      await tester.pumpAndSettle();

      for (var prompt = 0; prompt < 12; prompt++) {
        await tester.tap(find.text('Fruit'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('belongs in').evaluate().isNotEmpty ||
              find.textContaining('That’s right!').evaluate().isNotEmpty,
          isTrue,
        );
        final next = find.text(prompt == 11 ? 'See results' : 'Next item');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(find.text('Market sorted!'), findsOneWidget);
      await tester.tap(find.text('Play again'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 12'), findsOneWidget);
    });

    testWidgets('timed games expose pause and resume controls', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: MiniGamePage(gameIndex: 3)),
      );
      await tester.tap(find.text('Start game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start · then tap in the arc'));
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('Pause'), findsOneWidget);
      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Paused'), findsWidgets);
      expect(find.text('Resume'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: MiniGamePage(key: ValueKey('hydration'), gameIndex: 2),
        ),
      );
      await tester.tap(find.text('Start game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start round'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('Pause game'));
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Trail Tiles shows numbered tiles and a solvable goal preview',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: MiniGamePage(gameIndex: 5)),
        );
        await tester.tap(find.text('Start game'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Goal: arrange'), findsOneWidget);
        final semantics = tester.ensureSemantics();
        final board = <int>[];
        var blank = -1;
        for (var index = 0; index < 9; index++) {
          final label = tester
              .widget<Semantics>(find.byKey(ValueKey('trail-tile-$index')))
              .properties
              .label!;
          if (label == 'Empty space') {
            board.add(0);
            blank = index;
          } else {
            board.add(int.parse(label.substring('Tile '.length)));
          }
        }
        expect(board.toSet(), equals({0, 1, 2, 3, 4, 5, 6, 7, 8}));
        var inversions = 0;
        final numbered = board.where((tile) => tile != 0).toList();
        for (var i = 0; i < numbered.length; i++) {
          for (var j = i + 1; j < numbered.length; j++) {
            if (numbered[i] > numbered[j]) inversions++;
          }
        }
        expect(inversions.isEven, isTrue);

        final nonAdjacent = List.generate(9, (index) => index).firstWhere(
          (index) =>
              index != blank &&
              (index ~/ 3 - blank ~/ 3).abs() + (index % 3 - blank % 3).abs() >
                  1,
        );
        await tester.tap(find.byKey(ValueKey('trail-tile-$nonAdjacent')));
        await tester.pumpAndSettle();
        final movesCard = find
            .ancestor(of: find.text('MOVES'), matching: find.byType(Container))
            .first;
        expect(
          find.descendant(of: movesCard, matching: find.text('0')),
          findsOneWidget,
        );

        final adjacent = List.generate(9, (index) => index).firstWhere(
          (index) =>
              index != blank &&
              (index ~/ 3 - blank ~/ 3).abs() + (index % 3 - blank % 3).abs() ==
                  1,
        );
        await tester.tap(find.byKey(ValueKey('trail-tile-$adjacent')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: movesCard, matching: find.text('1')),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );
  });
}
