import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

// ---------------------------------------------------------------------------
// The merchant knowledge base: categories, known businesses, the spellings a
// bank might print for them, and "meaning words" like eats -> eating out.
//
// It lives in Supabase (so it can grow without an app release), is copied to
// a JSON file on the phone, and is read from memory when matching. Matching
// never calls the network, so it is instant, works offline, and nothing the
// user spends is sent anywhere.
//
// Field names below match the Supabase column names on purpose, so the same
// fromJson reads both a server row and the local cache.
// ---------------------------------------------------------------------------

/// One row of the `categories` table. Top-level rows have no parent.
class CategoryNode {
  final String id;
  final String? parentId;
  final String label;
  final int sort;
  const CategoryNode(this.id, this.parentId, this.label, this.sort);

  factory CategoryNode.fromJson(Map<String, dynamic> r) => CategoryNode(
        r['id'] as String,
        r['parent_id'] as String?,
        r['label'] as String,
        (r['sort'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'id': id, 'parent_id': parentId, 'label': label, 'sort': sort};
}

/// One row of the `merchants` table.
class Merchant {
  final String id;
  final String name;
  final String categoryId;
  final bool isChain;
  final String? town;
  const Merchant(this.id, this.name, this.categoryId, this.isChain, this.town);

  factory Merchant.fromJson(Map<String, dynamic> r) => Merchant(
        r['id'] as String,
        r['name'] as String,
        r['category_id'] as String,
        r['is_chain'] as bool? ?? false,
        r['town'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'category_id': categoryId, 'is_chain': isChain, 'town': town};
}

/// One row of the `merchant_aliases` table. [alias] is already normalised
/// (lower-case letters and single spaces) by the database helper.
class MerchantAlias {
  final String alias;
  final String merchantId;
  const MerchantAlias(this.alias, this.merchantId);

  factory MerchantAlias.fromJson(Map<String, dynamic> r) =>
      MerchantAlias(r['alias'] as String, r['merchant_id'] as String);

  Map<String, dynamic> toJson() => {'alias': alias, 'merchant_id': merchantId};
}

/// One row of the `cue_words` table: a word that hints at a category.
class Cue {
  final String word;
  final String categoryId;
  final double strength; // 0..1
  const Cue(this.word, this.categoryId, this.strength);

  factory Cue.fromJson(Map<String, dynamic> r) =>
      Cue(r['word'] as String, r['category_id'] as String, (r['strength'] as num).toDouble());

  Map<String, dynamic> toJson() => {'word': word, 'category_id': categoryId, 'strength': strength};
}

/// What a sync did. Syncing never throws; check [error].
class SyncResult {
  final bool skipped; // nothing was due
  final bool full; // everything was re-downloaded
  final int rows; // rows received
  final String? error;
  const SyncResult({this.skipped = false, this.full = false, this.rows = 0, this.error});
  bool get ok => error == null;
}

class MerchantStore {
  MerchantStore._();
  static final MerchantStore instance = MerchantStore._();

  static const _fileName = 'merchant_cache.json';
  static const _formatVersion = 1;

  /// How often the app asks the server whether anything changed.
  static const _checkEvery = Duration(hours: 24);

  /// The server only sends verified merchants, and a merchant that is later
  /// rejected or removed is never announced. A full re-download now and then
  /// (and on a manual refresh) cleans those out of the phone's copy.
  static const _fullResyncEvery = Duration(days: 30);

  static const _page = 1000; // Supabase returns at most 1000 rows per request

  // ---- In-memory data (read by the matcher) ----------------------------------

  final Map<String, CategoryNode> categories = {};
  final Map<String, Merchant> merchants = {};
  final Map<String, Cue> cues = {}; // keyed by word
  final Map<String, MerchantAlias> _aliases = {}; // keyed by 'alias|merchantId'

  Iterable<MerchantAlias> get aliases => _aliases.values;

  bool get isEmpty => merchants.isEmpty && cues.isEmpty;

  /// Incremented every time the data changes, so the matcher knows to rebuild
  /// its indexes.
  int version = 0;

  String get summary =>
      '${categories.length} categories, ${merchants.length} merchants, ${_aliases.length} aliases, ${cues.length} cue words';

  // ---- Sync bookkeeping ---------------------------------------------------------

  final Map<String, String> _cursors = {}; // table -> newest updated_at received
  DateTime? _lastChecked;
  DateTime? _lastFull;
  bool _loaded = false;
  bool _syncing = false;

  SupabaseClient get _db => Supabase.instance.client;

  /// Maps a Supabase category id ('alcohol') to the app's category and the
  /// sub-label to show (Cat.entertainment, 'Alcohol'). Returns null when the
  /// id is unknown, or when the database has a top-level category this version
  /// of the app doesn't have yet (so an older app never crashes on newer data).
  (Cat, String)? resolve(String categoryId) {
    final node = categories[categoryId];
    if (node == null) return null;
    final parentId = node.parentId;
    if (parentId == null) {
      final cat = catFromName(node.id);
      return cat == null ? null : (cat, cat.label);
    }
    final cat = catFromName(parentId);
    return cat == null ? null : (cat, node.label);
  }

  // ---- Loading from the phone ------------------------------------------------------

  /// Reads the local copy. Safe to call more than once. Call at app start,
  /// before the first sync.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['v'] != _formatVersion) return;

      List<Map<String, dynamic>> rows(String key) =>
          [for (final r in (j[key] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];

      for (final r in rows('categories')) {
        final c = CategoryNode.fromJson(r);
        categories[c.id] = c;
      }
      for (final r in rows('merchants')) {
        final m = Merchant.fromJson(r);
        merchants[m.id] = m;
      }
      for (final r in rows('aliases')) {
        final a = MerchantAlias.fromJson(r);
        _aliases[_aliasKey(a)] = a;
      }
      for (final r in rows('cues')) {
        final c = Cue.fromJson(r);
        cues[c.word] = c;
      }
      _cursors
        ..clear()
        ..addAll({for (final e in ((j['cursors'] as Map?) ?? const {}).entries) e.key as String: e.value as String});
      _lastChecked = DateTime.tryParse(j['lastChecked'] as String? ?? '');
      _lastFull = DateTime.tryParse(j['lastFull'] as String? ?? '');
      version++;
    } catch (e) {
      // A damaged cache is not worth crashing for: start empty and re-download.
      debugPrint('MerchantStore: cache unreadable, starting empty ($e)');
      _clearAll();
    }
  }

  // ---- Syncing from Supabase ---------------------------------------------------------

  /// Downloads whatever changed on the server since last time. By default this
  /// only runs about once a day. [force] (a manual refresh) re-downloads
  /// everything. Never throws.
  Future<SyncResult> sync({bool force = false}) async {
    await load();
    if (_syncing) return const SyncResult(skipped: true);
    final now = DateTime.now();
    final due = force ||
        isEmpty ||
        _lastChecked == null ||
        now.difference(_lastChecked!) >= _checkEvery;
    if (!due) return const SyncResult(skipped: true);

    _syncing = true;
    try {
      final full = force || isEmpty || _lastFull == null || now.difference(_lastFull!) >= _fullResyncEvery;
      String? cursorFor(String table) => full ? null : _cursors[table];

      // Download everything first and change nothing until all four tables
      // arrived, so a dropped connection can never leave a half-updated copy.
      final results = await Future.wait([
        _fetchAll('categories', 'id, parent_id, label, sort, updated_at', cursorFor('categories'), ['updated_at', 'id']),
        _fetchAll('merchants', 'id, name, category_id, is_chain, town, updated_at', cursorFor('merchants'), ['updated_at', 'id']),
        _fetchAll('merchant_aliases', 'alias, merchant_id, updated_at', cursorFor('merchant_aliases'), ['updated_at', 'alias', 'merchant_id']),
        _fetchAll('cue_words', 'word, category_id, strength, updated_at', cursorFor('cue_words'), ['updated_at', 'word']),
      ]);
      final (catRows, merRows, aliasRows, cueRows) = (results[0], results[1], results[2], results[3]);

      if (full) _clearAll();
      for (final r in catRows) {
        final c = CategoryNode.fromJson(r);
        categories[c.id] = c;
      }
      for (final r in merRows) {
        final m = Merchant.fromJson(r);
        merchants[m.id] = m;
      }
      for (final r in aliasRows) {
        final a = MerchantAlias.fromJson(r);
        _aliases[_aliasKey(a)] = a;
      }
      for (final r in cueRows) {
        final c = Cue.fromJson(r);
        cues[c.word] = c;
      }
      _advance('categories', catRows);
      _advance('merchants', merRows);
      _advance('merchant_aliases', aliasRows);
      _advance('cue_words', cueRows);

      _lastChecked = now;
      if (full) _lastFull = now;
      version++;
      await _save();

      final total = catRows.length + merRows.length + aliasRows.length + cueRows.length;
      debugPrint('MerchantStore: ${full ? 'full' : 'delta'} sync, $total rows. Now: $summary');
      return SyncResult(full: full, rows: total);
    } catch (e) {
      debugPrint('MerchantStore: sync failed ($e)');
      return SyncResult(error: e.toString());
    } finally {
      _syncing = false;
    }
  }

  /// Every row of [table] newer than [cursor], fetched in pages.
  Future<List<Map<String, dynamic>>> _fetchAll(
      String table, String columns, String? cursor, List<String> order) async {
    final out = <Map<String, dynamic>>[];
    for (var from = 0;; from += _page) {
      var q = _db.from(table).select(columns);
      if (cursor != null) q = q.gt('updated_at', cursor);
      var t = q.order(order.first);
      for (final o in order.skip(1)) {
        t = t.order(o);
      }
      final rows = await t.range(from, from + _page - 1);
      out.addAll(rows);
      if (rows.length < _page) break;
    }
    return out;
  }

  /// Remembers the newest server timestamp seen, so the next sync asks only for
  /// anything after it. Uses the server's clock, not the phone's.
  void _advance(String table, List<Map<String, dynamic>> rows) {
    DateTime? newest = DateTime.tryParse(_cursors[table] ?? '');
    for (final r in rows) {
      final t = DateTime.tryParse(r['updated_at'] as String? ?? '');
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    if (newest != null) _cursors[table] = newest.toUtc().toIso8601String();
  }

  static String _aliasKey(MerchantAlias a) => '${a.alias}|${a.merchantId}';

  void _clearAll() {
    categories.clear();
    merchants.clear();
    cues.clear();
    _aliases.clear();
    _cursors.clear();
    _lastChecked = null;
    _lastFull = null;
  }

  // ---- The file on the phone ----------------------------------------------------------

  /// Null on the web, where there is no file system (the data is then simply
  /// downloaded again each time).
  Future<File?> _file() async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      if (f == null) return;
      final json = jsonEncode({
        'v': _formatVersion,
        'cursors': _cursors,
        'lastChecked': _lastChecked?.toIso8601String(),
        'lastFull': _lastFull?.toIso8601String(),
        'categories': [for (final c in categories.values) c.toJson()],
        'merchants': [for (final m in merchants.values) m.toJson()],
        'aliases': [for (final a in _aliases.values) a.toJson()],
        'cues': [for (final c in cues.values) c.toJson()],
      });
      // Write beside the real file, then swap, so a crash mid-write can't
      // leave a half-written cache.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('MerchantStore: could not save cache ($e)');
    }
  }
}