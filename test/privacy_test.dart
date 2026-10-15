import 'package:bbt/data/categorizer.dart';
import 'package:bbt/data/privacy.dart';
import 'package:bbt/data/statement_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('maskPrivate', () {
    test('account numbers keep only the last 4 digits', () {
      expect(maskPrivate('Byc Debit 63015864936'), 'Byc Debit ••••4936');
      expect(maskPrivate('Ref 123456789'), 'Ref ••••6789');
    });

    test('half-masked card numbers are fully masked', () {
      expect(maskPrivate('POS Purchase Spar 471396*5328'), 'POS Purchase Spar ••••5328');
      expect(maskPrivate('Card 4713xxxxxx5328 Engen'), 'Card ••••5328 Engen');
    });

    test('phone numbers lose the country code but stay usable', () {
      expect(maskPrivate('Send Money 26771234567'), 'Send Money 71234567');
      expect(phoneNumbers(maskPrivate('Airtime 26771234567')), {'71234567'});
      expect(maskPrivate('P2C 71234567 Test User'), 'P2C 71234567 Test User');
    });

    test('short numbers, codes and dates are left alone', () {
      expect(maskPrivate('Transfer To Sv 8F 2026'), 'Transfer To Sv 8F 2026');
      expect(maskPrivate('Monthly Fee 31/07'), 'Monthly Fee 31/07');
    });

    test('masked numbers do not show in display names', () {
      expect(cleanName(maskPrivate('Byc Debit 63015864936')), isNot(contains('•')));
    });
  });

  test('the parser never keeps full account numbers', () {
    final s = parseStatementText('''
02 Jun Byc Debit 63015864936 20.04Dr 979.96
03 Jun Send Money 26773333333 50.00Dr 929.96
''');
    for (final t in s.txns) {
      expect(RegExp(r'\d{9,}').hasMatch(t.raw), isFalse, reason: t.raw);
    }
    expect(s.txns.first.raw, contains('••••4936'));
  });
}
