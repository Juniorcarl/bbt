import 'package:flutter/foundation.dart';

import 'models.dart';
import 'statement_parser.dart';

/// Holds the uploaded statement and works out every number the screens show.
class SpendingStore extends ChangeNotifier {
  List<Txn> _txns = const [];
  String? bank;
  String? accountTail;
  String? sourceName;
  double? closingBalance;
  bool isSample = false;
  DateTime? _month;

  List<Txn> get txns => _txns;
  bool get hasData => _txns.isNotEmpty;

  void load(ParsedStatement s, String name, {bool sample = false}) {
    _txns = [...s.txns]..sort((a, b) => b.date.compareTo(a.date));
    bank = s.bank;
    accountTail = s.accountTail;
    closingBalance = s.closingBalance;
    sourceName = name;
    isSample = sample;
    _month = months.isEmpty ? null : months.first;
    notifyListeners();
  }

  void clear() {
    _txns = const [];
    bank = accountTail = sourceName = null;
    closingBalance = null;
    _month = null;
    notifyListeners();
  }

  // ---- Months ------------------------------------------------------------

  /// Months that have transactions, newest first.
  List<DateTime> get months {
    final set = <DateTime>{for (final t in _txns) DateTime(t.date.year, t.date.month)};
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  DateTime get month => _month ?? DateTime(DateTime.now().year, DateTime.now().month);
  set month(DateTime m) {
    _month = DateTime(m.year, m.month);
    notifyListeners();
  }

  bool _inMonth(Txn t, DateTime m) => t.date.year == m.year && t.date.month == m.month;

  List<Txn> txnsIn(DateTime m) => _txns.where((t) => _inMonth(t, m)).toList();
  List<Txn> get monthTxns => txnsIn(month);

  /// "Today" for filters = the last day with data in the selected month
  /// (statements are always in the past, so the real today is usually empty).
  DateTime get refDate {
    final list = monthTxns;
    if (list.isEmpty) return DateTime(month.year, month.month + 1, 0);
    final d = list.first.date;
    return DateTime(d.year, d.month, d.day);
  }

  // ---- Totals ------------------------------------------------------------

  double spentIn(DateTime m) => txnsIn(m).where((t) => t.amount < 0).fold(0.0, (a, t) => a - t.amount);
  double incomeIn(DateTime m) => txnsIn(m).where((t) => t.amount > 0).fold(0.0, (a, t) => a + t.amount);

  double get monthSpent => spentIn(month);
  double get monthIncome => incomeIn(month);

  DateTime get _prevMonth => DateTime(month.year, month.month - 1);

  /// Whether the statement covers (almost) the whole month, so comparisons are fair.
  bool _coversMonth(DateTime m) {
    if (_txns.isEmpty) return false;
    final earliest = _txns.last.date;
    final latest = _txns.first.date;
    return !earliest.isAfter(DateTime(m.year, m.month, 4)) &&
        !latest.isBefore(DateTime(m.year, m.month + 1, 0).subtract(const Duration(days: 4)));
  }

  /// Fractional change vs last month (-0.12 = 12% less). Null if we can't compare fairly.
  double? get changeVsPrev {
    final prev = _prevMonth;
    if (!_coversMonth(prev)) return null;
    final p = spentIn(prev);
    if (p == 0) return null;
    return (monthSpent - p) / p;
  }

  /// Spending per category this month, biggest first. Income excluded.
  Map<Cat, double> get categorySpend {
    final m = <Cat, double>{};
    for (final t in monthTxns) {
      if (t.amount >= 0) continue;
      m[t.cat] = (m[t.cat] ?? 0) - t.amount;
    }
    final sorted = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

  // ---- Chart data -------------------------------------------------------

  Map<String, double> bars(String mode) {
    switch (mode) {
      case 'Daily':
        final end = refDate;
        final out = <String, double>{};
        for (var i = 6; i >= 0; i--) {
          final d = end.subtract(Duration(days: i));
          out[shortDate(d)] = _spentOn(d);
        }
        return out;
      case 'Weekly':
        final lastDay = monthTxns.isEmpty ? 0 : refDate.day;
        final out = <String, double>{};
        for (var w = 0; w * 7 + 1 <= lastDay; w++) {
          final from = w * 7 + 1, to = w * 7 + 7;
          out['Wk ${w + 1}'] = monthTxns
              .where((t) => t.amount < 0 && t.date.day >= from && t.date.day <= to)
              .fold(0.0, (a, t) => a - t.amount);
        }
        return out;
      default: // Monthly
        final ms = months.where((m) => !m.isAfter(month)).take(6).toList().reversed;
        return {for (final m in ms) monthShort(m): spentIn(m)};
    }
  }

  double _spentOn(DateTime d) => _txns
      .where((t) => t.amount < 0 && t.date.year == d.year && t.date.month == d.month && t.date.day == d.day)
      .fold(0.0, (a, t) => a - t.amount);

  // ---- Plain-language summary -----------------------------------------

  String get insight {
    if (!hasData) return 'Upload a statement to see where your money goes.';
    final spent = monthSpent;
    if (spent == 0) return 'No spending recorded in ${monthLong(month)}.';
    final change = changeVsPrev;
    final cats = categorySpend;
    final top = cats.entries.first;
    final topShare = (top.value / spent * 100).round();
    final topLine = '${top.key.label} is your biggest category at $topShare% (${pula(top.value, decimals: false)}).';
    if (change == null) return topLine;
    final pct = (change.abs() * 100).round();
    if (pct == 0) return 'Same spending as last month. $topLine';
    return change < 0
        ? "You've spent $pct% less than last month. $topLine"
        : "You've spent $pct% more than last month. $topLine";
  }
}

/// Single app-wide instance — fine for Stage 1 (no login, one statement at a time).
final store = SpendingStore();
