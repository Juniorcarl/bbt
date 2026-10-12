import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../services/statement_import.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _mode = 'Monthly';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
          SectionTitle('Spending', subtitle: store.hasData ? store.periodLabel : null),
          if (store.isMultiMonth) ...[
            const SizedBox(height: 12),
            const MonthChips(),
          ],
          const SizedBox(height: 16),
          if (!store.hasData)
            EmptyState(onUpload: () => importStatement(context), onSample: loadSample)
          else
            ..._content(),
        ]),
      ),
    );
  }

  List<Widget> _content() {
    final bars = store.bars(_mode);
    final maxV = bars.values.fold(0.0, (a, b) => a > b ? a : b);
    final cats = store.categorySpend;
    final total = cats.values.fold(0.0, (a, b) => a + b);
    final change = store.changeVsPrev;

    return [
      BCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(store.allMonths && store.isMultiMonth ? 'Total spent over ${store.monthCount} months' : 'Total spent',
              style: const TextStyle(color: AppColors.muted)),
          FittedBox(
            child: Text(pula(store.monthSpent),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          const SizedBox(height: 4),
          if (change != null)
            Text(
              '${(change.abs() * 100).round()}% ${change <= 0 ? 'less' : 'more'} than last month',
              style: TextStyle(color: change <= 0 ? AppColors.income : const Color(0xFFD0573F)),
            )
          else if (store.allMonths && store.isMultiMonth)
            Text('About ${pula(store.avgMonthlySpent, decimals: false)} a month · ${store.monthTxns.length} transactions',
                style: const TextStyle(color: AppColors.muted))
          else
            Text('${store.monthTxns.length} transactions in ${monthLong(store.month)}',
                style: const TextStyle(color: AppColors.muted)),
        ]),
      ),
      const SizedBox(height: 14),
      BCard(
        child: Column(children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Daily', label: Text('Daily')),
              ButtonSegment(value: 'Weekly', label: Text('Weekly')),
              ButtonSegment(value: 'Monthly', label: Text('Monthly')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 170,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final e in bars.entries)
                Expanded(
                  child: Tooltip(
                    message: pula(e.value),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text(e.value == 0 ? '' : pula(e.value, decimals: false).replaceFirst('P ', ''),
                          style: const TextStyle(fontSize: 9, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Container(
                        height: maxV == 0 ? 2 : (120 * e.value / maxV).clamp(2.0, 120.0),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(e.key, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      BCard(
        child: Column(children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Spending by category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
          const SizedBox(height: 12),
          if (cats.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No spending this month', style: TextStyle(color: AppColors.muted)),
            )
          else ...[
            DonutChart(
              data: cats,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Total', style: TextStyle(color: AppColors.muted)),
                Text(pula(total, decimals: false), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(height: 12),
            for (final e in cats.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: e.key.color.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
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
      ),
    ];
  }
}
