import 'dart:convert';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'categorizer.dart';
import 'models.dart';
import 'privacy.dart';

/// What we could read out of one bank statement.
class ParsedStatement {
  final List<Txn> txns;
  final String? bank;
  final String? accountTail; // last 4 digits
  final double? openingBalance;
  final double? closingBalance;

  /// Total fees/charges the statement itself reports in its summary, if any.
  final double? statedCharges;
  const ParsedStatement(this.txns,
      {this.bank, this.accountTail, this.openingBalance, this.closingBalance, this.statedCharges});

  /// Lines whose amount didn't match the change in running balance.
  int get flaggedCount => txns.where((t) => t.flagged).length;

  /// opening + every amount − closing. 0 when the books balance.
  double? get difference {
    if (openingBalance == null || closingBalance == null) return null;
    final sum = txns.fold(0.0, (a, t) => a + t.amount);
    return ((openingBalance! + sum - closingBalance!) * 100).roundToDouble() / 100;
  }
}

class StatementParseException implements Exception {
  final String message;
  const StatementParseException(this.message);
  @override
  String toString() => message;
}

/// Thrown for password-protected PDFs (most Botswana banks email these).
class StatementPasswordRequired extends StatementParseException {
  final bool wrongPassword;
  const StatementPasswordRequired({this.wrongPassword = false})
      : super(wrongPassword ? 'That password did not work.' : 'This statement is password-protected.');
}

/// Entry point: PDF or CSV bytes in, transactions out.
ParsedStatement parseStatement(Uint8List bytes, String fileName, {String? password}) {
  final ext = fileName.contains('.') ? fileName.toLowerCase().split('.').last : '';
  ParsedStatement result;
  if (ext == 'pdf') {
    result = parseStatementText(_pdfToText(bytes, password));
  } else if (ext == 'csv' || ext == 'txt') {
    final raw = utf8.decode(bytes, allowMalformed: true);
    result = parseCsv(raw) ?? parseStatementText(raw);
  } else {
    throw StatementParseException('Unsupported file type ".$ext". Upload a PDF or CSV statement.');
  }
  if (result.txns.isEmpty) {
    throw const StatementParseException(
        "Couldn't find any transactions in that file. If it's a scanned image PDF, download the statement from online banking instead.");
  }
  return result;
}

String _pdfToText(Uint8List bytes, String? password) {
  PdfDocument doc;
  try {
    doc = password == null ? PdfDocument(inputBytes: bytes) : PdfDocument(inputBytes: bytes, password: password);
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('password') || msg.contains('encrypt')) {
      throw StatementPasswordRequired(wrongPassword: password != null);
    }
    throw const StatementParseException("Couldn't open that PDF. Is it a valid bank statement?");
  }
  try {
    return PdfTextExtractor(doc).extractText(layoutText: true);
  } finally {
    doc.dispose();
  }
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

const _monthNums = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

final _dIso = RegExp(r'^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})(?!\d)');
final _dNum = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?![\d.,])');
final _dText = RegExp(r'^(\d{1,2})[\s\-]?([A-Za-z]{3,9})\.?(?:[\s\-,]*(\d{4}|\d{2})(?![\d.,:]))?(?![A-Za-z])');

/// Parses a date at the start of [s]. Returns the date and how many characters it used.
/// [fallbackYear] is used for "05 Oct" style dates without a year; the bool says whether the year was printed.
(DateTime, int, bool)? _dateAtStart(String s, int fallbackYear) {
  Match? m = _dIso.firstMatch(s);
  if (m != null) {
    final d = _mk(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    return d == null ? null : (d, m.end, true);
  }
  m = _dNum.firstMatch(s);
  if (m != null) {
    var a = int.parse(m[1]!), b = int.parse(m[2]!);
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    // Botswana uses day/month. Only flip if that's impossible.
    if (b > 12 && a <= 12) (a, b) = (b, a);
    final d = _mk(y, b, a);
    return d == null ? null : (d, m.end, true);
  }
  m = _dText.firstMatch(s);
  if (m != null) {
    final mon = _monthNums[m[2]!.substring(0, 3).toLowerCase()];
    if (mon == null) return null;
    var y = m[3] == null ? fallbackYear : int.parse(m[3]!);
    if (y < 100) y += 2000;
    final d = _mk(y, mon, int.parse(m[1]!));
    return d == null ? null : (d, m.end, m[3] != null);
  }
  return null;
}

DateTime? _mk(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) return null;
  final dt = DateTime(y, m, d);
  return dt.month == m ? dt : null; // rejects 31 Feb etc.
}

