import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../data/models.dart';
import '../data/spending_store.dart';
import '../services/statement_import.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final plannedSpending = budgets.values.fold(0.0, (a, b) => a + b);
    final monthlyIncome = store.monthIncome;
    final categorySpend = store.categorySpend;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
        SectionTitle(store.hasData ? '${monthLong(store.month)} Budget' : 'Budget'),
        const SizedBox(height: 16),
        if (!store.hasData)
          EmptyState(onUpload: () => importStatement(context), onSample: loadSample)
        else ...[
          BCard(
            child: Column(children: [
              Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: monthlyIncome == 0 ? 0.0 : (plannedSpending / monthlyIncome).clamp(0.0, 1.0),
                    strokeWidth: 14,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFFE3EEF8),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(pula(plannedSpending, decimals: false),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('/ ${pula(monthlyIncome, decimals: false)}', style: const TextStyle(color: AppColors.muted)),
                ]),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                _Stat('Monthly income', monthlyIncome),
                _Stat('Planned spending', plannedSpending),
                _Stat('Expected savings', monthlyIncome - plannedSpending),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          BCard(
            color: const Color(0xFFEAF4FC),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(_budgetInsight(categorySpend))),
            ]),
          ),
          const SizedBox(height: 14),
          BCard(
            child: Column(children: [
              for (final e in budgets.entries) _BudgetRow(e.key, categorySpend[e.key] ?? 0, e.value),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text("Create Next Month's Budget"),
          ),
        ],
      ]),
    );
  }

  /// Points at the category closest to (or over) its limit.
  String _budgetInsight(Map<Cat, double> spend) {
    final over = <(Cat, double)>[
      for (final e in budgets.entries) (e.key, (spend[e.key] ?? 0) / e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    if (over.isEmpty) return 'Set limits for your categories to track your budget.';
    final (cat, ratio) = over.first;
    final pct = (ratio * 100).round();
    if (ratio > 1) return '${cat.label} is over budget at $pct% of its limit.';
    if (ratio >= 0.8) return 'Careful: ${cat.label} is at $pct% of its limit.';
    return "You're on track. ${cat.label} is your closest category at $pct% of its limit.";
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double v;
  const _Stat(this.label, this.v);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(pula(v, decimals: false), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _BudgetRow extends StatelessWidget {
  final Cat cat;
  final double spent, limit;
  const _BudgetRow(this.cat, this.spent, this.limit);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(children: [
          Row(children: [
            Icon(cat.icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(cat.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${pula(spent, decimals: false)} / ${pula(limit, decimals: false)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (spent / limit).clamp(0.0, 1.0),
              minHeight: 8,
              color: cat.color,
              backgroundColor: cat.color.withValues(alpha: 0.2),
            ),
          ),
        ]),
      );
}
