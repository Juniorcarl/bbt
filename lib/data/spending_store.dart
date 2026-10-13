import 'package:flutter/foundation.dart';

import '../services/backend.dart';
import 'categorizer.dart';
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

/// Numbers for the money-flow diagram.
class FlowData {
  final double income;
  final double fromBalance; // spent more than came in → came from savings/balance
  final Map<Cat, double> outflows;
  final double leftOver;
  final double transfersOut;
  final double transfersIn;
  const FlowData({
    required this.income,
    required this.fromBalance,
    required this.outflows,
    required this.leftOver,
    required this.transfersOut,
    required this.transfersIn,
  });
}

/// Does opening + everything on the statement = closing?
class BooksCheck {
  final double? opening;
  final double? closing;
  final double income; // +
  final double spending; // −
  final double charges; // −
  final double transfers; // ±
  final List<Txn> flagged;
  const BooksCheck({
    this.opening,
    this.closing,
    required this.income,
    required this.spending,
    required this.charges,
    required this.transfers,
    required this.flagged,
  });

  double? get expectedClosing => opening == null ? null : opening! + income + spending + charges + transfers;

  /// Statement closing − our sum. 0 = balanced. Null when the statement has no balances.
  double? get difference {
    final e = expectedClosing;
    if (e == null || closing == null) return null;
    return ((closing! - e) * 100).roundToDouble() / 100;
  }