DateTime? parseDateLoose(String s) => _dateAtStart(s.trim(), DateTime.now().year)?.$1;

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/// e.g. "1,234.56", "-87.50", "P 420.00", "650.00 Dr", "12,000.00Cr", "87.50-"
final _amountRe = RegExp(
    r'(?<![\w.,])(-\s?)?(?:BWP|P)?\s?(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?!\d)(\s?(?:-|CR|Cr|cr|DR|Dr|dr)(?![A-Za-z]))?');

class _Amt {
  final double value; // always positive
  final int? sign; // +1 credit, -1 debit, null unknown
  final int start;
  const _Amt(this.value, this.sign, this.start);
  double get signedOrPositive => value * (sign ?? 1);
}

List<_Amt> _amounts(String s) => [
      for (final m in _amountRe.allMatches(s))
        _Amt(
          double.parse('${m[2]!.replaceAll(',', '')}.${m[3]}'),
          switch (m[4]?.trim().toLowerCase()) {
            'cr' => 1,
            'dr' || '-' => -1,
            _ => m[1] != null ? -1 : null,
          },
          m.start,
        ),
    ];

/// Lenient money parse for CSV cells: "(1,234.00)", "P 50", "-20", "100.00 Cr".
double? parseMoney(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  var neg = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    neg = true;
    s = s.substring(1, s.length - 1);
  }
  final lower = s.toLowerCase();
  if (lower.endsWith('dr')) {
    neg = true;
    s = s.substring(0, s.length - 2);
  } else if (lower.endsWith('cr')) {
    s = s.substring(0, s.length - 2);
  }
  s = s.replaceAll(RegExp(r'BWP|P|\s|,', caseSensitive: false), '');
  if (s.endsWith('-')) {
    neg = true;
    s = s.substring(0, s.length - 1);
  }
  final v = double.tryParse(s);
  if (v == null) return null;
  return neg ? -v.abs() : v;
}

// ---------------------------------------------------------------------------
// Statement metadata
// ---------------------------------------------------------------------------

const _banks = {
  'first national bank': 'First National Bank',
  'fnb': 'First National Bank',
  'absa': 'Absa',
  'barclays': 'Absa',
  'stanbic': 'Stanbic Bank',
  'standard chartered': 'Standard Chartered',
  'bank gaborone': 'Bank Gaborone',
  'bancabc': 'Access Bank',
  'access bank': 'Access Bank',
  'first capital bank': 'First Capital Bank',
  'botswana building society': 'BBS Bank',
  'bbs bank': 'BBS Bank',
  'botswana savings bank': 'Botswana Savings Bank',
};

String? _detectBank(String text) {
  final t = text.toLowerCase();
  for (final e in _banks.entries) {
    if (RegExp('\\b${RegExp.escape(e.key)}\\b').hasMatch(t)) return e.value;
  }
  return null;
}

String? _detectAccountTail(String text) {
  final m = RegExp(r'account[ \t]*(?:number|no\.?|#)?[ \t]*:?[ \t]*(\d[\d \-]{5,20}\d)', caseSensitive: false)
      .firstMatch(text);
  if (m == null) return null;
  final digits = m[1]!.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 4 ? digits.substring(digits.length - 4) : null;
}

