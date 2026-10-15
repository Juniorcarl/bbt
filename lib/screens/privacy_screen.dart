import 'package:flutter/material.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Plain-language privacy notice, shown before sign-up and from Profile.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    (
      Icons.description_outlined,
      'What bbt reads',
      'When you upload a bank statement, bbt reads it on your phone. The statement file itself is '
          'never uploaded or kept. Any statement password you type is used once and never saved.'
    ),
    (
      Icons.cloud_outlined,
      'What is saved to your account',
      'Your name, email, the phone number you add, and from each statement: the dates, descriptions, '
          'amounts, balances and categories of your transactions. Account and card numbers are hidden '
          'before saving (only the last 4 digits are kept). Also your budgets and the category '
          'corrections you make, so bbt can learn.'
    ),
    (
      Icons.lock_outline,
      'Who can see it',
      'Only you, when signed in. The database checks every request, so one user can never read '
          'another user\'s data. The developer of bbt has administrator access to the database to keep '
          'it running and fix problems. Your data is never sold or shared with anyone.'
    ),
    (
      Icons.dns_outlined,
      'Where it is stored',
      'In a Supabase cloud database. Data is encrypted while it travels (HTTPS) and while it is '
          'stored. On your phone, your sign-in is kept in the phone\'s encrypted storage.'
    ),
    (
      Icons.delete_outline,
      'Deleting your data',
      'Profile → Delete all my data removes every statement, transaction, budget and correction '
          'straight away. You can also clear just your statements and upload them again.'
    ),
    (
      Icons.gavel_outlined,
      'Your rights',
      'Under Botswana\'s data protection law you can ask what data is held about you, have it '
          'corrected, or have it deleted. bbt only uses your data to show you your own spending.'
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Privacy notice'), backgroundColor: AppColors.bg),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          const Text('How bbt handles your money data, in plain words.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          for (final (icon, title, body) in _sections) ...[
            BCard(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Text(body),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          if (privacyContact.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Questions or requests: $privacyContact',
                  style: const TextStyle(color: AppColors.muted)),
            ),
        ]),
      );
}
