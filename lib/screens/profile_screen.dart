import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../data/categorizer.dart';
import '../services/backend.dart';
import '../services/security.dart';
import 'books_check_screen.dart';
import 'privacy_screen.dart';
import '../services/statement_import.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cz = store.categoriser;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 110), children: [
        Center(
          child: Column(children: [
            UserAvatar(name: store.userName, email: store.userEmail, radius: 40),
            const SizedBox(height: 10),
            Text(store.userName.isEmpty ? 'Add your name' : store.userName,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(store.userEmail, style: const TextStyle(color: AppColors.muted)),
          ]),
        ),
        const SizedBox(height: 20),

        const _Header('Account'),
        BCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Name'),
              subtitle: Text(store.userName.isEmpty ? 'Not set' : store.userName),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () => _editName(context),
            ),
            ListTile(
              leading: const Icon(Icons.phone_iphone),
              title: const Text('Your phone number'),
              subtitle: Text(store.phone.isNotEmpty
                  ? store.phone
                  : (store.suggestedPhone != null
                      ? 'Not set · looks like ${store.suggestedPhone} from your airtime'
                      : 'Not set')),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () => _editPhone(context),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changePassword(context),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                await Supabase.instance.client.auth.signOut();
              },
            ),
          ]),
        ),

        _Header('Statements (${store.statements.length})'),
        BCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final st in store.statements) _StatementTile(st),
            ListTile(
              leading: const Icon(Icons.upload_outlined, color: AppColors.primary),
              title: const Text('Upload a statement', style: TextStyle(color: AppColors.primary)),
              onTap: () => importStatement(context),
            ),
            if (store.statements.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Clear statements to upload again'),
                subtitle: const Text('Keeps your budgets and what bbt learned'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (await _confirm(context, 'Clear all statements?',
                      'All statements and transactions are removed so you can upload them again. '
                          'Budgets and categories you taught bbt are kept.',
                      'Clear')) {
                    try {
                      await store.clearStatements();
                    } catch (_) {
                      messenger.showSnackBar(const SnackBar(content: Text("Couldn't clear. Check your connection.")));
                    }
                  }
                },
              ),
          ]),
        ),

        const _Header('Your own accounts'),
        BCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            const ListTile(
              leading: Icon(Icons.swap_horiz),
              title: Text('Transfers to and from these are not counted'),
              subtitle: Text('Detected from your statements. Tap one to change it.'),
            ),
            for (final k in (store.ownAccounts.toList()..sort()))
              ListTile(
                dense: true,
                title: Text(k.toUpperCase()),
                subtitle: Text(store.confirmedOwn.contains(k) ? 'Confirmed as yours' : 'Detected — not confirmed'),
                trailing: TextButton(
                  onPressed: () => store.confirmOwnAccount(k, false),
                  child: const Text('Not mine'),
                ),
              ),
            for (final k in (store.rejectedOwn.toList()..sort()))
              ListTile(
                dense: true,
                title: Text(k.toUpperCase()),
                subtitle: const Text('Marked as not yours'),
                trailing: TextButton(
                  onPressed: () => store.confirmOwnAccount(k, true),
                  child: const Text("It's mine"),
                ),
              ),
          ]),
        ),

        const _Header('AI & Categorization'),
        BCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
              title: const Text('What bbt has learned'),
              subtitle: Text(cz.examplesLearned == 0
                  ? 'Tap any transaction to correct its category. bbt learns from every correction.'
                  : '${cz.merchantsLearned} merchants remembered · ${cz.examplesLearned} corrections learned'),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset learning'),
              enabled: cz.examplesLearned > 0,
              onTap: () async {
                if (await _confirm(context, 'Reset learning?', 'bbt will forget every category you taught it.', 'Reset')) {
                  await store.resetLearning();
                }
              },
            ),
          ]),
        ),

        if (security.lockSupported || security.isAndroid) ...[
          const _Header('Security'),
          const _SecurityCard(),
        ],

        const _Header('Privacy'),
        BCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy notice'),
              subtitle: const Text('What is saved, who can see it and your rights'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFD0573F)),
              title: const Text('Delete all my data', style: TextStyle(color: Color(0xFFD0573F))),
              subtitle: const Text('Statements, transactions, budgets and learning'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                if (await _confirm(context, 'Delete all your data?',
                    'This permanently deletes every statement, transaction, budget and correction. It cannot be undone.',
                    'Delete')) {
                  try {
                    await store.deleteAllData();
                    messenger.showSnackBar(const SnackBar(content: Text('All your data was deleted.')));
                  } catch (_) {
                    messenger.showSnackBar(const SnackBar(content: Text("Couldn't delete. Check your connection.")));
                  }
                }
              },
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _editName(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: store.userName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await store.updateName(name.trim());
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't save your name. Check your connection.")));
    }
  }

  Future<void> _editPhone(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: store.phone.isNotEmpty ? store.phone : (store.suggestedPhone ?? ''));
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your phone number'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Used to tell money you send to yourself (cash) from money you send to other people.',
            style: TextStyle(color: AppColors.muted),
          ),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'e.g. 71234567'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value.trim().isNotEmpty && normalisePhone(value).length < 8) {
      messenger.showSnackBar(const SnackBar(content: Text('That number looks too short.')));
      return;
    }
    try {
      await store.setPhone(value);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't save. Check your connection.")));
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: '8+ characters, letters and numbers'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Change')),
        ],
      ),
    );
    controller.dispose();
    if (pw == null) return;
    if (pw.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(pw) || !RegExp(r'\d').hasMatch(pw)) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Use at least 8 characters with both letters and numbers.')));
      return;
    }
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: pw));
      messenger.showSnackBar(const SnackBar(content: Text('Password changed.')));
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't change password. Check your connection.")));
    }
  }
}

Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
      );
}

