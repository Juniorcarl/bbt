import 'dart:math' as math;

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

/// One correction the user made ("this text is Food"). Stored in the database
/// (category_lessons) and replayed into the model at sign-in.
class Lesson {
  final String text;
  final String merchantKey;
  final Cat cat;
  final double amount;
  const Lesson(this.text, this.merchantKey, this.cat, this.amount);
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
/// The model itself runs on the phone; the lessons it learns from are saved
/// to the user's account, so it keeps learning across devices and reinstalls.
class SmartCategorizer {
  SmartCategorizer() {
    _rebuild();
  }

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

  /// Replace everything learned with [lessons] (oldest first), e.g. after sign-in.
  void restore(Iterable<Lesson> lessons) {
    _examples.clear();
    _merchant.clear();
    for (final l in lessons) {
      _merchant[l.merchantKey] = l.cat;
      _examples.add((l.text, l.cat, l.amount));
    }
    while (_examples.length > _maxExamples) {
      _examples.removeAt(0);
    }
    _rebuild();
  }

  void reset() => restore(const []);

  /// The user says [text] (merchant [name], [amount]) belongs to [cat].
  /// Returns the lesson so the caller can save it.
  Lesson learn(String text, String name, double amount, Cat cat) {
    final key = merchantKey(name);
    _merchant[key] = cat;
    _examples.add((text, cat, amount));
    if (_examples.length > _maxExamples) _examples.removeAt(0);
    _train(text, amount, cat, weight: 3); // user examples count more than seeds
    _userWords.putIfAbsent(cat, () => {}).addAll(_words(text));
    return Lesson(text, key, cat, amount);
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

  /// Counterparty keys ("gg", "savings") that are the user's own accounts.
  Set<String> ownAccounts = {};

  /// The user's phone number (last 8 digits), to tell "cash for myself" from
  /// "sent to someone" on eWallet / pay-to-cell lines.
  String? ownPhone;

  CategoryGuess classify(String text, String name, double amount) {
    // 1. What the user taught for this merchant always wins.
    final remembered = _merchant[merchantKey(name)];
    if (remembered != null) return CategoryGuess(remembered, remembered.label, CatSource.user, 1);

    // 2. Transfers between the user's own accounts.
    final cp = counterparty(text);
    if (cp != null && ownAccounts.contains(cp.$3)) {
      return const CategoryGuess(Cat.transfer, 'Between your accounts', CatSource.rule, 1);
    }
    if (isTransferPhrase(text)) {
      return const CategoryGuess(Cat.transfer, 'Between your accounts', CatSource.rule, 1);
    }

    // 3. Money in.
    if (amount > 0) {
      final (cat, sub) = moneyIn(text);
      return CategoryGuess(cat, sub, CatSource.rule, 1);
    }

    // 4. Bank charges (including lines the bank posted with no description).
    if (isChargeText(text) || hasNoDescription(text)) {
      return const CategoryGuess(Cat.charges, 'Bank charges', CatSource.rule, 1);
    }

    // 5. Sending to / withdrawing via the user's own phone = cash for themselves.
    final phone = ownPhone;
    if (phone != null && phone.isNotEmpty && (isSendText(text) || isWithdrawalText(text)) &&
        phoneNumbers(text).contains(phone)) {
      return const CategoryGuess(Cat.cash, 'Cash for yourself', CatSource.rule, 1);
    }

    // 6. A transfer to someone who isn't one of the user's accounts.
    if (cp != null && cp.$1 == 'transfer' && cp.$2 == 'to') {
      return const CategoryGuess(Cat.people, 'Sent to people', CatSource.rule, 1);
    }

    final rule = ruleMatch(text);
    final model = predict(text, amount);

    // 7. A confident model guess backed by words the user taught overrides a rule.
    if (model != null && model.$2 >= 0.85 && _sharesUserWord(text, model.$1)) {
      return CategoryGuess(model.$1, model.$1.label, CatSource.model, model.$2);
    }
    // 8. Keyword rule.
    if (rule != null) return CategoryGuess(rule.$1, rule.$2, CatSource.rule, 1);
    // 9. Model guess for anything the rules don't know.
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
      if (cat.type != TxnType.spending) continue; // income, charges and transfers come from rules
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
