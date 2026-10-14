import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

enum Period { lastDay, dayBefore, week, all, custom }

/// Every transaction in the selected period, with filters. Opened from
/// "View all" on Home (optionally pre-filtered to one category).
class TransactionsScreen extends StatefulWidget {
  final Cat? initialCategory;
  const TransactionsScreen({super.key, this.initialCategory});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  Period _period = Period.all;
  Cat? _cat;
  DateTimeRange? _range;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _cat = widget.initialCategory;
  }

  List<Txn> get _filtered {
    final ref = store.refDate;
    final source = _period == Period.custom ? store.txns : store.monthTxns;
    final q = _query.trim().toLowerCase();
    return source.where((t) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      final inPeriod = switch (_period) {
        Period.lastDay => d == ref,
        Period.dayBefore => d == ref.subtract(const Duration(days: 1)),
        Period.week => !d.isBefore(ref.subtract(const Duration(days: 6))) && !d.isAfter(ref),
        Period.all => true,
        Period.custom => _range == null || (!d.isBefore(_range!.start) && !d.isAfter(_range!.end)),
      };
      final matches = q.isEmpty || t.name.toLowerCase().contains(q) || t.raw.toLowerCase().contains(q);
      return inPeriod && matches && (_cat == null || t.cat == _cat);
    }).toList();
  }

  Future<void> _pickPeriod(Period p) async {
    if (p == Period.custom) {
      final dates = store.txns.map((t) => t.date);
      if (dates.isEmpty) return;
      final first = dates.reduce((a, b) => a.isBefore(b) ? a : b);
      final last = dates.reduce((a, b) => a.isAfter(b) ? a : b);
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
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list = _filtered;
          final total = list.fold(0.0, (a, t) => a + t.amount);
          return Scaffold(
            appBar: AppBar(title: const Text('Transactions'), backgroundColor: AppColors.bg),
            body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
              if (store.isMultiMonth) ...[const MonthChips(), const SizedBox(height: 10)],
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final p in Period.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (p) {
                          Period.lastDay => 'Last day',
                          Period.dayBefore => 'Day before',
                          Period.week => 'Last 7 days',
                          Period.all => store.allMonths && store.isMultiMonth ? 'Everything' : 'Whole month',
                          Period.custom => 'Custom',
                        }),
                        selected: _period == p,
                        onSelected: (_) => _pickPeriod(p),
                      ),
                    ),
                ]),
              ),
              Row(children: [
                DropdownButton<Cat?>(
                  value: _cat,
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem<Cat?>(value: null, child: Text('All categories')),
                    for (final c in Cat.values) DropdownMenuItem<Cat?>(value: c, child: Text(c.label)),
                  ],
                  onChanged: (c) => setState(() => _cat = c),
                ),
                const Spacer(),
                Text('${list.length} · ${pula(total, sign: true)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
              BCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: Text('No transactions for this filter', style: TextStyle(color: AppColors.muted))),
                      )
                    : Column(children: [
                        for (final t in list) TxnTile(t, onTap: () => showCategorySheet(context, t)),
                      ]),
              ),
            ]),
          );
        },
      );
}
