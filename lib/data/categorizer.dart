import 'models.dart';

/// Keyword rules, checked top to bottom. First match wins.
/// Keywords match whole words, case-insensitive. Add local merchants here.
const _rules = <(List<String>, Cat, String)>[
  // Bank fees & cash before anything else (descriptions often include merchant-like words)
  (['service fee', 'bank charge', 'bank charges', 'monthly fee', 'admin fee', 'sms fee', 'notification fee', 'fee', 'fees', 'commission'], Cat.bills, 'Bank fees'),
  (['atm', 'cash withdrawal', 'withdrawal'], Cat.other, 'Cash withdrawal'),
  (['orange money', 'myzaka', 'my zaka', 'smega', 'mascom myzaka'], Cat.other, 'Mobile money'),

  // Bills & utilities
  (['mascom', 'orange', 'btc', 'bemobile', 'be mobile', 'airtime', 'data bundle'], Cat.bills, 'Telecommunications'),
  (['bpc', 'botswana power', 'electricity', 'prepaid elec', 'power prepaid'], Cat.bills, 'Electricity'),
  (['wuc', 'water utilities', 'water'], Cat.bills, 'Water'),
  (['dstv', 'multichoice', 'gotv', 'internet', 'fibre', 'liquid', 'starlink'], Cat.bills, 'TV & internet'),
  (['rent', 'rental', 'landlord'], Cat.bills, 'Rent'),
  (['insurance', 'botswana life', 'bona life', 'hollard', 'metropolitan', 'old mutual', 'funeral'], Cat.bills, 'Insurance'),
  (['loan', 'repayment', 'letshego', 'bayport', 'instalment'], Cat.bills, 'Loan repayment'),

  // Health (before food: Clicks/Dischem sell groceries too)
  (['pharmacy', 'chemist', 'clinic', 'hospital', 'dental', 'dentist', 'doctor', 'medical', 'dischem', 'dis-chem', 'clicks', 'bokamoso', 'sidilega', 'optometrist', 'bomaid', 'pula medical', 'bpomas'], Cat.health, 'Health'),

  // Food
  (['choppies', 'spar', 'sefalana', 'pick n pay', 'picknpay', 'pnp', 'shoprite', 'checkers', 'woolworths', 'food lovers', 'usave', 'u-save', 'square mart', 'trans supermarket', 'superspar', 'liquorama', 'grocer', 'supermarket', 'butchery', 'bakery'], Cat.food, 'Groceries'),
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

  // Generic transfers
  (['transfer', 'trf', 'eft', 'payment to', 'send money', 'cashsend', 'ewallet', 'e-wallet'], Cat.other, 'Transfer'),
];

const _incomeKeywords = [
  'salary', 'salaries', 'payroll', 'wages', 'stipend', 'allowance', 'dividend', 'interest received',
  'credit interest', 'refund', 'reversal', 'deposit', 'cash deposit', 'received', 'inward', 'incoming',
];

final _ruleRes = [
  for (final r in _rules) (RegExp(r.$1.map(_wordPattern).join('|'), caseSensitive: false), r.$2, r.$3),
];
final _incomeRe = RegExp(_incomeKeywords.map(_wordPattern).join('|'), caseSensitive: false);

String _wordPattern(String k) => '(?<![A-Za-z0-9])${RegExp.escape(k)}(?![A-Za-z0-9])';

/// True when the description reads like money coming in.
bool looksLikeIncome(String desc) => _incomeRe.hasMatch(desc);

/// Category and a short sub-label (e.g. Food / Groceries) for one transaction.
(Cat, String) categorize(String desc, double amount) {
  if (amount > 0) {
    final d = desc.toLowerCase();
    if (d.contains('salary') || d.contains('payroll') || d.contains('wages')) return (Cat.income, 'Salary');
    if (d.contains('refund') || d.contains('reversal')) return (Cat.income, 'Refund');
    if (d.contains('interest')) return (Cat.income, 'Interest');
    return (Cat.income, 'Money in');
  }
  for (final (re, cat, sub) in _ruleRes) {
    if (re.hasMatch(desc)) return (cat, sub);
  }
  return (Cat.other, 'Uncategorised');
}

const _noisePrefixes = [
  'pos purchase', 'card purchase', 'pos debit', 'debit card purchase', 'purchase', 'pos', 'debit order',
  'card', 'payment to', 'payment', 'eft debit', 'eft credit', 'eft', 'fnb app', 'online', 'internet banking',
];

/// Turns "POS PURCHASE CHOPPIES MALL 4321*1234 05/10" into "Choppies Mall".
String cleanName(String desc) {
  var s = desc
      .replaceAll(RegExp(r'[x*#]{2,}\d{2,}', caseSensitive: false), ' ') // masked card numbers
      .replaceAll(RegExp(r'\b\d{4,}\b'), ' ') // long reference numbers
      .replaceAll(RegExp(r'\b\d{1,2}[/.-]\d{1,2}([/.-]\d{2,4})?\b'), ' ') // stray dates
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