class _StatementTile extends StatelessWidget {
  final StatementRecord st;
  const _StatementTile(this.st);

  @override
  Widget build(BuildContext context) {
    final range = st.periodStart == null || st.periodEnd == null
        ? ''
        : '${shortDate(st.periodStart!)} ${st.periodStart!.year} – ${shortDate(st.periodEnd!)} ${st.periodEnd!.year} · ';
    final check = store.booksCheck(st);
    final diff = check?.difference;
    return ListTile(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BooksCheckScreen(st))),
      leading: Icon(
        diff == null ? Icons.description_outlined : (diff.abs() < 0.01 ? Icons.check_circle : Icons.warning_amber_rounded),
        color: diff == null ? null : (diff.abs() < 0.01 ? AppColors.income : const Color(0xFFD0573F)),
      ),
      title: Text(st.bank ?? st.fileName, overflow: TextOverflow.ellipsis),
      subtitle: Text('$range${st.txnCount} new transactions\nUploaded ${shortDate(st.uploadedAt)} ${st.uploadedAt.year}'),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete statement',
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          if (await _confirm(context, 'Delete this statement?',
              'Its ${st.txnCount} transactions will be removed too.', 'Delete')) {
            try {
              await store.deleteStatement(st);
            } catch (_) {
              messenger.showSnackBar(const SnackBar(content: Text("Couldn't delete. Check your connection.")));
            }
          }
        },
      ),
    );
  }
}

/// App lock and screenshot settings (kept on this phone only).
class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: security,
        builder: (context, _) => BCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            if (security.lockSupported)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('App lock'),
                subtitle: Text('Ask for your fingerprint, face or PIN when bbt opens '
                    'or after ${Security.lockAfter.inMinutes} minute away'),
                value: security.lockEnabled,
                onChanged: (on) async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (!await security.setLockEnabled(on)) {
                    messenger.showSnackBar(const SnackBar(content: Text('App lock is still on.')));
                  }
                },
              ),
            if (security.isAndroid)
              SwitchListTile(
                secondary: const Icon(Icons.screenshot_monitor_outlined),
                title: const Text('Hide from screenshots'),
                subtitle: const Text('Blocks screenshots and hides bbt in the recent apps list. '
                    'Turn off briefly if you want to take a screenshot.'),
                value: security.blockScreenshots,
                onChanged: security.setBlockScreenshots,
              ),
            const ListTile(
              leading: Icon(Icons.timer_outlined),
              title: Text('Automatic sign-out'),
              subtitle: Text('If bbt isn\'t opened for 30 days, you are signed out on this phone.'),
            ),
          ]),
        ),
      );
}
