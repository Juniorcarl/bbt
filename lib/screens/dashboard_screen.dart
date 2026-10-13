import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../services/statement_import.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
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
          SectionTitle('Cash flow', subtitle: store.hasData ? store.periodLabel : null),
          if (store.isMultiMonth) ...[
            const SizedBox(height: 12),
            const MonthChips(),
          ],
          const SizedBox(height: 16),
          if (!store.hasData)
            EmptyState(onUpload: () => importStatement(context))
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

    final income = store.monthIncome;
    final out = store.monthSpent;
    final net = income - out;
    final flow = store.flow;
    final fees = store.feeBreakdown;

    return [
      // Money in / out / left over
      BCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Figure('Money in', income, AppColors.income),
            _Figure('Money out', out, AppColors.ink),
            _Figure(net >= 0 ? 'Left over' : 'Overspent', net.abs(),
                net >= 0 ? const Color(0xFF5BB0E8) : const Color(0xFFD0573F)),
          ]),
          const SizedBox(height: 10),
          Text(
            [
              if (change != null) '${(change.abs() * 100).round()}% ${change <= 0 ? 'less' : 'more'} spending than last month',
              if (store.allMonths && store.isMultiMonth) 'About ${pula(store.avgMonthlySpent, decimals: false)} out a month',
              'Includes ${pula(store.monthCharges, decimals: false)} bank charges',
            ].join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (flow.transfersOut > 0 || flow.transfersIn > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Cat.transfer.icon, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Moved between your accounts: ${pula(flow.transfersOut, decimals: false)} out, '
                  '${pula(flow.transfersIn, decimals: false)} back in (not counted)',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 14),

      // Where the money went
      BCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Where your money went',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 14),
          FlowChart(flow),
        ]),
      ),
      const SizedBox(height: 14),

      // Bank charges
      BCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Cat.charges.icon, color: Cat.charges.color),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Bank charges',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            Text(pula(store.monthCharges), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          if (fees.isEmpty)
            Text(
              store.monthCharges > 0
                  ? 'Fees and service charges deducted by your bank in this period.'
                  : 'No bank charges in this period.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            )
          else ...[
            const Text('What caused them (fees your bank listed per transaction):',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            for (final e in fees.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(e.key)),
                  Text('${e.value.$1} × ', style: const TextStyle(color: AppColors.muted)),
                  SizedBox(
                    width: 84,
                    child: Text(pula(e.value.$2), textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
          ],
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
            child: Text('Money out by category',
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

class _Figure extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _Figure(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(pula(value, decimals: false),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
      );
}