int _likelyYear(String text) {
  final counts = <int, int>{};
  for (final m in RegExp(r'\b(20\d{2})\b').allMatches(text)) {
    final y = int.parse(m[1]!);
    counts[y] = (counts[y] ?? 0) + 1;
  }
  if (counts.isEmpty) return DateTime.now().year;
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// Earliest fully written date anywhere in the text (usually the statement
/// period start). Used to give a year to dates printed as "05 Oct".
DateTime? _earliestFullDate(String text) {
  final found = <DateTime>[];
  void consider(DateTime? d) {
    if (d != null) found.add(d);
  }

  for (final m in RegExp(r'\b(\d{1,2})[ \-/.]?([A-Za-z]{3,9})[ \-/.,]*(20\d{2})\b').allMatches(text)) {
    final mon = _monthNums[m[2]!.substring(0, 3).toLowerCase()];
    if (mon != null) consider(_mk(int.parse(m[3]!), mon, int.parse(m[1]!)));
  }
  for (final m in RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](20\d{2})\b').allMatches(text)) {
    consider(_mk(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!)));
  }
  for (final m in RegExp(r'\b(20\d{2})[/\-.](\d{1,2})[/\-.](\d{1,2})\b').allMatches(text)) {
    consider(_mk(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
  }
  if (found.isEmpty) return null;
  // Ignore old dates (date of birth, account opened…): keep the last ~13 months.
  final latest = found.reduce((a, b) => a.isAfter(b) ? a : b);
  final cutoff = latest.subtract(const Duration(days: 400));
  return found.where((d) => !d.isBefore(cutoff)).reduce((a, b) => a.isBefore(b) ? a : b);
}

const _balanceMarkers = [
  'opening balance', 'closing balance', 'balance brought forward', 'balance carried forward',
  'brought forward', 'carried forward', 'balance b/f', 'balance c/f', 'bal b/f', 'bal c/f',
];

/// Fee lines in a statement's summary block. Only figures directly after the
/// words count, so "Service Fees 190.25 Dr" → 190.25.
final _chargeSummaryRe = RegExp(
  r'\b(service fees|bank charges|cash deposit fees|cash handling fees|account fees|monthly fees|total fees|total charges)'
  r'\s*:?\s*(\d{1,3}(?:,\d{3})*\.\d{2})\s*(?:dr|cr)?',
  caseSensitive: false,
);

const _headerWords = ['date', 'description', 'details', 'balance', 'debit', 'credit', 'amount'];

// ---------------------------------------------------------------------------
// Text statements (PDF text, or CSV without a header)
// ---------------------------------------------------------------------------

class _Line {
  final DateTime date;
  final String rest;
  final List<_Amt> amts;
  const _Line(this.date, this.rest, this.amts);
}

class _Reading {
  final int amountIdx;
  final double amount; // signed
  final double? balance;
  final double fee;
  final bool reconciled;
  const _Reading(this.amountIdx, this.amount, this.balance, this.fee, this.reconciled);
}

/// Reads transactions line by line. A transaction line starts with a date and
/// ends with numbers. Which number is the amount, the running balance or a
/// fee differs between banks, so instead of trusting column positions we try
/// the possible readings and keep the one where
/// `previous balance ± amount = this balance`.
ParsedStatement parseStatementText(String text) {
  final year = _likelyYear(text);
  final periodStart = _earliestFullDate(text);
  var lines = <_Line>[];
  double? openingMarker;
  double? closingMarker;
  double? statedCharges;
  int? lastMonth;
  var yearShift = 0;

  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.replaceAll('\t', ' ').trim();
    if (line.length < 8) continue;
    final lower = line.toLowerCase();

    // Bank charges summary ("Service Fees 190.25 Dr", "Bank charges 45.00").
    if (_dateAtStart(line, year) == null) {
      for (final m in _chargeSummaryRe.allMatches(line)) {
        final v = double.parse(m[2]!.replaceAll(',', ''));
        statedCharges = (statedCharges ?? 0) + v;
      }
    }

    // Opening / closing balance lines. Summary blocks often put several
    // figures on one line ("Opening Balance 11.08 Cr  Service Fees 190.25 Dr"),
    // so take the first amount *after* the words, not the last on the line.
    final marker = _balanceMarkers.where(lower.contains).firstOrNull;
    if (marker != null) {
      final after = lower.indexOf(marker) + marker.length;
      final a = _amounts(line).where((x) => x.start >= after).toList();
      if (a.isNotEmpty) {
        final b = a.first.signedOrPositive;
        if (marker.contains('closing') || marker.contains('carried') || marker.contains('c/f')) {
          closingMarker = b;
        } else {
          openingMarker ??= b;
        }
      }
      continue;
    }

    final first = _dateAtStart(line, year + yearShift);
    if (first == null) continue;
    var date = first.$1;
    var rest = line.substring(first.$2).trim();
    // Some banks print transaction date + value date.
    final second = _dateAtStart(rest, date.year);
    if (second != null) rest = rest.substring(second.$2).trim();

    if (!first.$3 && periodStart != null) {
      // No year printed: place the date inside the statement period
      // (e.g. period 15 Nov 2025 – 14 Jan 2026 → "03 Jan" is 2026).
      date = DateTime(periodStart.year, date.month, date.day);
      if (date.isBefore(periodStart.subtract(const Duration(days: 7)))) {
        date = DateTime(date.year + 1, date.month, date.day);
      }
    } else if (!first.$3 && lastMonth != null && date.month < lastMonth - 6) {
      // Year roll-over for "28 Dec … 03 Jan" when no period is printed.
      yearShift++;
      date = DateTime(date.year + 1, date.month, date.day);
    }
    lastMonth = date.month;

    final amts = _amounts(rest);
    if (amts.isEmpty) continue;
    final descEnd = rest.substring(0, amts.first.start).toLowerCase();
    if (_headerWords.where(descEnd.contains).length >= 2) continue; // repeated header row
    lines.add(_Line(date, rest, amts));
  }

  // Newest-first statements: walk them oldest-first so balances chain.
  if (lines.length >= 2 && lines.first.date.isAfter(lines.last.date)) {
    lines = lines.reversed.toList();
  }

  final txns = <Txn>[];
  double? prev = openingMarker;
  double? firstOpening;
  for (final l in lines) {
    final r = _read(l, prev);
    if (r == null || r.amount == 0) continue;
    var desc = l.rest.substring(0, l.amts[r.amountIdx].start).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (desc.isEmpty) desc = kNoDescription;
    if (txns.isEmpty && r.balance != null) firstOpening = r.balance! - r.amount;
    txns.add(_txn(desc, l.date, r.amount, fee: r.fee, balance: r.balance, flagged: !r.reconciled));
    if (r.balance != null) prev = r.balance;
  }

  return ParsedStatement(
    txns,
    bank: _detectBank(text),
    accountTail: _detectAccountTail(text),
    openingBalance: _round(openingMarker ?? firstOpening),
    closingBalance: _round(closingMarker ?? prev),
    statedCharges: _round(statedCharges),
  );
}

