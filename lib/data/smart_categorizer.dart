import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'categorizer.dart';
import 'models.dart';

/// Result of categorising one transaction.
class CategoryGuess {
  final Cat cat;
  final String sub;
  final CatSource source;
  final double confidence;
  const CategoryGuess(this.cat, this.sub, this.source, this.confidence);
}

/// Learns categories from the user's corrections.
///
/// Three layers, strongest first:
///  1. **Merchant memory** – "you said Mugg & Bean is Food" → always Food.
///  2. **Naive Bayes model** – learns words, spelling fragments and amount
///     ranges from every correction, so it can guess merchants it has never
///     seen ("MUGG BEAN AIRPORT", "CHOPIES MOGODITSHANE").
///  3. **Keyword rules** – the built-in list in categorizer.dart.
///
/// Everything runs and is stored on the device.
class SmartCategorizer {
  SmartCategorizer({this.persist = true}) {
    _rebuild();
  }

  /// Turn off in tests (no SharedPreferences there).
  final bool persist;

  static const _prefsKey = 'bbt.categorizer.v1';
  static const _maxExamples = 3000;

  /// Minimum model probability to use a guess (8 categories, so chance is ~0.13).
  static const minConfidence = 0.35;

  /// Softmax temperature applied to the per-feature average log-likelihood.
  /// Raw Naive Bayes is wildly overconfident because letter fragments of the
  /// same word aren't independent; averaging + this scale keeps it honest.
  static const _temperature = 5.0;

  // What the user taught us. Kept so the model can be rebuilt any time.
  final List<(String, Cat, double)> _examples = []; // (text, cat, amount)
  final Map<String, Cat> _merchant = {}; // merchantKey -> cat

  // Naive Bayes counts.
  final Map<Cat, Map<String, double>> _featCounts = {};
  final Map<Cat, double> _totals = {};
  final Set<String> _vocab = {};
  // Words the user personally linked to a category (lets the model overrule a keyword rule).
  final Map<Cat, Set<String>> _userWords = {};

  int get examplesLearned => _examples.length;
  int get merchantsLearned => _merchant.length;

  // ---- Persistence --------------------------------------------------------

