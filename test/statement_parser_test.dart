import 'package:bbt/data/categorizer.dart';
import 'package:bbt/data/models.dart';
import 'package:bbt/data/spending_store.dart';
import 'package:bbt/data/statement_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PDF-style text', () {
    const fnbStyle = '''
First National Bank Botswana
Account Number: 6201 2345 6925
Statement Period: 01 Oct 2026 to 31 Oct 2026
Date   Description                       Amount        Balance
01 Oct Opening Balance                                  1,000.00Cr
02 Oct POS PURCHASE CHOPPIES MALL        420.00           580.00Cr
05 Oct SALARY DOCTOR ON CALL          12,000.00Cr     12,580.00Cr
07 Oct UBER TRIP                          87.50       12,492.50Cr
10 Oct MASCOM AIRTIME                    150.00       12,342.50Cr
31 Oct Closing Balance                               12,342.50Cr
''';

    test('reads every transaction with the right sign', () {
      final s = parseStatementText(fnbStyle);
      expect(s.txns.length, 4);
      expect(s.txns.map((t) => t.amount), [-420.00, 12000.00, -87.50, -150.00]);
      expect(s.txns.first.date, DateTime(2026, 10, 2));
    });

    test('detects bank, account and closing balance', () {
      final s = parseStatementText(fnbStyle);
      expect(s.bank, 'First National Bank');
      expect(s.accountTail, '6925');
      expect(s.closingBalance, 12342.50);
    });

    test('categorises', () {
      final s = parseStatementText(fnbStyle);
      expect(s.txns.map((t) => t.cat), [Cat.food, Cat.income, Cat.transport, Cat.bills]);
      expect(s.txns.first.name, 'Choppies Mall');
    });

    test('uses balance changes when there are no Cr/Dr markers', () {
      const text = '''
01/10/2026 Opening balance 500.00
02/10/2026 Cash deposit branch 200.00 700.00
03/10/2026 Spar Riverwalk 100.00 600.00
''';
      final s = parseStatementText(text);
      expect(s.txns.map((t) => t.amount), [200.00, -100.00]);
    });

    test('rolls the year over for Dec → Jan statements', () {
      const text = '''
30 Dec Spar 50.00 950.00
02 Jan Spar 50.00 900.00
2025
''';
      final s = parseStatementText(text);
      expect(s.txns.map((t) => t.date), [DateTime(2025, 12, 30), DateTime(2026, 1, 2)]);
    });
  });

  group('CSV', () {
    test('debit/credit columns', () {
      const csv = '''
Transaction Date,Description,Debit,Credit,Balance
2026-10-01,"Choppies, Main Mall",120.50,,879.50
2026-10-25,Salary,,"12,000.00","12,879.50"
''';
      final s = parseCsv(csv)!;
      expect(s.txns.map((t) => t.amount), [-120.50, 12000.00]);
      expect(s.txns.first.cat, Cat.food);
      expect(s.closingBalance, 12879.50);
    });

    test('single signed amount column, day/month dates', () {
      const csv = '''
Date;Details;Amount
25/10/2026;NETFLIX.COM;-99.00
26/10/2026;REFUND ZARA;650.00
''';
      final s = parseCsv(csv)!;
      expect(s.txns.map((t) => t.amount), [-99.00, 650.00]);
      expect(s.txns.first.date, DateTime(2026, 10, 25));
      expect(s.txns.first.cat, Cat.entertainment);
    });
  });

  group('helpers', () {
    test('parseMoney', () {
      expect(parseMoney('(1,234.00)'), -1234.00);
      expect(parseMoney('P 50.00'), 50.00);
      expect(parseMoney('100.00 Dr'), -100.00);
      expect(parseMoney('87.50-'), -87.50);
      expect(parseMoney(''), isNull);
    });

    test('categorize never matches partial words', () {
      expect(categorize('COFFEE SHOP', -30).$1, Cat.food); // not "fee"
      expect(categorize('SALON NAILS', -200).$1, Cat.other); // not "salary"
    });
  });

  test('store totals by month', () {
    final store = SpendingStore();
    store.load(parseStatementText('''
02 Oct Choppies 100.00Dr 900.00
03 Oct Uber 50.00Dr 850.00
05 Oct Salary 1,000.00Cr 1,850.00
'''), 'test');
    expect(store.monthSpent, 150.00);
    expect(store.monthIncome, 1000.00);
    expect(store.categorySpend.keys.first, Cat.food);
  });
}
