import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// "Money out by category" pie with its own period picker: all months or any
/// single month, independent of the rest of the Dashboard.
class CategoryPieCard extends StatefulWidget {
  const CategoryPieCard({super.key});

  @override
  State<CategoryPieCard> createState() => _CategoryPieCardState();
}

class _CategoryPieCardState extends State<CategoryPieCard> {
  bool _chosen = false; // until the user picks, follow the Dashboard's period
  DateTime? _month; // null = all months

  DateTime? get _period {
    if (_chosen) return _month;
    return store.allMonths ? null : store.month;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() {
    final months = store.monthsOldestFirst;
    final period = _period;
    final cats = store.categorySpendFor(period);
    final total = cats.values.fold(0.0, (a, b) => a + b);
    final yearsDiffer = months.isNotEmpty && months.first.year != months.last.year;

    return BCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Money out by category',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 10),
        if (months.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip(months.length == 1 ? 'All' : 'All ${months.length} months', period == null, null),
              for (final m in months.reversed) // newest first
                _chip(yearsDiffer ? '${monthShort(m)} ${m.year % 100}' : monthLong(m), period == m, m),
            ]),
          ),
        const SizedBox(height: 14),
        if (cats.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No spending in this period', style: TextStyle(color: AppColors.muted))),
          )
        else ...[
          Center(
            child: DonutChart(
              data: cats,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(period == null ? 'Total' : monthLong(period), style: const TextStyle(color: AppColors.muted)),
                Text(pula(total, decimals: false), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          for (final e in cats.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration:
                      BoxDecoration(color: e.key.color.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
                  child: Icon(e.key.icon, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(e.key.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(pula(e.value, decimals: false), style: const TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(
                  width: 48,
                  child: Text('${(e.value / total * 100).round()}%',
                      textAlign: TextAlign.right, style: const TextStyle(color: AppColors.muted)),
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _chip(String label, bool selected, DateTime? month) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() {
            _chosen = true;
            _month = month;
          }),
        ),
      );
}
