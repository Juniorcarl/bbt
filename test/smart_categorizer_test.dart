import 'package:bbt/data/models.dart';
import 'package:bbt/data/smart_categorizer.dart';
import 'package:bbt/data/spending_store.dart';
import 'package:bbt/data/statement_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SmartCategorizer cz;
  setUp(() => cz = SmartCategorizer());

  test('keyword rules still work out of the box', () {
    expect(cz.classify('POS PURCHASE CHOPPIES', 'Choppies', -100).cat, Cat.food);
    expect(cz.classify('SALARY', 'Salary', 5000).cat, Cat.income);
  });

  test('recognises typos of known merchants', () {
    final g = cz.classify('CHOPIES MOGODITSHANE', 'Chopies Mogoditshane', -120);
    expect(g.cat, Cat.food);
    expect(g.source, CatSource.model);
  });

  test('does not guess wildly on names it has never seen', () {
    final g = cz.classify('JUSTICE MOTSWAGOLE', 'Justice Motswagole', -300);
    expect(g.source, CatSource.none);
  });

  test('remembers a merchant the user taught', () async {
    cz.learn('KGALAGADI BREWERIES 1234', 'Kgalagadi Breweries', -150, Cat.entertainment);
    final g = cz.classify('KGALAGADI BREWERIES 9999', 'Kgalagadi Breweries', -80);
    expect(g.cat, Cat.entertainment);
    expect(g.source, CatSource.user);
  });

  test('generalises from what the user taught to new variants', () async {
    cz.learn('MOTHERS TOUCH CATERING', 'Mothers Touch Catering', -150, Cat.food);
    final g = cz.classify('MOTHERS TOUCH CATERERS PALAPYE', 'Mothers Touch Caterers Palapye', -90);
    expect(g.cat, Cat.food);
    expect(g.source, CatSource.model);
  });

  test('user teaching beats a keyword rule for that merchant', () async {
    // "Game" is a shopping keyword, but this person's "Game Lodge" is entertainment.
    cz.learn('GAME LODGE MAUN', 'Game Lodge Maun', -900, Cat.entertainment);
    expect(cz.classify('GAME LODGE MAUN', 'Game Lodge Maun', -400).cat, Cat.entertainment);
  });

  test('reset forgets everything', () async {
    cz.learn('SEDIBENG', 'Sedibeng', -50, Cat.food);
    cz.reset();
    expect(cz.examplesLearned, 0);
    expect(cz.classify('SEDIBENG', 'Sedibeng', -50).source, CatSource.none);
  });

  test('store.teach updates every matching transaction', () async {
    final store = SpendingStore()..categoriserForTesting = cz;
    store.load(parseStatementText('''
02 Oct SEDIBENG TUCKSHOP 20.00Dr 980.00
09 Oct SEDIBENG TUCKSHOP 35.00Dr 945.00
12 Oct UBER 50.00Dr 895.00
'''), 'test');
    expect(store.needsReview, 2);
    final changed = await store.teach(store.txns.last, Cat.food);
    expect(changed, 2);
    expect(store.needsReview, 0);
    expect(store.categorySpend[Cat.food], 55.00);
  });
}
