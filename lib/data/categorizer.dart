import 'models.dart';

// ---------------------------------------------------------------------------
// Keyword rules. Checked top to bottom, first match wins. Keywords match whole
// words, case-insensitive. They are deliberately bank-neutral: add wording
// from any bank here, never logic that only one statement layout needs.
// ---------------------------------------------------------------------------

/// Wording that always means "between my own accounts", at any bank.
const _transferPhrases = [
  'own account', 'own acc', 'inter account', 'interaccount', 'inter-account', 'internal transfer',
  'between accounts', 'to savings', 'from savings', 'savings transfer', 'transfer to savings',
  'sweep', 'iat', 'self transfer',
];

/// Bank charges. Checked only for money going out.
const _chargeWords = [
  'service fee', 'service fees', 'monthly account fee', 'account fee', 'monthly fee', 'admin fee',
  'sms fee', 'notification fee', 'ledger fee', 'bank charge', 'bank charges', 'charges', 'commission',
  'fee', 'fees', 'levy', 'interest charged', 'debit interest', 'overdraft interest', 'penalty',
];

const _rules = <(List<String>, Cat, String)>[
  // Cash
  (['atm', 'cash withdrawal', 'cash advance', 'cash advanc', 'cardless', 'withdrawal'], Cat.cash, 'Cash withdrawal'),
  (['orange money', 'myzaka', 'my zaka', 'smega', 'mascom myzaka'], Cat.cash, 'Mobile money'),

  // Money sent to other people (eWallet, pay-to-cell, payments to someone)
  (['p2c', 'send money', 'sendmoney', 'cashsend', 'cash send', 'ewallet', 'e-wallet', 'payment to', 'pay to', 'money transfer'], Cat.people, 'Sent to people'),

  // Bills & utilities
  (['mascom', 'orange', 'btc', 'bemobile', 'be mobile', 'airtime', 'data bundle', 'bundle'], Cat.bills, 'Airtime & data'),
  (['bpc', 'botswana power', 'electricity', 'prepaid elec', 'power prepaid'], Cat.bills, 'Electricity'),
  (['wuc', 'water utilities', 'water'], Cat.bills, 'Water'),
  (['dstv', 'multichoice', 'gotv', 'internet', 'fibre', 'liquid', 'starlink'], Cat.bills, 'TV & internet'),
  (['rent', 'rental', 'landlord'], Cat.bills, 'Rent'),
  (['insurance', 'botswana life', 'bona life', 'hollard', 'metropolitan', 'old mutual', 'funeral'], Cat.bills, 'Insurance'),
  (['loan', 'repayment', 'letshego', 'bayport', 'instalment'], Cat.bills, 'Loan repayment'),

  // Health (before food: pharmacies sell groceries too)
  (['pharmacy', 'pharma', 'chemist', 'clinic', 'hospital', 'dental', 'dentist', 'doctor', 'medical', 'dischem', 'dis-chem', 'clicks', 'bokamoso', 'sidilega', 'optometrist', 'bomaid', 'pula medical', 'bpomas'], Cat.health, 'Health'),

  // Food
  (['choppies', 'spar', 'superspar', 'sefalana', 'pick n pay', 'picknpay', 'pnp', 'shoprite', 'checkers', 'woolworths', 'food lovers', 'usave', 'u-save', 'square mart', 'trans supermarket', 'liquorama', 'grocer', 'supermarket', 'hyper', 'butchery', 'bakery'], Cat.food, 'Groceries'),
  (['kfc', 'nandos', "nando's", 'debonairs', 'chicken licken', 'steers', 'wimpy', 'mugg', 'bean', 'hungry lion', 'mcdonalds', 'pizza', 'burger', 'restaurant', 'cafe', 'coffee', 'eats', 'mr delivery', 'bolt food', 'takeaway'], Cat.food, 'Eating out'),

  // Transport
  (['uber', 'bolt', 'yango', 'taxi', 'cab', 'combi'], Cat.transport, 'Rides'),
  (['puma', 'engen', 'shell', 'totalenergies', 'total energies', 'caltex', 'astron', 'sasol', 'fuel', 'filling station', 'service station', 'petrol', 'diesel'], Cat.transport, 'Fuel'),
  (['air botswana', 'airlink', 'flight', 'bus', 'parking', 'car wash'], Cat.transport, 'Travel'),

  // Entertainment & subscriptions
  (['spotify', 'netflix', 'showmax', 'apple com', 'apple.com', 'itunes', 'google play', 'youtube', 'disney', 'prime video', 'chatgpt', 'openai'], Cat.entertainment, 'Subscription'),
  (['cinema', 'nu metro', 'ster kinekor', 'playstation', 'xbox', 'steam', 'betway', 'betpawa', 'lotto', 'casino', 'club', 'lounge', 'tavern', 'bar'], Cat.entertainment, 'Going out'),

  // Shopping
  (['zara', 'mr price', 'mrp', 'edgars', 'jet', 'pep', 'ackermans', 'truworths', 'foschini', 'markham', 'h&m', 'cotton on', 'woolies', 'identity', 'sportscene', 'totalsports', 'shein', 'temu'], Cat.shopping, 'Clothing'),
  (['game', 'builders', 'cashbuild', 'hifi corp', 'incredible connection', 'takealot', 'amazon', 'aliexpress', 'furniture', 'hardware', 'pennypinchers'], Cat.shopping, 'Shopping'),
];

