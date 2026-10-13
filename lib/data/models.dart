import 'package:flutter/material.dart';

/// Every transaction belongs to exactly one category. The category decides its
/// [TxnType]: income, a kind of spending, bank charges, or a transfer between
/// the user's own accounts (which is left out of income and spending).
enum Cat {
  food,
  transport,
  shopping,
  bills,
  entertainment,
  health,
  cash,
  people,
  other,
  charges,
  income,
  received,
  transfer,
}

enum TxnType { income, spending, charge, transfer }

extension CatX on Cat {
  TxnType get type => switch (this) {
        Cat.income || Cat.received => TxnType.income,
        Cat.charges => TxnType.charge,
        Cat.transfer => TxnType.transfer,
        _ => TxnType.spending,
      };

  /// Categories a budget limit can be set on.
  bool get isOutflow => type == TxnType.spending || type == TxnType.charge;

  String get label => const {
        Cat.food: 'Food',
        Cat.transport: 'Transport',
        Cat.shopping: 'Shopping',
        Cat.bills: 'Bills',
        Cat.entertainment: 'Entertainment',
        Cat.health: 'Health',
        Cat.cash: 'Cash',
        Cat.people: 'Sent to people',
        Cat.other: 'Other',
        Cat.charges: 'Bank charges',
        Cat.income: 'Income',
        Cat.received: 'From people',
        Cat.transfer: 'Transfer',
      }[this]!;

  IconData get icon => const {
        Cat.food: Icons.shopping_basket_outlined,
        Cat.transport: Icons.directions_car_outlined,
        Cat.shopping: Icons.checkroom_outlined,
        Cat.bills: Icons.receipt_long_outlined,
        Cat.entertainment: Icons.music_note_outlined,
        Cat.health: Icons.favorite_border,
        Cat.cash: Icons.local_atm_outlined,
        Cat.people: Icons.people_outline,
        Cat.other: Icons.more_horiz,
        Cat.charges: Icons.account_balance_outlined,
        Cat.income: Icons.south_west,
        Cat.received: Icons.call_received,
        Cat.transfer: Icons.swap_horiz,
      }[this]!;

  Color get color => const {
        Cat.food: Color(0xFF7ED6A5),
        Cat.transport: Color(0xFFA9A3F0),
        Cat.shopping: Color(0xFFF5B88A),
        Cat.bills: Color(0xFF8CC7F0),
        Cat.entertainment: Color(0xFFF2A0C0),
        Cat.health: Color(0xFFF2D56E),
        Cat.cash: Color(0xFF9ED0C8),
        Cat.people: Color(0xFFC9B3E6),
        Cat.other: Color(0xFFB8C2D0),
        Cat.charges: Color(0xFFE8857A),
        Cat.income: Color(0xFF2E9E6B),
        Cat.received: Color(0xFF7CC4A0),
        Cat.transfer: Color(0xFF9AA8B8),
      }[this]!;
}

Cat? catFromName(String n) {
  for (final c in Cat.values) {
    if (c.name == n) return c;
  }
  return null;
}

/// Description used when the bank printed none (often its own fee lines).
const kNoDescription = 'Bank entry (no description)';

/// Where a transaction's category came from.
enum CatSource {
  rule, // built-in keyword list
  model, // learned guess (Naive Bayes)
  user, // the user picked it (or taught it for this merchant)
  none, // nothing matched
}

class Txn {
  final String? id; // database id, null until saved
  final double fee; // per-transaction fee printed on the statement (charged later as a lump)
  final double? balance; // running balance after this transaction, if printed
  final bool flagged; // amount didn't match the change in balance
  final String name;
  final Cat cat;
  final String sub; // e.g. Groceries
  final DateTime date;
  final double amount; // negative = expense
  final String raw; // description exactly as printed on the statement
  final CatSource source;
  final double confidence; // 0..1, for model guesses
  const Txn(this.name, this.cat, this.sub, this.date, this.amount,
      {this.id,
      this.raw = '',
      this.source = CatSource.rule,
      this.confidence = 1,
      this.fee = 0,
      this.balance,
      this.flagged = false});
  bool get isIncome => amount > 0;
  TxnType get type => cat.type;

  /// Text the categoriser looks at.
  String get text => raw.isEmpty ? name : raw;

  Txn withCategory(Cat cat, String sub, CatSource source, [double confidence = 1]) =>
      Txn(name, cat, sub, date, amount,
          id: id, raw: raw, source: source, confidence: confidence, fee: fee, balance: balance, flagged: flagged);
}

/// Botswana pula: -P 87.50, +P 12,000.00
String pula(double v, {bool sign = false, bool decimals = true}) {
  final s = v.abs().toStringAsFixed(decimals ? 2 : 0).split('.');
  final whole = s[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final prefix = v < 0 ? '-' : (sign ? '+' : '');
  return '${prefix}P $whole${decimals ? '.${s[1]}' : ''}';
}

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String shortDate(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

/// "Oct"
String monthShort(DateTime d) => _monthsShort[d.month - 1];

/// "October 2026"
String monthYear(DateTime d) => '${_monthsLong[d.month - 1]} ${d.year}';

/// "October"
String monthLong(DateTime d) => _monthsLong[d.month - 1];
