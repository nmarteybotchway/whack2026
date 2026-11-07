import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/food/food_matcher.dart';
import 'package:hackathon/food/known_foods.g.dart';

void main() {
  test('matches catalogue names to known foods', () {
    expect(
      matchKnownFood('Tesco Granny Smith Apples 6 Pack'),
      KnownFood.apples,
    );
    expect(
      matchKnownFood('Birds Eye Frozen Mixed Vegetables 1kg'),
      KnownFood.frozenVeg,
    );
    expect(matchKnownFood('Red Bull Energy Drink 250ml'), KnownFood.redBull);
    expect(
      matchKnownFood('Butterkist Sweet & Salty Popcorn'),
      KnownFood.sweetAndSaltyPopcorn,
    );
    expect(
      matchKnownFood('Fruit Shoot Apple & Blackcurrant'),
      KnownFood.robinsonsFruitShoot,
    );
    expect(
      matchKnownFood('Warburtons Toastie White Bread 800g'),
      KnownFood.breadToast,
    );
    expect(matchKnownFood('Free Range Large Eggs x12'), KnownFood.eggs);
  });

  test('matches names written as one word or with separators', () {
    for (final name in ['red bull', 'red_bull', 'RED-BULL', 'redbull']) {
      expect(matchKnownFood(name), KnownFood.redBull, reason: name);
    }
    expect(matchKnownFood('Redbull Energy 250ml'), KnownFood.redBull);
    expect(matchKnownFood('Fruitshoot Orange'), KnownFood.robinsonsFruitShoot);
    expect(matchKnownFood('Frozenveg mix'), KnownFood.frozenVeg);
  });

  test('returns null when nothing fits', () {
    expect(matchKnownFood('Heinz Baked Beanz 415g'), isNull);
    expect(matchKnownFood('Red Leicester Cheese'), isNull);
    expect(matchKnownFood(''), isNull);
  });
}