const _incomeKeywords = [
  'salary', 'salaries', 'payroll', 'wages', 'stipend', 'allowance', 'dividend', 'interest received',
  'credit interest', 'refund', 'reversal', 'deposit', 'cash deposit', 'received', 'inward', 'incoming',
  'payment from', 'pmnt from', 'pmt from',
];

String _wordPattern(String k) => '(?<![A-Za-z0-9])${RegExp.escape(k)}(?![A-Za-z0-9])';
RegExp _anyOf(List<String> words) => RegExp(words.map(_wordPattern).join('|'), caseSensitive: false);

final _ruleRes = [for (final r in _rules) (_anyOf(r.$1), r.$2, r.$3)];
final _incomeRe = _anyOf(_incomeKeywords);
final _transferRe = _anyOf(_transferPhrases);
final _chargeRe = _anyOf(_chargeWords);
final _withdrawalRe = _anyOf(['atm', 'cash withdrawal', 'cash advance', 'cash advanc', 'cardless', 'withdrawal']);
final _sendRe = _anyOf(['p2c', 'send money', 'sendmoney', 'cashsend', 'cash send', 'ewallet', 'e-wallet', 'payment to', 'pay to', 'money transfer']);

/// True when the description reads like money coming in.
bool looksLikeIncome(String desc) => _incomeRe.hasMatch(desc);

/// Wording that always means a transfer between the user's own accounts.
bool isTransferPhrase(String desc) => _transferRe.hasMatch(desc);

/// Bank fee / charge wording.
bool isChargeText(String desc) => _chargeRe.hasMatch(desc);

/// Sending money to someone (eWallet, pay-to-cell, payment to …).
bool isSendText(String desc) => _sendRe.hasMatch(desc);

/// Taking cash out.
bool isWithdrawalText(String desc) => _withdrawalRe.hasMatch(desc);

/// Sub-label for money coming in.
String incomeKind(String desc) {
  final d = desc.toLowerCase();
  if (d.contains('salary') || d.contains('payroll') || d.contains('wages')) return 'Salary';
  if (d.contains('refund') || d.contains('reversal')) return 'Refund';
  if (d.contains('interest')) return 'Interest';
  if (d.contains('deposit')) return 'Deposit';
  if (RegExp(r'\b(payment|pmnt|pmt|transfer|trf)\s+from\b|\breceived\b', caseSensitive: false).hasMatch(desc)) {
    return 'From people';
  }
  return 'Money in';
}

/// Money in is either *income* (salary, allowance, bursary, interest, refunds)
/// or money *received from people* (payments from someone, cash someone
/// deposited for you). Both count as money in; only income is "regular income".
(Cat, String) moneyIn(String desc) {
  final kind = incomeKind(desc);
  return switch (kind) {
    'From people' => (Cat.received, 'From people'),
    'Deposit' => (Cat.received, 'Cash deposit'),
    _ => (Cat.income, kind),
  };
}

/// A line the bank printed with no description. Banks post their own entries
/// (service fees, account fees) this way, so a debit like this is a charge.
bool hasNoDescription(String desc) => desc.trim().isEmpty || desc == kNoDescription;

/// Context-free category, used when a statement is first read. The app then
/// re-categorises with more context (own accounts, phone number, what the
/// user taught) in SmartCategorizer.
(Cat, String) categorize(String desc, double amount) {
  if (isTransferPhrase(desc)) return (Cat.transfer, 'Between your accounts');
  if (amount > 0) return moneyIn(desc);
  if (isChargeText(desc) || hasNoDescription(desc)) return (Cat.charges, 'Bank charges');
  return ruleMatch(desc) ?? (Cat.other, 'Uncategorised');
}