double? _round(double? v) => v == null ? null : (v * 100).roundToDouble() / 100;

/// Picks which number on the line is the amount, the balance and the fee.
_Reading? _read(_Line l, double? prev) {
  final a = l.amts;
  if (a.length == 1) {
    // Amount only (no running balance on this statement).
    final t = a.first;
    final desc = l.rest.substring(0, t.start);
    final sign = t.sign ?? (looksLikeIncome(desc) ? 1 : -1);
    return _Reading(0, t.value * sign, null, 0, true);
  }

  double feeAfter(int b) => (a.length - b - 1) == 1 ? a.last.value : 0;

  // 1. Readings that make the running balance add up. Prefer the balance
  //    furthest right (fee columns sit after it, so try those next).
  if (prev != null) {
    for (var b = a.length - 1; b >= 1; b--) {
      if (a.length - b - 1 > 1) continue; // at most one fee column after the balance
      final balance = a[b].signedOrPositive;
      final amt = a[b - 1];
      final delta = balance - prev;
      for (final sign in amt.sign != null ? [amt.sign!] : const [-1, 1]) {
        if ((delta - amt.value * sign).abs() < 0.015) {
          return _Reading(b - 1, amt.value * sign, balance, feeAfter(b), true);
        }
      }
    }
  }

  // 2. No previous balance yet (first line), or nothing adds up:
  //    the balance is the last number marked Cr/Dr/−, else the last number.
  var b = -1;
  for (var i = a.length - 1; i >= 1; i--) {
    if (a[i].sign != null) {
      b = i;
      break;
    }
  }
  if (b < 1) b = a.length - 1;
  final amt = a[b - 1];
  final desc = l.rest.substring(0, amt.start);
  final sign = amt.sign ?? (looksLikeIncome(desc) ? 1 : -1);
  return _Reading(b - 1, amt.value * sign, a[b].signedOrPositive, feeAfter(b), prev == null);
}

