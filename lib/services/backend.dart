import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import '../data/smart_categorizer.dart';
import '../data/statement_parser.dart';

/// A statement the user uploaded (metadata only; the file is never stored).
class StatementRecord {
  final String id;
  final String fileName;
  final String? bank;
  final String? accountTail;
  final double? openingBalance;
  final double? closingBalance;
  final int flaggedLines;
  final double? statedCharges;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int txnCount;
  final DateTime uploadedAt;

  const StatementRecord({
    required this.id,
    required this.fileName,
    this.bank,
    this.accountTail,
    this.openingBalance,
    this.closingBalance,
    this.flaggedLines = 0,
    this.statedCharges,
    this.periodStart,
    this.periodEnd,
    required this.txnCount,
    required this.uploadedAt,
  });

  factory StatementRecord.fromRow(Map<String, dynamic> r) => StatementRecord(
        id: r['id'] as String,
        fileName: r['file_name'] as String,
        bank: r['bank'] as String?,
        accountTail: r['account_tail'] as String?,
        openingBalance: (r['opening_balance'] as num?)?.toDouble(),
        closingBalance: (r['closing_balance'] as num?)?.toDouble(),
        flaggedLines: (r['flagged_lines'] as num?)?.toInt() ?? 0,
        statedCharges: (r['stated_charges'] as num?)?.toDouble(),
        periodStart: r['period_start'] == null ? null : DateTime.parse(r['period_start'] as String),
        periodEnd: r['period_end'] == null ? null : DateTime.parse(r['period_end'] as String),
        txnCount: (r['txn_count'] as num?)?.toInt() ?? 0,
        uploadedAt: DateTime.parse(r['uploaded_at'] as String).toLocal(),
      );
}

/// The user's profile row.
class Profile {
  final String name;
  final String phone;
  final Set<String> ownAccounts;
  final Set<String> notOwnAccounts;
  const Profile(this.name, this.phone, this.ownAccounts, this.notOwnAccounts);
}

/// Result of saving a statement.
class SaveResult {
  final int added;
  final int alreadySaved;
  const SaveResult(this.added, this.alreadySaved);
}

/// Everything that talks to Supabase. Row Level Security on the server makes
/// sure each call only ever touches the signed-in user's rows.
class Backend {
  SupabaseClient get _db => Supabase.instance.client;
  String get _uid => _db.auth.currentUser!.id;

  User? get user => _db.auth.currentUser;

  // ---- Profile ------------------------------------------------------------