/// The first spending rule that matches, or null.
(Cat, String)? ruleMatch(String desc) {
  for (final (re, cat, sub) in _ruleRes) {
    if (re.hasMatch(desc)) return (cat, sub);
  }
  return null;
}

/// Every keyword with its category — the learning model's starting vocabulary.
/// Cash and "sent to people" are left out: their wording ("cash", "send")
/// says nothing about which merchant a purchase was from.
Iterable<(String, Cat)> get ruleSeeds sync* {
  for (final (words, cat, _) in _rules) {
    if (cat == Cat.cash || cat == Cat.people) continue;
    for (final w in words) {
      yield (w, cat);
    }
  }
}

// ---------------------------------------------------------------------------
// Counterparties and phone numbers
// ---------------------------------------------------------------------------

final _counterpartyRe = RegExp(
  r'\b(transfer|trf|payment|pmnt|pmt|paid|send money|sent|eft)\s+(to|from)\s+([A-Za-z0-9*][A-Za-z0-9*&.\-\x27 ]*)',
  caseSensitive: false,
);

/// Who the money went to / came from, as written after "transfer to", "payment
/// from" etc. Returns (kind, direction, key) or null. Key is lower-case words
/// up to the first number, e.g. "FNB App Transfer From Gg 1234" → ('transfer', 'from', 'gg').
(String, String, String)? counterparty(String desc) {
  final m = _counterpartyRe.firstMatch(desc);
  if (m == null) return null;
  final words = m[3]!
      .toLowerCase()
      .split(RegExp(r'\s+'))
      // Stop at reference / phone numbers; short codes like "8F" or "P2C" are kept.
      .takeWhile((w) => w.isNotEmpty && !RegExp(r'\d{4,}').hasMatch(w))
      .take(3)
      .toList();
  if (words.isEmpty) return null;
  final kind = m[1]!.toLowerCase();
  return (kind == 'trf' ? 'transfer' : kind, m[2]!.toLowerCase(), words.join(' '));
}

/// Phone-number-like digit runs (8–12 digits), normalised to the last 8
/// digits so 26775148671 and 75148671 match.
Set<String> phoneNumbers(String desc) => {
      for (final m in RegExp(r'(?<!\d)\d{8,12}(?!\d)').allMatches(desc))
        m[0]!.substring(m[0]!.length - 8),
    };

String normalisePhone(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
  return d.length >= 8 ? d.substring(d.length - 8) : d;
}

// ---------------------------------------------------------------------------
// Display names
// ---------------------------------------------------------------------------

const _noisePrefixes = [
  'pos purchase', 'card purchase', 'pos debit', 'debit card purchase', 'purchase', 'pos', 'debit order',
  'card', 'eft debit', 'eft credit', 'eft', 'fnb app', 'fnb ob', 'online', 'internet banking', 'chq card',
];

/// Turns "POS PURCHASE CHOPPIES MALL 471396*5328 05 Oct" into "Choppies Mall".
String cleanName(String desc) {
  var s = desc
      .replaceAll(RegExp(r'•+\d*'), ' ') // numbers bbt masked (••••5678)
      .replaceAll(RegExp(r'\b\d{4,}[x*#]+\d{2,}\b', caseSensitive: false), ' ') // masked cards 471396*5328
      .replaceAll(RegExp(r'[x*#]{2,}\d{2,}', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b\d{1,2}\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b\d{4,}\b'), ' ') // long reference numbers
      .replaceAll(RegExp(r'\b\d{1,2}[/.-]\d{1,2}([/.-]\d{2,4})?\b'), ' ') // stray dates
      .replaceAll('#', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  var changed = true;
  while (changed) {
    changed = false;
    for (final p in _noisePrefixes) {
      if (s.toLowerCase().startsWith('$p ') && s.length > p.length + 1) {
        s = s.substring(p.length).trim();
        changed = true;
      }
    }
  }
  s = s.replaceAll(RegExp(r'^[\-:*/\s]+|[\-:*/\s]+$'), '');
  if (s.isEmpty) return 'Transaction';
  final titled = s.split(' ').map((w) {
    if (w.length <= 3 && w == w.toUpperCase() && RegExp(r'[A-Z]').hasMatch(w)) return w; // keep BPC, WUC, ATM
    return w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join(' ');
  return titled.length > 40 ? '${titled.substring(0, 39)}…' : titled;
}