Txn _txn(String printed, DateTime date, double amount, {double fee = 0, double? balance, bool flagged = false}) {
  // Account and card numbers never leave the parser.
  final desc = maskPrivate(printed);
  final (cat, sub) = categorize(desc, amount);
  final source = sub == 'Uncategorised' ? CatSource.none : CatSource.rule;
  final name = desc == kNoDescription ? (amount < 0 ? 'Bank fee' : 'Bank entry') : cleanName(desc);
  return Txn(name, cat, sub, date, amount,
      raw: desc, source: source, fee: fee, balance: balance, flagged: flagged);
}

// ---------------------------------------------------------------------------
// CSV with a header row
// ---------------------------------------------------------------------------

List<List<String>> _csvRows(String raw) {
  final lines = const LineSplitter().convert(raw);
  final sample = lines.take(20).join('\n');
  final delim = [',', ';', '\t'].reduce((a, b) => a.allMatches(sample).length >= b.allMatches(sample).length ? a : b);
  return [for (final l in lines) _splitCsvLine(l, delim)];
}

List<String> _splitCsvLine(String line, String delim) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == delim && !quoted) {
      out.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString().trim());
  return out;
}

/// Returns null when no recognisable header is found (caller falls back to text parsing).
ParsedStatement? parseCsv(String raw) {
  final rows = _csvRows(raw);
  int? headerAt;
  int? dateCol, descCol, amountCol, debitCol, creditCol, balanceCol;

  for (var r = 0; r < rows.length && r < 40; r++) {
    final h = rows[r].map((c) => c.toLowerCase()).toList();
    // Keys are tried in priority order; columns already taken are skipped.
    final used = <int>{};
    int? find(List<String> keys) {
      for (final k in keys) {
        for (var i = 0; i < h.length; i++) {
          if (!used.contains(i) && h[i].contains(k)) return i;
        }
      }
      return null;
    }

    final d = find(['transaction date', 'posting date', 'date']);
    if (d == null) continue;
    used.add(d);
    final valueDate = find(['value date']);
    if (valueDate != null) used.add(valueDate);
    final deb = find(['debit', 'withdraw', 'money out', 'paid out']);
    if (deb != null) used.add(deb);
    final cre = find(['credit', 'deposit', 'money in', 'paid in']);
    if (cre != null) used.add(cre);
    final amt = (deb == null && cre == null) ? find(['amount']) : null;
    if (amt != null) used.add(amt);
    if (amt == null && deb == null && cre == null) continue;
    final bal = find(['balance']);
    if (bal != null) used.add(bal);

    headerAt = r;
    dateCol = d;
    amountCol = amt;
    debitCol = deb;
    creditCol = cre;
    balanceCol = bal;
    descCol = find(['description', 'details', 'narrative', 'particulars', 'payee', 'merchant', 'reference', 'transaction']);
    break;
  }
  if (headerAt == null) return null;

  String cell(List<String> row, int? i) => (i != null && i < row.length) ? row[i] : '';

  final txns = <Txn>[];
  for (final row in rows.skip(headerAt + 1)) {
    final date = parseDateLoose(cell(row, dateCol));
    if (date == null) continue;
    final desc = cell(row, descCol).replaceAll(RegExp(r'\s+'), ' ');
    if (_balanceMarkers.any(desc.toLowerCase().contains)) continue;

    double? amount;
    if (amountCol != null) {
      amount = parseMoney(cell(row, amountCol));
    } else {
      final out = parseMoney(cell(row, debitCol))?.abs() ?? 0;
      final inn = parseMoney(cell(row, creditCol))?.abs() ?? 0;
      amount = inn - out;
    }
    if (amount == null || amount == 0) continue;
    final bal = parseMoney(cell(row, balanceCol));
    txns.add(_txn(desc.isEmpty ? 'Transaction' : desc, date, amount, balance: bal));
  }

  // Oldest first, so opening/closing come from the right ends.
  if (txns.length >= 2 && txns.first.date.isAfter(txns.last.date)) {
    final r = txns.reversed.toList();
    txns
      ..clear()
      ..addAll(r);
  }
  final first = txns.isEmpty ? null : txns.first;
  final last = txns.isEmpty ? null : txns.last;
  return ParsedStatement(
    txns,
    bank: _detectBank(raw),
    accountTail: _detectAccountTail(raw),
    openingBalance: (first != null && first.balance != null) ? _round(first.balance! - first.amount) : null,
    closingBalance: last?.balance,
  );
}
