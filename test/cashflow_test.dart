import 'package:bbt/data/models.dart';
import 'package:bbt/data/smart_categorizer.dart';
import 'package:bbt/data/spending_store.dart';
import 'package:bbt/data/statement_parser.dart';
import 'package:bbt/services/backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// A made-up statement in the same layout as a real FNB Botswana PDF:
/// Date · Description · Reference · Amount · Balance (Cr/Dr) · accrued fee.
/// Names and numbers are fictional. Opening + every line = closing exactly.
const fnbStyle = '''
Test Bank Statement  First National Bank Botswana
Account Number: 6200 0000 9999
Statement Period : 01 June 2026 to 30 June 2026
Date Description Reference Amount Balance Accrued Bank Charges
01 Jun Opening Balance 241.08Cr
01 Jun FNB App Transfer From Kk 300.00Cr 541.08Cr
02 Jun FNB App Payment From Thabo Molefe 250.00Cr 791.08Cr
02 Jun FNB App Payment To P2C 26771111111 Test User 200.00 591.08Cr 3.85
02 Jun FNB App Payment To P2C 26772222222 Test User 150.00 441.08Cr 3.85
03 Jun ATM Cash Mall 00740082 400000*1234 100.00 341.08Cr 2.75
03 Jun FNB App Prepaid Airtime 26771111111 20.00 321.08Cr
04 Jun POS Purchase Choppies Hyper Stor 400000*1234 03 Jun 94.90 226.18Cr
05 Jun POS Purchase 1.69 Spotify P42857 400000*1234 04 Jun 24.96 201.22Cr
06 Jun Send Money Dr Send 26773333333 50.00 151.22Cr 10.40
07 Jun FNB App Transfer To Kk 210.00 58.78Dr
08 Jun FNB OB Pmt Uniallowjun26 1,500.00Cr 1,441.22Cr
09 Jun FNB App Transfer To Mm 400.00 1,041.22Cr
10 Jun FNB App Transfer From Mm 100.00Cr 1,141.22Cr
12 Jun Byc Debit 63015864936 20.04 1,121.18Cr
28 Jun #Monthly Account Fee 3.00 1,118.18Cr
28 Jun #Service Fees 20.85 1,097.33Cr
30 Jun Closing Balance 1,097.33Cr
''';

SpendingStore _storeFor(ParsedStatement s) => SpendingStore()
  ..categoriserForTesting = SmartCategorizer()
  ..load(s, 'test');

Txn _find(SpendingStore st, String text) => st.txns.firstWhere((t) => t.text.contains(text));

