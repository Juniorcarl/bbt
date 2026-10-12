import 'package:flutter/foundation.dart';

import '../services/backend.dart';
import 'models.dart';
import 'smart_categorizer.dart';
import 'statement_parser.dart';

/// One row of the month-by-month breakdown.
class MonthSummary {
  final DateTime month;
  final double spent;
  final double income;
  final int count;
  const MonthSummary(this.month, this.spent, this.income, this.count);
  double get net => income - spent;
}

/// The signed-in user's data, and every number the screens show.
///
/// Data lives in Supabase ([Backend]); this class keeps a copy in memory and
/// does the maths. The screens look at a *period*: one month, or all months
/// ([allMonths]).
class SpendingStore extends ChangeNotifier {
  SpendingStore({Backend? backend}) : _db = backend;

  /// Null in tests: everything still works, nothing is saved.
  Backend? _db;
  set backend(Backend? b) => _db = b;

  List<Txn> _txns = const [];
  List<StatementRecord> statements = const [];
  Map<Cat, double> budgets = const {};
  String userName = '';
  String userEmail = '';
  DateTime? _month; // null = all months

  bool loading = false;
  String? loadError;

  List<Txn> get txns => _txns;
  bool get hasData => _txns.isNotEmpty;

  /// Latest uploaded statement (for the account card).
  StatementRecord? get latestStatement => statements.isEmpty ? null : statements.first;

  // ---- Loading ------------------------------------------------------------

