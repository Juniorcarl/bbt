import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../services/statement_import.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

enum Period { today, yesterday, week, month, custom }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Period _period = Period.month;
  Cat? _cat; // null = all categories
  DateTimeRange? _range;
  bool _showAll = false;

  List<Txn> get _filtered {
    final ref = store.refDate;
    final source = _period == Period.custom ? store.txns : store.monthTxns;
    return source.where((t) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      final inPeriod = switch (_period) {
        Period.today => d == ref,
        Period.yesterday => d == ref.subtract(const Duration(days: 1)),
        Period.week => !d.isBefore(ref.subtract(const Duration(days: 6))) && !d.isAfter(ref),
        Period.month => true,
        Period.custom => _range == null || (!d.isBefore(_range!.start) && !d.isAfter(_range!.end)),
      };
      return inPeriod && (_cat == null || t.cat == _cat);
    }).toList();
  }

  Future<void> _pickPeriod(Period p) async {
    if (p == Period.custom) {
      final dates = store.txns.map((t) => t.date);
      final first = dates.isEmpty ? DateTime(2024) : dates.reduce((a, b) => a.isBefore(b) ? a : b);
      final last = dates.isEmpty ? DateTime.now() : dates.reduce((a, b) => a.isAfter(b) ? a : b);
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(first.year, first.month, first.day),
        lastDate: DateTime(last.year, last.month, last.day),
      );
      if (r == null) return;
      _range = r;
    }
    setState(() => _period = p);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
          Row(children: [
            const Text('bbt.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const Spacer(),
            UserAvatar(name: store.userName, email: store.userEmail),
          ]),
          const SizedBox(height: 12),
          Text(_greeting(store.userName),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const Text("Let's make sense of your money.", style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
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
    final list = _filtered;
    final shown = _showAll ? list : list.take(10).toList();
    return [
      Row(children: [
        Expanded(
          child: Text(store.periodLabel,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        ),
        FilledButton.icon(
          onPressed: () => importStatement(context),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: const Text('Upload statement'),
        ),
      ]),
      if (store.isMultiMonth) ...[
        const SizedBox(height: 12),
        const MonthChips(),
      ],
      const SizedBox(height: 16),
      const _AccountCard(),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _MiniStat('Money in', store.monthIncome)),
        const SizedBox(width: 12),
        Expanded(child: _MiniStat('Money out', store.monthSpent)),
      ]),
      const SizedBox(height: 14),
      BCard(
        color: const Color(0xFFEAF4FC),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(store.insight, style: const TextStyle(color: AppColors.ink))),
        ]),
      ),
      if (store.allMonths && store.isMultiMonth) ...[
        const SizedBox(height: 14),
        const MonthBreakdown(),
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
                'Teach it once and it learns for next time.',
                style: const TextStyle(color: AppColors.ink),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _cat = Cat.other;
                _period = Period.month;
                _showAll = true;
              }),
              child: const Text('Review'),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      BCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('Transactions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            if (list.length > 10)
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? 'Show less' : 'View all (${list.length})'),
              ),
          ]),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final p in Period.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (p) {
                      Period.today => 'Last day',
                      Period.yesterday => 'Day before',
                      Period.week => 'Last 7 days',
                      Period.month => store.allMonths && store.isMultiMonth ? 'Everything' : 'Whole month',
                      Period.custom => 'Custom',
                    }),
                    selected: _period == p,
                    onSelected: (_) => _pickPeriod(p),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          DropdownButton<Cat?>(
            value: _cat,
            underline: const SizedBox(),
            items: [
              const DropdownMenuItem<Cat?>(value: null, child: Text('All categories')),
              for (final c in Cat.values) DropdownMenuItem<Cat?>(value: c, child: Text(c.label)),
            ],
            onChanged: (c) => setState(() => _cat = c),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No transactions for this filter', style: TextStyle(color: AppColors.muted))),
            )
          else
            for (final t in shown) TxnTile(t, onTap: () => showCategorySheet(context, t)),
        ]),
      ),
    ];
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() {
    final st = store.latestStatement;
    final tail = st?.accountTail;
    final balance = st?.closingBalance;
    final end = st?.periodEnd;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFFE3F1FB), Color(0xFFCFE6F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          st == null ? 'Statements' : 'Latest statement · ${shortDate(st.uploadedAt)} ${st.uploadedAt.year}',
          style: const TextStyle(color: AppColors.muted),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(st?.bank ?? 'Bank account',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
        if (tail != null) ...[
          const SizedBox(height: 14),
          Text('••••  ••••  ••••  $tail', style: const TextStyle(letterSpacing: 2, color: AppColors.muted)),
        ],
        if (balance != null) ...[
          const SizedBox(height: 14),
          Text(
            end == null ? 'Closing balance' : 'Balance on ${shortDate(end)} ${end.year}',
            style: const TextStyle(color: AppColors.muted),
          ),
          FittedBox(
            child: Text(pula(balance),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
        ],
      ]),
    );
  }
}

/// "Are these your own accounts?" for transfer names bbt detected.
class _OwnAccountsCard extends StatelessWidget {
  const _OwnAccountsCard();

  @override
  Widget build(BuildContext context) {
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

class _MiniStat extends StatelessWidget {
  final String label;
  final double value;
  const _MiniStat(this.label, this.value);

  @override
  Widget build(BuildContext context) => BCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(pula(value),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
        ]),
      );
}

String _greeting(String name) {
  final h = DateTime.now().hour;
  final part = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  final first = name.trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? '$part.' : '$part, $first.';
}
