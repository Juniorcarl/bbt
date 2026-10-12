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
            IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
            const CircleAvatar(radius: 16, backgroundColor: Color(0xFFDCEBF8), child: Text('JC', style: TextStyle(fontSize: 12))),
          ]),
          const SizedBox(height: 12),
          const Text('Good morning, Jane.',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const Text("Let's make sense of your money.", style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          if (!store.hasData)
            EmptyState(onUpload: () => importStatement(context), onSample: loadSample)
          else
            ..._content(context),
        ]),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final list = _filtered;
    final shown = _showAll ? list : list.take(10).toList();
    final month = store.month;
    return [
      Row(children: [
        const MonthPicker(),
        const Spacer(),
        FilledButton.icon(
          onPressed: () => importStatement(context),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: const Text('Upload statement'),
        ),
      ]),
      if (store.isSample)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Showing sample data — upload your own statement to replace it.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
      const SizedBox(height: 16),
      const _AccountCard(),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _MiniStat('${monthLong(month)} spending', store.monthSpent)),
        const SizedBox(width: 12),
        Expanded(child: _MiniStat('${monthLong(month)} money in', store.monthIncome)),
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
                      Period.month => 'Whole month',
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
            for (final t in shown) TxnTile(t),
        ]),
      ),
    ];
  }
}

/// "October 2026 ▾" — switches between the months in the statement.
class MonthPicker extends StatelessWidget {
  const MonthPicker({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() => PopupMenuButton<DateTime>(
        onSelected: (m) => store.month = m,
        itemBuilder: (_) => [for (final m in store.months) PopupMenuItem(value: m, child: Text(monthYear(m)))],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFC9D6E3)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(monthYear(store.month), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_drop_down, color: AppColors.primary),
          ]),
        ),
      );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() => Container(
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
          Text(store.sourceName ?? 'Statement', style: const TextStyle(color: AppColors.muted), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(store.bank ?? 'Your bank',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
          if (store.accountTail != null) ...[
            const SizedBox(height: 14),
            Text('••••  ••••  ••••  ${store.accountTail}', style: const TextStyle(letterSpacing: 2, color: AppColors.muted)),
          ],
          if (store.closingBalance != null) ...[
            const SizedBox(height: 14),
            const Text('Closing balance', style: TextStyle(color: AppColors.muted)),
            FittedBox(
              child: Text(pula(store.closingBalance!),
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
          ],
        ]),
      );
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
