import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../services/statement_import.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'transactions_screen.dart';

/// Home: greeting, wallet card, quick actions, anything that needs the user,
/// and the latest transactions.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 110), children: [
          const _Header(),
          const SizedBox(height: 22),
          if (store.loading && !store.hasData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (store.loadError != null)
            BCard(
              child: Column(children: [
                Text(store.loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                FilledButton(onPressed: store.loadForUser, child: const Text('Try again')),
              ]),
            )
          else if (!store.hasData)
            EmptyState(onUpload: () => importStatement(context))
          else
            ..._content(context),
        ]),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final recent = store.monthTxns.take(6).toList();
    return [
      Row(children: [
        const Text('My Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const Spacer(),
        Text(store.periodLabel, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]),
      const SizedBox(height: 12),
      const _WalletCard(),
      if (store.isMultiMonth) ...[
        const SizedBox(height: 18),
        const MonthChips(),
      ],
      if (store.pendingOwnAccounts.isNotEmpty) ...[
        const SizedBox(height: 14),
        const _OwnAccountsCard(),
      ],
      if (store.needsReview > 0) ...[
        const SizedBox(height: 14),
        BCard(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.school_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "${store.needsReview} transaction${store.needsReview == 1 ? '' : 's'} bbt doesn't recognise yet. "
                'Teach it once and it learns.',
                style: const TextStyle(color: AppColors.ink),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const TransactionsScreen(initialCategory: Cat.other),
              )),
              child: const Text('Review'),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      BCard(
        color: const Color(0xFFEAF4FC),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(store.homeInsight, style: const TextStyle(color: AppColors.ink))),
        ]),
      ),
      const SizedBox(height: 18),
      Row(children: [
        const Expanded(
          child: Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransactionsScreen())),
          child: const Text('View All'),
        ),
      ]),
      BCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(children: [
          for (final t in recent) TxnTile(t, onTap: () => showCategorySheet(context, t)),
        ]),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
    final name = store.userName.trim().isEmpty ? store.userEmail : store.userName;
    return Row(children: [
      GestureDetector(
        onTap: () => appTab.value = 3,
        child: UserAvatar(name: store.userName, email: store.userEmail, radius: 22),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(part, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ]),
      ),
      _CircleButton(
        Icons.search_rounded,
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransactionsScreen())),
      ),
    ]);
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: Color(0xFFE6ECF2))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, size: 20, color: AppColors.ink)),
        ),
      );
}

/// Dark card: bank, last digits of the account, and this period's money in and out.
class _WalletCard extends StatelessWidget {
  const _WalletCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() {
    final st = store.latestStatement;
    final tail = st?.accountTail;
    const light = Color(0xFFB9C2D0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF141821), Color(0xFF2A303C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(st?.bank ?? 'Your account',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          const Text('bbt.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _Figure('Money in', store.monthIncome, const Color(0xFF8FE0B4))),
          Expanded(child: _Figure('Money out', store.monthSpent, Colors.white)),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Text(tail == null ? '' : '••••  ••••  $tail',
                style: const TextStyle(color: light, letterSpacing: 2, fontSize: 13)),
          ),
          Text(store.periodLabel, style: const TextStyle(color: light, fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _Figure(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Color(0xFFB9C2D0), fontSize: 12)),
        const SizedBox(height: 2),
        FittedBox(
          child: Text(pula(value, decimals: false),
              style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800)),
        ),
      ]);
}

/// "Are these your own accounts?" for transfer names bbt detected.
class _OwnAccountsCard extends StatelessWidget {
  const _OwnAccountsCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() {
    final keys = store.pendingOwnAccounts;
    return BCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Cat.transfer.icon, color: AppColors.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Are these your own accounts?',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          "Money moves to and from these like your own savings or accounts, so bbt doesn't count it as income or "
          'spending. Tap ✗ for any that are other people.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in keys)
            InputChip(
              label: Text(k.toUpperCase()),
              onDeleted: () => store.confirmOwnAccount(k, false),
              deleteIcon: const Icon(Icons.close, size: 16),
              onPressed: () => store.confirmOwnAccount(k, true),
              avatar: const Icon(Icons.check, size: 16),
            ),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () async {
              for (final k in keys) {
                await store.confirmOwnAccount(k, true);
              }
            },
            child: const Text('Yes, all mine'),
          ),
        ),
      ]),
    );
  }
}

