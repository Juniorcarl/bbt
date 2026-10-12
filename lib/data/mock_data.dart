import 'categorizer.dart';
import 'models.dart';
import 'statement_parser.dart';

/// Default monthly limits for the Budget screen until users can edit them.
const budgets = {
  Cat.food: 1500.0,
  Cat.transport: 1000.0,
  Cat.shopping: 1200.0,
  Cat.bills: 2000.0,
  Cat.entertainment: 500.0,
  Cat.health: 800.0,
};

/// Demo statement for "Try with sample data" — goes through the same
/// categorizer as a real upload so the screens behave identically.
ParsedStatement sampleStatement() {
  const rows = <(int, int, String, double)>[
    // (month, day, description, amount)
    (9, 1, 'POS PURCHASE CHOPPIES MALL', -380.00),
    (9, 2, 'MASCOM AIRTIME', -150.00),
    (9, 4, 'UBER TRIP', -64.00),
    (9, 6, 'ZARA RIVERWALK', -820.00),
    (9, 9, 'BPC PREPAID ELECTRICITY', -300.00),
    (9, 12, 'SPOTIFY P1234', -79.99),
    (9, 14, 'PUMA FILLING STATION', -450.00),
    (9, 17, 'SPAR AIRPORT JUNCTION', -512.40),
    (9, 20, 'NANDOS GAME CITY', -168.00),
    (9, 25, 'SALARY DOCTOR ON CALL', 12000.00),
    (9, 26, 'WUC WATER', -210.00),
    (9, 28, 'DISCHEM PHARMACY', -245.00),
    (10, 1, 'POS PURCHASE SEFALANA', -430.00),
    (10, 3, 'BOLT RIDE', -55.00),
    (10, 5, 'MONTHLY SERVICE FEE', -45.00),
    (10, 7, 'DEBONAIRS PIZZA', -189.00),
    (10, 10, 'ATM CASH WITHDRAWAL', -400.00),
    (10, 12, 'NETFLIX.COM', -99.00),
    (10, 15, 'ENGEN GABORONE', -400.00),
    (10, 20, 'MASCOM DATA BUNDLE', -500.00),
    (10, 24, 'PHARMACY MAIN MALL', -326.00),
    (10, 25, 'SALARY DOCTOR ON CALL', 12000.00),
    (10, 26, 'ZARA RIVERWALK', -650.00),
    (10, 27, 'SPOTIFY P1234', -79.99),
    (10, 28, 'CHOPPIES MALL', -420.00),
    (10, 29, 'UBER TRIP', -87.50),
  ];
  final txns = [
    for (final (m, d, desc, amt) in rows)
      () {
        final (cat, sub) = categorize(desc, amt);
        return Txn(cleanName(desc), cat, sub, DateTime(2026, m, d), amt, raw: desc);
      }(),
  ];
  return ParsedStatement(txns, bank: 'First National Bank', accountTail: '6925', closingBalance: 12505.58);
}