  Future<Profile> fetchProfile() async {
    final row = await _db
        .from('profiles')
        .select('full_name, phone, own_accounts, not_own_accounts')
        .eq('id', _uid)
        .maybeSingle();
    var name = (row?['full_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) name = (user?.userMetadata?['full_name'] as String?)?.trim() ?? '';
    Set<String> set(Object? v) => {for (final x in (v as List?) ?? const []) x.toString()};
    return Profile(
      name,
      (row?['phone'] as String?) ?? '',
      set(row?['own_accounts']),
      set(row?['not_own_accounts']),
    );
  }

  Future<void> updatePhone(String phone) async {
    await _db.from('profiles').update({'phone': phone}).eq('id', _uid);
  }

  Future<void> updateOwnAccounts(Set<String> own, Set<String> notOwn) async {
    await _db.from('profiles').update({
      'own_accounts': own.toList()..sort(),
      'not_own_accounts': notOwn.toList()..sort(),
    }).eq('id', _uid);
    await log('own_accounts_updated', {'own': own.length, 'not_own': notOwn.length});
  }

  Future<void> updateName(String name) async {
    await _db.from('profiles').upsert({'id': _uid, 'full_name': name});
    await _db.auth.updateUser(UserAttributes(data: {'full_name': name}));
  }

  // ---- Transactions -------------------------------------------------------

  /// All of the user's transactions, newest first. Fetched in pages because
  /// Supabase returns at most 1000 rows per request.
  Future<List<Txn>> fetchTransactions() async {
    const page = 1000;
    final out = <Txn>[];
    for (var from = 0;; from += page) {
      final rows = await _db
          .from('transactions')
          .select('id, date, name, raw, amount, category, sub, source, confidence, fee, balance, flagged')
          .eq('user_id', _uid)
          .order('date', ascending: false)
          .order('id')
          .range(from, from + page - 1);
      for (final r in rows) {
        out.add(Txn(
          r['name'] as String,
          catFromName(r['category'] as String) ?? Cat.other,
          r['sub'] as String? ?? '',
          DateTime.parse(r['date'] as String),
          (r['amount'] as num).toDouble(),
          id: r['id'] as String,
          raw: r['raw'] as String? ?? '',
          source: CatSource.values.asNameMap()[r['source']] ?? CatSource.rule,
          confidence: (r['confidence'] as num?)?.toDouble() ?? 1,
          fee: (r['fee'] as num?)?.toDouble() ?? 0,
          balance: (r['balance'] as num?)?.toDouble(),
          flagged: r['flagged'] as bool? ?? false,
        ));
      }
      if (rows.length < page) break;
    }
    return out;
  }

  /// Saves a statement and its (already categorised) transactions.
  /// Transactions already saved from an earlier, overlapping statement are skipped.
  Future<SaveResult> saveStatement(ParsedStatement s, List<Txn> txns, String fileName) async {
    final dates = txns.map((t) => t.date).toList()..sort();
    final stmt = await _db
        .from('statements')
        .insert({
          'user_id': _uid,
          'file_name': fileName,
          'bank': s.bank,
          'account_tail': s.accountTail,
          'opening_balance': s.openingBalance,
          'closing_balance': s.closingBalance,
          'flagged_lines': s.flaggedCount,
          'stated_charges': s.statedCharges,
          'period_start': dates.isEmpty ? null : _day(dates.first),
          'period_end': dates.isEmpty ? null : _day(dates.last),
          'txn_count': txns.length,
        })
        .select('id')
        .single();
    final statementId = stmt['id'] as String;

    // Fingerprint: same date + description + amount, numbered if it repeats
    // (two identical coffees on one day are two transactions).
    final seen = <String, int>{};
    final rows = <Map<String, dynamic>>[];
    for (final t in txns) {
      final base = '${_day(t.date)}|${t.text.trim().toUpperCase()}|${t.amount.toStringAsFixed(2)}';
      final n = seen[base] = (seen[base] ?? 0) + 1;
      rows.add({
        'user_id': _uid,
        'statement_id': statementId,
        'date': _day(t.date),
        'name': t.name,
        'raw': t.raw,
        'amount': t.amount,
        'category': t.cat.name,
        'sub': t.sub,
        'source': t.source.name,
        'confidence': t.confidence,
        'fee': t.fee,
        'balance': t.balance,
        'flagged': t.flagged,
        'fingerprint': '$base|$n',
      });
    }

    var added = 0;
    for (var i = 0; i < rows.length; i += 500) {
      final chunk = rows.sublist(i, i + 500 > rows.length ? rows.length : i + 500);
      final inserted = await _db
          .from('transactions')
          .upsert(chunk, onConflict: 'user_id,fingerprint', ignoreDuplicates: true)
          .select('id');
      added += inserted.length;
    }
    await _db.from('statements').update({'txn_count': added}).eq('id', statementId);
    await log('statement_uploaded', {
      'bank': s.bank,
      'read': txns.length,
      'added': added,
      'flagged': s.flaggedCount,
      'difference': s.difference,
      'from': dates.isEmpty ? null : _day(dates.first),
      'to': dates.isEmpty ? null : _day(dates.last),
    });
    return SaveResult(added, txns.length - added);
  }

  /// Saves new categories for transactions that changed.
  Future<void> updateCategories(Iterable<Txn> changed) async {
    await Future.wait([
      for (final t in changed)
        if (t.id != null)
          _db.from('transactions').update({
            'category': t.cat.name,
            'sub': t.sub,
            'source': t.source.name,
            'confidence': t.confidence,
          }).eq('id', t.id!),
    ]);
  }

  // ---- Statements ---------------------------------------------------------

  Future<List<StatementRecord>> fetchStatements() async {
    final rows = await _db.from('statements').select().eq('user_id', _uid).order('uploaded_at', ascending: false);
    return [for (final r in rows) StatementRecord.fromRow(r)];
  }

  /// Deletes a statement and the transactions that came from it.
  Future<void> deleteStatement(String id) async {
    await _db.from('statements').delete().eq('id', id);
    await log('statement_deleted', {'id': id});
  }

  // ---- Learning -----------------------------------------------------------

  Future<List<Lesson>> fetchLessons() async {
    final rows = await _db
        .from('category_lessons')
        .select('text, merchant_key, category, amount')
        .eq('user_id', _uid)
        .order('created_at');
    return [
      for (final r in rows)
        if (catFromName(r['category'] as String) case final c?)
          Lesson(r['text'] as String, r['merchant_key'] as String, c, (r['amount'] as num).toDouble()),
    ];
  }

  Future<void> saveLesson(Lesson l) async {
    await _db.from('category_lessons').insert({
      'user_id': _uid,
      'text': l.text,
      'merchant_key': l.merchantKey,
      'category': l.cat.name,
      'amount': l.amount,
    });
    await log('category_corrected', {'merchant': l.merchantKey, 'category': l.cat.name});
  }

  Future<void> clearLessons() async {
    await _db.from('category_lessons').delete().eq('user_id', _uid);
    await log('learning_reset');
  }

  // ---- Budgets ------------------------------------------------------------

  Future<Map<Cat, double>> fetchBudgets() async {
    final rows = await _db.from('budgets').select('category, monthly_limit').eq('user_id', _uid);
    return {
      for (final r in rows)
        if (catFromName(r['category'] as String) case final c?) c: (r['monthly_limit'] as num).toDouble(),
    };
  }

  Future<void> setBudget(Cat cat, double? limit) async {
    if (limit == null || limit <= 0) {
      await _db.from('budgets').delete().eq('user_id', _uid).eq('category', cat.name);
    } else {
      await _db.from('budgets').upsert({
        'user_id': _uid,
        'category': cat.name,
        'monthly_limit': limit,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  // ---- Account ------------------------------------------------------------

  /// Deletes every statement and transaction (keeps budgets and learning),
  /// so statements can be uploaded and read again.
  Future<void> deleteAllStatements() async {
    await _db.from('transactions').delete().eq('user_id', _uid);
    await _db.from('statements').delete().eq('user_id', _uid);
    await log('statements_cleared');
  }

  /// Deletes all of the user's data (statements, transactions, lessons, budgets).
  /// The login itself stays; deleting it needs the dashboard (service role).
  Future<void> deleteAllData() async {
    await _db.from('transactions').delete().eq('user_id', _uid);
    await _db.from('statements').delete().eq('user_id', _uid);
    await _db.from('category_lessons').delete().eq('user_id', _uid);
    await _db.from('budgets').delete().eq('user_id', _uid);
    await log('data_deleted');
  }

  // ---- Activity log -------------------------------------------------------

  /// Best effort: a failed log write never breaks the app.
  Future<void> log(String type, [Map<String, dynamic> detail = const {}]) async {
    try {
      await _db.from('events').insert({'user_id': _uid, 'type': type, 'detail': detail});
    } catch (_) {}
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
