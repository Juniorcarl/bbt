import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../services/statement_import.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Monthly limits per category, saved to the user's account.
class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  static final _expenseCats = Cat.values.where((c) => c != Cat.income).toList();

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final budgets = store.budgets;
    final planned = budgets.values.fold(0.0, (a, b) => a + b);
    // Limits are monthly, so "All months" compares against the monthly average.
    final perMonth = store.periodMonths;
    final income = store.monthIncome / perMonth;
    final spend = {for (final e in store.categorySpend.entries) e.key: e.value / perMonth};
    final averaged = store.allMonths && store.isMultiMonth;

    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
        SectionTitle(
          averaged ? 'Monthly Budget' : (store.hasData ? '${monthLong(store.month)} Budget' : 'Budget'),
          subtitle: averaged ? 'Compared with your average over ${store.periodLabel}' : null,
        ),
        if (store.isMultiMonth) ...[
          const SizedBox(height: 12),
          const MonthChips(),
        ],
        const SizedBox(height: 16),
        if (!store.hasData)
          EmptyState(onUpload: () => importStatement(context))
        else ...[
          BCard(
            child: Column(children: [
              Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: income == 0 ? 0.0 : (planned / income).clamp(0.0, 1.0),
                    strokeWidth: 14,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFFE3EEF8),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(pula(planned, decimals: false), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('/ ${pula(income, decimals: false)}', style: const TextStyle(color: AppColors.muted)),
                ]),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                _Stat(averaged ? 'Avg. money in' : 'Money in', income),
                _Stat('Total limits', planned),
                _Stat('Left to save', income - planned),
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
              Expanded(child: Text(_insight(budgets, spend))),
            ]),
          ),
          const SizedBox(height: 14),
          BCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tap a category to set its monthly limit',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 4),
              for (final c in _expenseCats)
                _BudgetRow(
                  cat: c,
                  spent: spend[c] ?? 0,
                  limit: budgets[c],
                  onTap: () => _editLimit(context, c, budgets[c], store.avgSpendFor(c)),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  /// Points at the category closest to (or over) its limit.
  String _insight(Map<Cat, double> budgets, Map<Cat, double> spend) {
    if (budgets.isEmpty) {
      final top = spend.entries.where((e) => e.key != Cat.income).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (top.isEmpty) return 'Set monthly limits below to track your spending.';
      return 'No limits yet. ${top.first.key.label} is where most of your money goes '
          '(${pula(top.first.value, decimals: false)} a month), a good place to start.';
    }
    final ratios = <(Cat, double)>[
      for (final e in budgets.entries) (e.key, (spend[e.key] ?? 0) / e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final (cat, ratio) = ratios.first;
    final pct = (ratio * 100).round();
    if (ratio > 1) return '${cat.label} is over budget at $pct% of its limit.';
    if (ratio >= 0.8) return 'Careful: ${cat.label} is at $pct% of its limit.';
    return "You're on track. ${cat.label} is your closest category at $pct% of its limit.";
  }

  Future<void> _editLimit(BuildContext context, Cat cat, double? current, double avg) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: current == null ? '' : current.toStringAsFixed(0));
    final result = await showDialog<(bool, double?)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${cat.label} limit'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (avg > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('You usually spend about ${pula(avg, decimals: false)} a month on ${cat.label.toLowerCase()}.',
                  style: const TextStyle(color: AppColors.muted)),
            ),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: 'P ', labelText: 'Monthly limit'),
          ),
        ]),
        actions: [
          if (current != null)
            TextButton(onPressed: () => Navigator.pop(ctx, (true, null)), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (true, double.tryParse(controller.text.replaceAll(',', '').trim()))),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !result.$1) return;
    try {
      await store.setBudget(cat, result.$2);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't save the limit. Check your connection.")));
    }
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
  final double spent;
  final double? limit;
  final VoidCallback onTap;
  const _BudgetRow({required this.cat, required this.spent, required this.limit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = limit;
    final over = l != null && spent > l;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(children: [
          Row(children: [
            Icon(cat.icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(cat.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(
              l == null
                  ? '${pula(spent, decimals: false)} · Set limit'
                  : '${pula(spent, decimals: false)} / ${pula(l, decimals: false)}',
              style: TextStyle(
                color: over ? const Color(0xFFD0573F) : (l == null ? AppColors.primary : AppColors.muted),
                fontSize: 12,
              ),
            ),
          ]),
          if (l != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (spent / l).clamp(0.0, 1.0),
                minHeight: 8,
                color: over ? const Color(0xFFD0573F) : cat.color,
                backgroundColor: cat.color.withValues(alpha: 0.2),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
