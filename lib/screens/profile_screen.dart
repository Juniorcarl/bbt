import 'package:flutter/material.dart';
import '../data/smart_categorizer.dart';
import '../data/spending_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _sections = {
    'Account': ['Personal Information', 'Connected Bank Statements', 'Statement History'],
    'Preferences': ['Currency', 'Notifications', 'Dark Mode'],
    'Privacy & Security': ['Data Privacy', 'Delete Data', 'Security'],
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
        const Center(
          child: Column(children: [
            CircleAvatar(radius: 40, backgroundColor: Color(0xFFDCEBF8), child: Icon(Icons.person, size: 40)),
            SizedBox(height: 10),
            Text('Jane Cooper', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('jane@example.com', style: TextStyle(color: AppColors.muted)),
          ]),
        ),
        const SizedBox(height: 20),
        for (final s in _sections.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
            child: Text(s.key, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
          ),
          BCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final item in s.value)
                ListTile(title: Text(item), trailing: const Icon(Icons.chevron_right), onTap: () {}),
            ]),
          ),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 0, 8),
          child: Text('AI & Categorization', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => BCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
                title: const Text('What bbt has learned'),
                subtitle: Text(categorizer.examplesLearned == 0
                    ? 'Tap any transaction to correct its category. bbt learns from every correction.'
                    : '${categorizer.merchantsLearned} merchants remembered · '
                        '${categorizer.examplesLearned} corrections learned'),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reset learning'),
                enabled: categorizer.examplesLearned > 0,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reset learning?'),
                      content: const Text('bbt will forget every category you taught it.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                      ],
                    ),
                  );
                  if (ok == true) await store.resetLearning();
                },
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
