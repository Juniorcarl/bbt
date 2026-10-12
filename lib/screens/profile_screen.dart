import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _sections = {
    'Account': ['Personal Information', 'Connected Bank Statements', 'Statement History'],
    'Preferences': ['Currency', 'Notifications', 'Dark Mode'],
    'Privacy & Security': ['Data Privacy', 'Delete Data', 'Security'],
    'AI & Categorization': ['Automatic Categorization', 'Category Preferences', 'Review Categorization History'],
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
      ]),
    );
  }
}