void main() {
  group('reading amounts', () {
    final s = parseStatementText(fnbStyle);

    test('reads every line', () => expect(s.txns.length, 16));

    test('a fee column after the balance is not mistaken for the balance', () {
      final p2c = s.txns.firstWhere((t) => t.raw.contains('72222222'));
      expect(p2c.amount, -150.00);
      expect(p2c.balance, 441.08);
      expect(p2c.fee, 3.85);
    });

    test('numbers inside the description are ignored', () {
      final spotify = s.txns.firstWhere((t) => t.raw.contains('Spotify'));
      expect(spotify.amount, -24.96);
      expect(spotify.fee, 0);
    });

    test('overdrawn (Dr) balances work', () {
      final t = s.txns.firstWhere((t) => t.raw.contains('Transfer To Kk'));
      expect(t.amount, -210.00);
      expect(t.balance, -58.78);
    });

    test('books balance: opening + lines = closing', () {
      expect(s.openingBalance, 241.08);
      expect(s.closingBalance, 1097.33);
      expect(s.difference, 0);
      expect(s.flaggedCount, 0);
    });

    test('newest-first statements read the same', () {
      final lines = fnbStyle.trim().split('\n');
      final header = lines.take(5);
      final body = lines.skip(5).take(16).toList().reversed;
      final reversed = [...header, ...body, lines.last].join('\n');
      final r = parseStatementText(reversed);
      expect(r.txns.length, 16);
      expect(r.difference, 0);
      expect(r.txns.firstWhere((t) => t.raw.contains('72222222')).amount, -150.00);
    });

    test('a line that does not add up is flagged', () {
      final broken = fnbStyle.replaceFirst('94.90 226.18Cr', '94.90 999.99Cr');
      final r = parseStatementText(broken);
      expect(r.flaggedCount, greaterThan(0));
    });
  });

  group('cash flow', () {
    final store = _storeFor(parseStatementText(fnbStyle));

    test('transfers between own accounts are detected and excluded', () {
      expect(store.ownAccounts, containsAll(['kk', 'mm']));
      expect(_find(store, 'Transfer From Kk').cat, Cat.transfer);
      expect(_find(store, 'Transfer To Mm').cat, Cat.transfer);
    });

    test('money in, money out and charges', () {
      expect(store.monthIncome, closeTo(1750.00, 0.001)); // 250 from a person + 1,500 allowance
      expect(store.monthCharges, closeTo(23.85, 0.001)); // monthly fee + service fees
      expect(store.monthSpent, closeTo(683.75, 0.001)); // 659.90 spending + 23.85 charges
      expect(store.monthTransfersOut, closeTo(610.00, 0.001));
      expect(store.monthTransfersIn, closeTo(400.00, 0.001));
    });

    test('sending to your own number is cash, to someone else is sent to people', () {
      expect(store.suggestedPhone, '71111111'); // from the airtime purchases
      expect(_find(store, '71111111 Test User').cat, Cat.cash);
      expect(_find(store, '72222222').cat, Cat.people);
      expect(_find(store, 'Send Money').cat, Cat.people);
      expect(_find(store, 'ATM Cash').cat, Cat.cash);
    });

    test('charges are their own category', () {
      expect(_find(store, 'Monthly Account Fee').cat, Cat.charges);
      expect(_find(store, 'Service Fees').cat, Cat.charges);
      expect(store.categorySpend[Cat.charges], closeTo(23.85, 0.001));
    });

    test('fee column explains the service fees without double counting', () {
      expect(store.monthAccruedFees, closeTo(20.85, 0.001));
      final b = store.feeBreakdown;
      expect(b['Sending money']!.$1, 2);
      expect(b['Sending money']!.$2, closeTo(14.25, 0.001));
      expect(b['Cash withdrawals']!.$2, closeTo(6.60, 0.001));
    });

    test('one-off income is not regular', () {
      final allowance = _find(store, 'Uniallowjun26');
      expect(allowance.cat, Cat.income);
      expect(store.isRegularIncome(allowance), isFalse);
      expect(store.monthRegularIncome, 0);
    });

    test('flow diagram adds up', () {
      final f = store.flow;
      final out = f.outflows.values.fold(0.0, (a, b) => a + b);
      expect(f.income + f.fromBalance, closeTo(out + f.leftOver, 0.001));
    });

    test('books check balances', () {
      final check = store.booksCheck(StatementRecord(
        id: 'x',
        fileName: 'test.pdf',
        openingBalance: 241.08,
        closingBalance: 1097.33,
        periodStart: DateTime(2026, 6, 1),
        periodEnd: DateTime(2026, 6, 30),
        txnCount: 16,
        uploadedAt: DateTime(2026, 7, 1),
      ))!;
      expect(check.income, closeTo(1750.00, 0.001));
      expect(check.charges, closeTo(-23.85, 0.001));
      expect(check.transfers, closeTo(-210.00, 0.001));
      expect(check.balanced, isTrue);
    });

    test('rejecting a detected own account counts it again', () async {
      final s = _storeFor(parseStatementText(fnbStyle));
      await s.confirmOwnAccount('mm', false);
      expect(_find(s, 'Transfer To Mm').cat, Cat.people);
      expect(_find(s, 'Transfer From Mm').cat, Cat.received);
    });
  });

  test('other banks: minus signs and a plain transfer to a person', () {
    const text = '''
2026/03/01 Opening balance 1000.00
2026/03/02 Card purchase Sefalana -100.00 900.00
2026/03/03 Transfer to John Smith -200.00 700.00
2026/03/04 Salary Acme Ltd 3000.00 3700.00
2026/03/05 Transfer to savings -500.00 3200.00
2026/03/31 Closing balance 3200.00
''';
    final s = parseStatementText(text);
    expect(s.txns.map((t) => t.amount), [-100.00, -200.00, 3000.00, -500.00]);
    expect(s.difference, 0);
    final store = _storeFor(s);
    expect(_find(store, 'John Smith').cat, Cat.people);
    expect(_find(store, 'savings').cat, Cat.transfer);
    expect(store.monthIncome, 3000.00);
  });

  group('round 2 rules (any bank)', () {
    // A different layout: ISO dates, minus signs, a summary block with several
    // figures per line, and a fee line the bank printed without a description.
    const summaryStyle = """
Account summary
Opening Balance 100.00 Cr     Service Fees 12.50 Dr     Interest Rate 0.00%
Closing Balance 37.50 Cr      Cash Deposit Fees 0.50 Dr
2026-05-01 Grocer Mart -50.00 50.00
2026-05-31   -12.50 37.50
""";

    test('opening/closing take the figure right after the words', () {
      final s = parseStatementText(summaryStyle);
      expect(s.openingBalance, 100.00);
      expect(s.closingBalance, 37.50);
      expect(s.difference, 0);
    });

    test("the statement's own fee total is read", () {
      expect(parseStatementText(summaryStyle).statedCharges, 13.00);
    });

    test('a debit with no description is a bank charge', () {
      final store = _storeFor(parseStatementText(summaryStyle));
      final fee = store.txns.firstWhere((t) => t.amount == -12.50);
      expect(fee.cat, Cat.charges);
      expect(fee.name, 'Bank fee');
      expect(store.monthCharges, 12.50);
    });

    test('account codes can contain digits', () {
      const text = """
2026-04-01 Opening balance 500.00
2026-04-02 Transfer to 8F -100.00 400.00
2026-04-05 Transfer from 8F 40.00 440.00
""";
      final store = _storeFor(parseStatementText(text));
      expect(store.ownAccounts, contains('8f'));
      expect(store.monthIncome, 0);
    });

    test('money from people is received, not income; only income can be regular', () {
      const text = """
2026-04-01 Opening balance 0.00
2026-04-25 Salary Acme Ltd 3000.00 3000.00
2026-04-26 Payment from Jane Doe 500.00 3500.00
2026-05-25 Salary Acme Ltd 3000.00 6500.00
2026-05-26 Payment from Jane Doe 500.00 7000.00
""";
      final store = _storeFor(parseStatementText(text));
      expect(_find(store, 'Jane Doe').cat, Cat.received);
      expect(_find(store, 'Salary').cat, Cat.income);
      expect(store.monthIncome, 7000.00); // all money in
      expect(store.monthEarned, 6000.00);
      expect(store.monthReceived, 1000.00);
      expect(store.monthRegularIncome, 6000.00); // Jane is regular but not income
    });

    test('left over minus money moved to own accounts = change in balance', () {
      final store = _storeFor(parseStatementText(fnbStyle));
      final leftOver = store.monthIncome - store.monthSpent;
      expect(leftOver - store.monthMovedToOwn, closeTo(store.monthBalanceChange, 0.001));
      expect(store.monthBalanceChange, closeTo(1097.33 - 241.08, 0.001));
    });

    test('each month has its own money in and out', () {
      final store = _storeFor(parseStatementText(fnbStyle));
      final june = store.monthSummaries.single;
      expect(june.income, closeTo(1750.00, 0.001));
      expect(june.spent, closeTo(683.75, 0.001));
      expect(june.charges, closeTo(23.85, 0.001));
      expect(june.movedToOwn, closeTo(210.00, 0.001));
    });
  });

  test('month comparison: daily amounts per category add up to the month', () {
    final store = _storeFor(parseStatementText(fnbStyle));
    final june = DateTime(2026, 6);
    final allOut = store.dailyAmounts(june);
    expect(allOut.length, 30);
    expect(allOut.fold(0.0, (a, b) => a + b), closeTo(store.monthSpent, 0.001));
    final food = store.dailyAmounts(june, cat: Cat.food);
    expect(food[3], closeTo(94.90, 0.001)); // 4 June
    expect(store.dailyAmounts(june, moneyIn: true).fold(0.0, (a, b) => a + b), closeTo(1750.00, 0.001));
  });

  test('pie can show one month or all months', () {
    final store = _storeFor(parseStatementText("""
2026-04-01 Opening balance 1000.00
2026-04-05 Grocer Mart -100.00 900.00
2026-05-05 Grocer Mart -40.00 860.00
2026-05-06 Uber trip -20.00 840.00
"""));
    expect(store.categorySpendFor(null)[Cat.food], 140.00);
    expect(store.categorySpendFor(DateTime(2026, 5))[Cat.food], 40.00);
    expect(store.categorySpendFor(DateTime(2026, 4)).containsKey(Cat.transport), isFalse);
  });

  test('home insight never states what was left over', () {
    final store = _storeFor(parseStatementText(fnbStyle));
    expect(store.homeInsight.toLowerCase(), isNot(contains('kept')));
    expect(store.homeInsight.toLowerCase(), isNot(contains('left')));
  });

  test('a budget plan replaces the limits and sets planned income', () async {
    final store = _storeFor(parseStatementText(fnbStyle));
    await store.saveBudgetPlan(3000, 600, {Cat.food: 800, Cat.transport: 0, Cat.bills: 400});
    expect(store.hasPlan, isTrue);
    expect(store.plannedIncome, 3000);
    expect(store.budgets, {Cat.food: 800.0, Cat.bills: 400.0}); // zero means no limit
  });
}