  Future<void> init() async {
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _examples
        ..clear()
        ..addAll([
          for (final e in (j['examples'] as List))
            if (_catByName(e[1] as String) case final c?) (e[0] as String, c, (e[2] as num).toDouble()),
        ]);
      _merchant
        ..clear()
        ..addAll({
          for (final e in (j['merchants'] as Map<String, dynamic>).entries)
            if (_catByName(e.value as String) case final c?) e.key: c,
        });
      _rebuild();
    } catch (_) {
      // Corrupt or unavailable storage: start fresh rather than crash.
    }
  }

  Future<void> _save() async {
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'examples': [for (final (t, c, a) in _examples) [t, c.name, a]],
          'merchants': {for (final e in _merchant.entries) e.key: e.value.name},
        }),
      );
    } catch (_) {}
  }

  Future<void> reset() async {
    _examples.clear();
    _merchant.clear();
    _rebuild();
    await _save();
  }

  static Cat? _catByName(String n) {
    for (final c in Cat.values) {
      if (c.name == n) return c;
    }
    return null;
  }

  // ---- Learning -----------------------------------------------------------

  /// The user says [text] (with [amount]) belongs to [cat].
  Future<void> learn(String text, String name, double amount, Cat cat) async {
    _merchant[merchantKey(name)] = cat;
    _examples.add((text, cat, amount));
    if (_examples.length > _maxExamples) _examples.removeAt(0);
    _train(text, amount, cat, weight: 3); // user examples count more than seeds
    _userWords.putIfAbsent(cat, () => {}).addAll(_words(text));
    await _save();
  }

  void _rebuild() {
    _featCounts.clear();
    _totals.clear();
    _vocab.clear();
    _userWords.clear();
    for (final (word, cat) in ruleSeeds) {
      _train(word, null, cat, weight: 1);
    }
    for (final (text, cat, amount) in _examples) {
      _train(text, amount, cat, weight: 3);
      _userWords.putIfAbsent(cat, () => {}).addAll(_words(text));
    }
  }

  void _train(String text, double? amount, Cat cat, {required double weight}) {
    final counts = _featCounts.putIfAbsent(cat, () => {});
    for (final f in features(text, amount)) {
      counts[f] = (counts[f] ?? 0) + weight;
      _totals[cat] = (_totals[cat] ?? 0) + weight;
      _vocab.add(f);
    }
  }

  // ---- Predicting ---------------------------------------------------------

  CategoryGuess classify(String text, String name, double amount) {
    // 1. Merchant memory always wins.
    final remembered = _merchant[merchantKey(name)];
    if (remembered != null) return CategoryGuess(remembered, remembered.label, CatSource.user, 1);

    // Money in is income unless the user taught otherwise.
    if (amount > 0) {
      final (cat, sub) = categorize(text, amount);
      return CategoryGuess(cat, sub, CatSource.rule, 1);
    }

    final rule = ruleMatch(text);
    final model = predict(text, amount);

    // 2. A confident model guess backed by words the user taught overrides a rule.
    if (model != null && model.$2 >= 0.85 && _sharesUserWord(text, model.$1)) {
      return CategoryGuess(model.$1, model.$1.label, CatSource.model, model.$2);
    }
    // 3. Keyword rule.
    if (rule != null) return CategoryGuess(rule.$1, rule.$2, CatSource.rule, 1);
    // 4. Model guess for anything the rules don't know.
    if (model != null && model.$2 >= minConfidence) {
      return CategoryGuess(model.$1, model.$1.label, CatSource.model, model.$2);
    }
    return const CategoryGuess(Cat.other, 'Uncategorised', CatSource.none, 0);
  }

  /// Naive Bayes: best expense category and its probability, or null if the
  /// text shares nothing with what the model has seen.
  (Cat, double)? predict(String text, double amount) {
    final feats = features(text, amount).where(_vocab.contains).toList();
    // Need at least one real word or spelling fragment, not just the amount bucket.
    if (!feats.any((f) => !f.startsWith('a:'))) return null;

    final v = _vocab.length.toDouble();
    const alpha = 0.5;
    final scores = <Cat, double>{};
    for (final cat in _featCounts.keys) {
      if (cat == Cat.income) continue;
      final counts = _featCounts[cat]!;
      final total = _totals[cat] ?? 0;
      var s = 0.0; // uniform prior: seed lists have very different sizes
      for (final f in feats) {
        s += math.log(((counts[f] ?? 0) + alpha) / (total + alpha * v));
      }
      scores[cat] = s / feats.length * _temperature;
    }
    if (scores.isEmpty) return null;
    // Softmax → probabilities.
    final maxS = scores.values.reduce(math.max);
    final exp = {for (final e in scores.entries) e.key: math.exp(e.value - maxS)};
    final sum = exp.values.fold(0.0, (a, b) => a + b);
    final best = exp.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (!_hasEvidence(text, best.key)) return null;
    return (best.key, best.value / sum);
  }

  /// The winning category must actually know this text: a whole word it has
  /// seen, or a word whose letter fragments mostly match (a typo/variant).
  bool _hasEvidence(String text, Cat cat) {
    final counts = _featCounts[cat]!;
    for (final w in _words(text)) {
      if (counts.containsKey('w:$w')) return true;
      if (w.length >= 4) {
        final g = _grams(w);
        if (g.where(counts.containsKey).length / g.length >= 0.7) return true;
      }
    }
    return false;
  }

  bool _sharesUserWord(String text, Cat cat) {
    final taught = _userWords[cat];
    if (taught == null || taught.isEmpty) return false;
    return _words(text).any(taught.contains);
  }

  // ---- Features -------------------------------------------------------------

  static const _noise = {
    'pos', 'purchase', 'card', 'debit', 'credit', 'payment', 'eft', 'order', 'ref', 'trf',
    'the', 'and', 'bw', 'gaborone', 'gab', 'bwp', 'pty', 'ltd', 'mall', 'branch',
  };

  static Set<String> _words(String text) => {
        for (final w in text.toLowerCase().split(RegExp(r'[^a-z]+')))
          if (w.length >= 2 && !_noise.contains(w)) w,
      };

  /// Words, 3-letter fragments of each word (so typos and variants still
  /// match), and a rough amount size.
  static List<String> features(String text, double? amount) {
    final out = <String>[];
    for (final w in _words(text)) {
      out.add('w:$w');
      out.addAll(_grams(w));
    }
    if (amount != null && amount != 0) {
      final bucket = (math.log(amount.abs()) / math.ln2).floor().clamp(0, 16);
      out.add('a:$bucket');
    }
    return out;
  }

  static List<String> _grams(String w) {
    final padded = '^$w\$';
    return [for (var i = 0; i + 3 <= padded.length; i++) 'g:${padded.substring(i, i + 3)}'];
  }

  /// "Mugg & Bean Riverwalk" and "MUGG & BEAN RIVERWALK 1234" → same key.
  static String merchantKey(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), ' ').trim();
}

/// App-wide instance.
final categorizer = SmartCategorizer();