  /// Loads everything for the signed-in user.
  Future<void> loadForUser() async {
    final db = _db;
    if (db == null) return;
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        db.fetchLessons(),
        db.fetchTransactions(),
        db.fetchStatements(),
        db.fetchBudgets(),
        db.fetchName(),
      ]);
      _cz.restore(results[0] as List<Lesson>);
      _setTxns((results[1] as List<Txn>).map(_categorise));
      statements = results[2] as List<StatementRecord>;
      budgets = results[3] as Map<Cat, double>;
      userName = results[4] as String;
      userEmail = db.user?.email ?? '';
      _month = null;
    } catch (e) {
      loadError = "Couldn't load your data. Check your internet connection and try again.";
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Forget everything in memory (sign-out).
  void clear() {
    _txns = const [];
    statements = const [];
    budgets = const {};
    userName = userEmail = '';
    _month = null;
    loadError = null;
    _cz.reset();
    notifyListeners();
  }

  void _setTxns(Iterable<Txn> list) {
    _txns = list.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Puts a parsed statement in memory without saving it (used by tests).
  void load(ParsedStatement s, String name) {
    _setTxns(s.txns.map(_categorise));
    final ms = months;
    _month = ms.length == 1 ? ms.first : null;
    notifyListeners();
  }

  /// Categorises, saves and reloads. Returns how many were new.
  Future<SaveResult> importStatement(ParsedStatement s, String fileName) async {
    final categorised = [for (final t in s.txns) _categorise(t)];
    final db = _db;
    if (db == null) {
      load(s, fileName);
      return SaveResult(categorised.length, 0);
    }
    final result = await db.saveStatement(s, categorised, fileName);
    final fresh = await Future.wait([db.fetchTransactions(), db.fetchStatements()]);
    _setTxns((fresh[0] as List<Txn>).map(_categorise));
    statements = fresh[1] as List<StatementRecord>;
    _month = null;
    notifyListeners();
    return result;
  }

  Future<void> deleteStatement(StatementRecord st) async {
    final db = _db;
    if (db == null) return;
    await db.deleteStatement(st.id);
    final fresh = await Future.wait([db.fetchTransactions(), db.fetchStatements()]);
    _setTxns((fresh[0] as List<Txn>).map(_categorise));
    statements = fresh[1] as List<StatementRecord>;
    _month = null;
    notifyListeners();
  }

  Future<void> deleteAllData() async {
    await _db?.deleteAllData();
    _txns = const [];
    statements = const [];
    budgets = const {};
    _month = null;
    _cz.reset();
    notifyListeners();
  }

  Future<void> updateName(String name) async {
    await _db?.updateName(name);
    userName = name;
    notifyListeners();
  }

  // ---- Budgets --------------------------------------------------------------

  Future<void> setBudget(Cat cat, double? limit) async {
    await _db?.setBudget(cat, limit);
    final b = Map<Cat, double>.of(budgets);
    if (limit == null || limit <= 0) {
      b.remove(cat);
    } else {
      b[cat] = limit;
    }
    budgets = b;
    notifyListeners();
  }

  // ---- Categories & learning ---------------------------------------------

  SmartCategorizer _cz = categorizer;

  /// Use a different categoriser (tests).
  set categoriserForTesting(SmartCategorizer c) => _cz = c;

  SmartCategorizer get categoriser => _cz;

  Txn _categorise(Txn t) {
    final g = _cz.classify(t.text, t.name, t.amount);
    return t.withCategory(g.cat, g.sub, g.source, g.confidence);
  }

  /// Spending the app couldn't categorise.
  int get needsReview => _txns.where((t) => t.amount < 0 && t.source == CatSource.none).length;

  /// The user corrects [t] to [cat]. The model learns it, then every
  /// transaction is re-categorised so similar ones update straight away.
  /// Returns how many transactions changed category.
  Future<int> teach(Txn t, Cat cat) async {
    final lesson = _cz.learn(t.text, t.name, t.amount, cat);
    final before = _txns;
    _txns = [for (final x in _txns) _categorise(x)]; // same order, so compare by position
    final changed = <Txn>[
      for (var i = 0; i < _txns.length; i++)
        if (before[i].cat != _txns[i].cat || before[i].source != _txns[i].source) _txns[i],
    ];
    notifyListeners();
    final db = _db;
    if (db != null) {
      await db.saveLesson(lesson);
      await db.updateCategories(changed);
    }
    var moved = 0;
    for (var i = 0; i < _txns.length; i++) {
      if (before[i].cat != _txns[i].cat) moved++;
    }
    return moved;
  }

  Future<void> resetLearning() async {
    _cz.reset();
    final before = _txns;
    _txns = [for (final x in _txns) _categorise(x)];
    notifyListeners();
    final db = _db;
    if (db != null) {
      await db.clearLessons();
      await db.updateCategories([
        for (var i = 0; i < _txns.length; i++)
          if (before[i].cat != _txns[i].cat || before[i].source != _txns[i].source) _txns[i],
      ]);
    }
  }

  // ---- Period selection --------------------------------------------------

  /// Months that have transactions, newest first.
  List<DateTime> get months {
    final set = <DateTime>{for (final t in _txns) DateTime(t.date.year, t.date.month)};
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  int get monthCount => months.length;
  bool get isMultiMonth => monthCount > 1;

  bool get allMonths => _month == null;

  /// Selected month. When "All months" is selected this is the latest month.
  DateTime get month {
    if (_month != null) return _month!;
    final ms = months;
    return ms.isEmpty ? DateTime(DateTime.now().year, DateTime.now().month) : ms.first;
  }

  set month(DateTime m) {
    _month = DateTime(m.year, m.month);
    notifyListeners();
  }

  void selectAllMonths() {
    _month = null;
    notifyListeners();
  }

  /// First and last transaction dates in the statement.
  (DateTime, DateTime)? get dateRange => _txns.isEmpty ? null : (_txns.last.date, _txns.first.date);

  /// "Aug – Oct 2026" or "October 2026".
  String get periodLabel {
    if (!allMonths) return monthYear(month);
    final ms = months;
    if (ms.isEmpty) return '';
    if (ms.length == 1) return monthYear(ms.first);
    final first = ms.last, last = ms.first;
    return first.year == last.year
        ? '${monthShort(first)} – ${monthShort(last)} ${last.year}'
        : '${monthShort(first)} ${first.year} – ${monthShort(last)} ${last.year}';
  }

  /// Word used in labels: "October" or "Total".
  String get periodName => allMonths && isMultiMonth ? 'Total' : monthLong(month);

  bool _inMonth(Txn t, DateTime m) => t.date.year == m.year && t.date.month == m.month;

  List<Txn> txnsIn(DateTime m) => _txns.where((t) => _inMonth(t, m)).toList();

  /// Transactions in the selected period (one month, or everything).
  List<Txn> get monthTxns => allMonths ? _txns : txnsIn(month);

  /// "Today" for filters = the last day with data in the selected period
  /// (statements are always in the past, so the real today is usually empty).
  DateTime get refDate {
    final list = monthTxns;
    if (list.isEmpty) return DateTime(month.year, month.month + 1, 0);
    final d = list.first.date;
    return DateTime(d.year, d.month, d.day);
  }

  // ---- Totals ------------------------------------------------------------

  double _spent(Iterable<Txn> l) => l.where((t) => t.amount < 0).fold(0.0, (a, t) => a - t.amount);
  double _income(Iterable<Txn> l) => l.where((t) => t.amount > 0).fold(0.0, (a, t) => a + t.amount);

  double spentIn(DateTime m) => _spent(txnsIn(m));
  double incomeIn(DateTime m) => _income(txnsIn(m));

  /// Spending in the selected period.
  double get monthSpent => _spent(monthTxns);
  double get monthIncome => _income(monthTxns);

  /// Months the selected period spans (for averages).
  int get periodMonths => allMonths ? (monthCount == 0 ? 1 : monthCount) : 1;

  double get avgMonthlySpent => monthSpent / periodMonths;
  double get avgMonthlyIncome => monthIncome / periodMonths;

  /// Average monthly spending on [cat] across every month with data.
  double avgSpendFor(Cat cat) {
    if (monthCount == 0) return 0;
    final total = _txns.where((t) => t.cat == cat && t.amount < 0).fold(0.0, (a, t) => a - t.amount);
    return total / monthCount;
  }

  /// Month-by-month totals, oldest first.
  List<MonthSummary> get monthSummaries => [for (final m in months.reversed) _summary(m)];

  MonthSummary _summary(DateTime m) {
    final l = txnsIn(m);
    return MonthSummary(m, _spent(l), _income(l), l.length);
  }

  DateTime get _prevMonth => DateTime(month.year, month.month - 1);

  /// Whether the statement covers (almost) the whole month, so comparisons are fair.
  bool coversMonth(DateTime m) {
    if (_txns.isEmpty) return false;
    final earliest = _txns.last.date;
    final latest = _txns.first.date;
    return !earliest.isAfter(DateTime(m.year, m.month, 4)) &&
        !latest.isBefore(DateTime(m.year, m.month + 1, 0).subtract(const Duration(days: 4)));
  }

  /// Fractional change vs last month (-0.12 = 12% less). Null in "All months"
  /// or when we can't compare fairly.
  double? get changeVsPrev {
    if (allMonths) return null;
    final prev = _prevMonth;
    if (!coversMonth(prev)) return null;
    final p = spentIn(prev);
    if (p == 0) return null;
    return (monthSpent - p) / p;
  }

  /// Spending per category in the period, biggest first. Income excluded.
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
        if (allMonths) {
          // 7-day buckets across the whole statement, at most the last 13.
          final range = dateRange;
          if (range == null) return {};
          final start = DateTime(range.$1.year, range.$1.month, range.$1.day);
          final end = DateTime(range.$2.year, range.$2.month, range.$2.day);
          final weeks = end.difference(start).inDays ~/ 7 + 1;
          final out = <String, double>{};
          for (var w = (weeks - 13).clamp(0, weeks); w < weeks; w++) {
            final from = start.add(Duration(days: w * 7));
            final to = from.add(const Duration(days: 7));
            out['W${w + 1}'] = _spent(_txns.where((t) => !t.date.isBefore(from) && t.date.isBefore(to)));
          }
          return out;
        }
        final lastDay = monthTxns.isEmpty ? 0 : refDate.day;
        final out = <String, double>{};
        for (var w = 0; w * 7 + 1 <= lastDay; w++) {
          final from = w * 7 + 1, to = w * 7 + 7;
          out['Wk ${w + 1}'] = _spent(monthTxns.where((t) => t.date.day >= from && t.date.day <= to));
        }
        return out;
      default: // Monthly
        final ms = months.where((m) => !m.isAfter(month)).take(6).toList().reversed;
        return {for (final m in ms) monthShort(m): spentIn(m)};
    }
  }

  double _spentOn(DateTime d) => _spent(
      _txns.where((t) => t.date.year == d.year && t.date.month == d.month && t.date.day == d.day));

  // ---- Plain-language summary -----------------------------------------

  String get insight {
    if (!hasData) return 'Upload a statement to see where your money goes.';
    final spent = monthSpent;
    if (spent == 0) return 'No spending recorded in $periodLabel.';
    final cats = categorySpend;
    final top = cats.entries.first;
    final topShare = (top.value / spent * 100).round();
    final topLine = '${top.key.label} is your biggest category at $topShare% (${pula(top.value, decimals: false)}).';

    if (allMonths && isMultiMonth) {
      final sums = monthSummaries;
      final highest = sums.reduce((a, b) => a.spent >= b.spent ? a : b);
      return 'Over $monthCount months you spent ${pula(spent, decimals: false)}, '
          'about ${pula(avgMonthlySpent, decimals: false)} a month. '
          '${monthLong(highest.month)} was the highest at ${pula(highest.spent, decimals: false)}. $topLine';
    }

    final change = changeVsPrev;
    if (change == null) return topLine;
    final pct = (change.abs() * 100).round();
    if (pct == 0) return 'Same spending as last month. $topLine';
    return change < 0
        ? "You've spent $pct% less than last month. $topLine"
        : "You've spent $pct% more than last month. $topLine";
  }

  /// Shown after an upload so the user can check the dates were read right.
  String get loadSummary {
    final r = dateRange;
    if (r == null) return 'No transactions found';
    final n = monthCount;
    return '${_txns.length} transactions · ${shortDate(r.$1)} ${r.$1.year} – ${shortDate(r.$2)} ${r.$2.year}'
        ' ($n month${n == 1 ? '' : 's'})';
  }
}

/// Single app-wide instance — fine for Stage 1 (no login, one statement at a time).
final store = SpendingStore();