  bool get balanced => difference != null && difference!.abs() < 0.01;
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
        db.fetchProfile(),
      ]);
      _cz.restore(results[0] as List<Lesson>);
      final profile = results[4] as Profile;
      userName = profile.name;
      phone = profile.phone;
      confirmedOwn = profile.ownAccounts;
      rejectedOwn = profile.notOwnAccounts;
      _setTxns(_contextual(results[1] as List<Txn>));
      statements = results[2] as List<StatementRecord>;
      budgets = results[3] as Map<Cat, double>;
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
    userName = userEmail = phone = '';
    confirmedOwn = {};
    rejectedOwn = {};
    _detectedOwn = {};
    _regularPayers = {};
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
    _setTxns(_contextual(s.txns));
    final ms = months;
    _month = ms.length == 1 ? ms.first : null;
    notifyListeners();
  }

  /// Categorises, saves and reloads. Returns how many were new.
  Future<SaveResult> importStatement(ParsedStatement s, String fileName) async {
    // Categorise with everything we know, including the new statement
    // (it may reveal own accounts through transfers going both ways).
    final all = _contextual([..._txns, ...s.txns]);
    final categorised = all.sublist(_txns.length);
    final db = _db;
    if (db == null) {
      load(s, fileName);
      return SaveResult(categorised.length, 0);
    }
    final result = await db.saveStatement(s, categorised, fileName);
    final fresh = await Future.wait([db.fetchTransactions(), db.fetchStatements()]);
    _setTxns(_contextual(fresh[0] as List<Txn>));
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
    _setTxns(_contextual(fresh[0] as List<Txn>));
    statements = fresh[1] as List<StatementRecord>;
    _month = null;
    notifyListeners();
  }

  /// Removes every statement and transaction so they can be uploaded again.
  Future<void> clearStatements() async {
    await _db?.deleteAllStatements();
    _txns = const [];
    statements = const [];
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

  // ---- Own accounts, phone number, regular income ------------------------

  /// Counterparties the user confirmed are their own accounts / said are not.
  Set<String> confirmedOwn = {};
  Set<String> rejectedOwn = {};

  /// The user's phone number as they entered it ('' = not set).
  String phone = '';

  Set<String> _detectedOwn = {};
  Set<String> _regularPayers = {};

  /// Own accounts in use: confirmed plus detected (minus rejected).
  Set<String> get ownAccounts => {...confirmedOwn, ..._detectedOwn};

  /// Detected but not yet confirmed — the app asks about these.
  List<String> get pendingOwnAccounts => (_detectedOwn.difference(confirmedOwn)).toList()..sort();

  /// Number used to recognise "cash for yourself": the one the user set, else
  /// the number they most often buy airtime for.
  String get effectivePhone => phone.isNotEmpty ? normalisePhone(phone) : (suggestedPhone ?? '');
  String? suggestedPhone;

  /// Transfer counterparties that look like the user's own accounts:
  /// money goes both to and from them, or they're a short code rather than
  /// a person's name ("Transfer To Gg" vs "Transfer To John Smith").
  static Set<String> detectOwnAccounts(Iterable<Txn> txns) {
    final to = <String>{}, from = <String>{}, codes = <String>{};
    for (final t in txns) {
      final cp = counterparty(t.text);
      if (cp == null || cp.$1 != 'transfer') continue;
      (cp.$2 == 'to' ? to : from).add(cp.$3);
      if (!cp.$3.contains(' ') && cp.$3.length <= 5) codes.add(cp.$3);
    }
    return {...to.intersection(from), ...codes};
  }

  static String? _airtimePhone(Iterable<Txn> txns) {
    final counts = <String, int>{};
    for (final t in txns) {
      if (!t.text.toLowerCase().contains('airtime')) continue;
      for (final n in phoneNumbers(t.text)) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  String _payerKey(Txn t) => counterparty(t.text)?.$3 ?? SmartCategorizer.merchantKey(t.name);

  /// Income from someone who paid in two or more different months.
  bool isRegularIncome(Txn t) => t.type == TxnType.income && _regularPayers.contains(_payerKey(t));

  /// Re-reads context from [list] (own accounts, phone, regular payers) and
  /// categorises every transaction with it.
  List<Txn> _contextual(Iterable<Txn> list) {
    final l = list.toList();
    _detectedOwn = detectOwnAccounts(l).difference(rejectedOwn);
    suggestedPhone = _airtimePhone(l);
    _cz.ownAccounts = ownAccounts;
    _cz.ownPhone = effectivePhone;
    final out = [for (final t in l) _categorise(t)];
    final months = <String, Set<String>>{};
    for (final t in out) {
      if (t.type != TxnType.income) continue;
      months.putIfAbsent(_payerKey(t), () => {}).add('${t.date.year}-${t.date.month}');
    }
    _regularPayers = {for (final e in months.entries) if (e.value.length >= 2) e.key};
    return out;
  }

  Future<void> _recategoriseAndSave() async {
    final before = _txns;
    _setTxns(_contextual(_txns));
    notifyListeners();
    final byId = {for (final t in before) if (t.id != null) t.id!: t};
    await _db?.updateCategories([
      for (final t in _txns)
        if (t.id != null && (byId[t.id]?.cat != t.cat || byId[t.id]?.source != t.source)) t,
    ]);
  }

  Future<void> confirmOwnAccount(String key, bool isOwn) async {
    confirmedOwn = {...confirmedOwn}..remove(key);
    rejectedOwn = {...rejectedOwn}..remove(key);
    (isOwn ? confirmedOwn : rejectedOwn).add(key);
    await _db?.updateOwnAccounts(confirmedOwn, rejectedOwn);
    await _recategoriseAndSave();
  }

  Future<void> setPhone(String value) async {
    phone = value.trim();
    await _db?.updatePhone(phone);
    await _recategoriseAndSave();
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
    _txns = _contextual(_txns); // same order, so compare by position
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
    _txns = _contextual(_txns);
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
  // Money out = spending + bank charges. Transfers between the user's own
  // accounts are never counted as income or spending.

  double _spent(Iterable<Txn> l) => l.where((t) => t.cat.isOutflow).fold(0.0, (a, t) => a - t.amount);
  double _income(Iterable<Txn> l) => l.where((t) => t.type == TxnType.income).fold(0.0, (a, t) => a + t.amount);
  double _charges(Iterable<Txn> l) => l.where((t) => t.type == TxnType.charge).fold(0.0, (a, t) => a - t.amount);
  double _transfers(Iterable<Txn> l, {required bool out}) => l
      .where((t) => t.type == TxnType.transfer && (out ? t.amount < 0 : t.amount > 0))
      .fold(0.0, (a, t) => a + t.amount.abs());

  double spentIn(DateTime m) => _spent(txnsIn(m));
  double incomeIn(DateTime m) => _income(txnsIn(m));

  /// Money out in the selected period: spending + bank charges.
  double get monthSpent => _spent(monthTxns);
  double get monthIncome => _income(monthTxns);
  double get monthCharges => _charges(monthTxns);
  double get monthSpendingOnly => monthSpent - monthCharges;
  double get monthTransfersOut => _transfers(monthTxns, out: true);
  double get monthTransfersIn => _transfers(monthTxns, out: false);

  /// Income from payers seen in 2+ months (salary, allowance…), excluding one-offs.
  double get monthRegularIncome => monthTxns.where(isRegularIncome).fold(0.0, (a, t) => a + t.amount);

  /// Months the selected period spans (for averages).
  int get periodMonths => allMonths ? (monthCount == 0 ? 1 : monthCount) : 1;

  double get avgMonthlySpent => monthSpent / periodMonths;
  double get avgMonthlyIncome => monthIncome / periodMonths;
  double get avgMonthlyRegularIncome => monthRegularIncome / periodMonths;

  /// Average monthly spending on [cat] across every month with data.
  double avgSpendFor(Cat cat) {
    if (monthCount == 0) return 0;
    final total = _txns.where((t) => t.cat == cat).fold(0.0, (a, t) => a - t.amount);
    return total > 0 ? total / monthCount : 0;
  }

  /// Month-by-month totals, oldest first.
  List<MonthSummary> get monthSummaries => [for (final m in months.reversed) _summary(m)];

  MonthSummary _summary(DateTime m) {
    final l = txnsIn(m);
    return MonthSummary(m, _spent(l), _income(l), l.length);
  }

  // ---- Charges ----------------------------------------------------------

  /// What the per-transaction fees on the statement were for, in the period:
  /// label → (count, total). These fees are usually deducted later as one
  /// "service fees" line, which is what [monthCharges] counts — so this is a
  /// breakdown, never added on top.
  Map<String, (int, double)> get feeBreakdown {
    final m = <String, (int, double)>{};
    for (final t in monthTxns) {
      if (t.fee <= 0) continue;
      final label = switch (t.cat) {
        Cat.cash => 'Cash withdrawals',
        Cat.people => 'Sending money',
        Cat.income => 'Money received',
        Cat.transfer => 'Transfers',
        _ => 'Card & other payments',
      };
      final cur = m[label] ?? (0, 0.0);
      m[label] = (cur.$1 + 1, cur.$2 + t.fee);
    }
    final sorted = m.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return {for (final e in sorted) e.key: e.value};
  }

  double get monthAccruedFees => monthTxns.fold(0.0, (a, t) => a + t.fee);

  // ---- Flow diagram -----------------------------------------------------

  /// Money in on the left; where it went on the right.
  FlowData get flow {
    final income = monthIncome;
    final outs = categorySpend;
    final totalOut = outs.values.fold(0.0, (a, b) => a + b);
    return FlowData(
      income: income,
      fromBalance: totalOut > income ? totalOut - income : 0,
      outflows: outs,
      leftOver: income > totalOut ? income - totalOut : 0,
      transfersOut: monthTransfersOut,
      transfersIn: monthTransfersIn,
    );
  }

  // ---- Books check --------------------------------------------------------

  /// Opening + income − spending − charges ± transfers should equal the
  /// closing balance printed on the statement.
  BooksCheck? booksCheck(StatementRecord st) {
    final from = st.periodStart, to = st.periodEnd;
    if (from == null || to == null) return null;
    final l = _txns.where((t) => !t.date.isBefore(from) && !t.date.isAfter(to)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    double sumOf(TxnType type) => l.where((t) => t.type == type).fold(0.0, (a, t) => a + t.amount);
    return BooksCheck(
      opening: st.openingBalance,
      closing: st.closingBalance,
      income: sumOf(TxnType.income),
      spending: sumOf(TxnType.spending),
      charges: sumOf(TxnType.charge),
      transfers: sumOf(TxnType.transfer),
      flagged: l.where((t) => t.flagged).toList(),
    );
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

  /// Money out per category (spending + bank charges), biggest first.
  /// Income and transfers are excluded.
  Map<Cat, double> get categorySpend {
    final m = <Cat, double>{};
    for (final t in monthTxns) {
      if (!t.cat.isOutflow) continue;
      m[t.cat] = (m[t.cat] ?? 0) - t.amount;
    }
    m.removeWhere((_, v) => v <= 0.005);
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
    final income = monthIncome;
    final cats = categorySpend;
    if (cats.isEmpty) return 'No spending recorded in $periodLabel.';
    final top = cats.entries.first;
    final topShare = spent <= 0 ? 0 : (top.value / spent * 100).round();
    final topLine = '${top.key.label} is your biggest at $topShare% (${pula(top.value, decimals: false)}).';
    final balance = income - spent;
    final net = balance >= 0
        ? 'You kept ${pula(balance, decimals: false)} of the ${pula(income, decimals: false)} that came in.'
        : 'You spent ${pula(-balance, decimals: false)} more than came in.';
    final charges = monthCharges > 0 ? ' Bank charges: ${pula(monthCharges, decimals: false)}.' : '';

    if (allMonths && isMultiMonth) {
      return 'Over $monthCount months: $net About ${pula(avgMonthlySpent, decimals: false)} out a month. $topLine$charges';
    }
    final change = changeVsPrev;
    final trend = change == null || (change.abs() * 100).round() == 0
        ? ''
        : ' ${(change.abs() * 100).round()}% ${change < 0 ? 'less' : 'more'} spending than last month.';
    return '$net$trend $topLine$charges';
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
