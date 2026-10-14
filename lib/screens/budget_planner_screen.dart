import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// "Make a budget": enter what comes in each month, set a savings goal, then
/// give every category an amount until there's nothing left to assign.
class BudgetPlannerScreen extends StatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  State<BudgetPlannerScreen> createState() => _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends State<BudgetPlannerScreen> {
  static final _cats = Cat.values.where((c) => c.isOutflow).toList();

  late final TextEditingController _income;
  late final TextEditingController _savings;
  late final Map<Cat, TextEditingController> _amounts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final suggestedIncome = store.plannedIncome ??
        (store.avgMonthlyRegularIncome > 0 ? store.avgMonthlyRegularIncome : null);
    _income = TextEditingController(text: _fmt(suggestedIncome));
    _savings = TextEditingController(text: _fmt(store.plannedSavings));
    _amounts = {for (final c in _cats) c: TextEditingController(text: _fmt(store.budgets[c]))};
    for (final c in [_income, _savings, ..._amounts.values]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_income, _savings, ..._amounts.values]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double? v) => v == null || v <= 0 ? '' : v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
  static double _val(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  double get _income$ => _val(_income);
  double get _savings$ => _val(_savings);
  double get _assigned => _amounts.values.fold(0.0, (a, c) => a + _val(c));
  double get _left => _income$ - _savings$ - _assigned;

  /// Fill every category with what the user usually spends there (rounded up to P10).
  void _fillFromHistory() {
    for (final c in _cats) {
      final avg = store.avgSpendFor(c);
      _amounts[c]!.text = avg <= 0 ? '' : ((avg / 10).ceil() * 10).toString();
    }
  }

  /// Spread what's left evenly over the categories that already have an amount.
  void _spreadLeftover() {
    final withAmount = _cats.where((c) => _val(_amounts[c]!) > 0).toList();
    if (withAmount.isEmpty || _left <= 0) return;
    final each = (_left / withAmount.length).floorToDouble();
    for (final c in withAmount) {
      _amounts[c]!.text = _fmt(_val(_amounts[c]!) + each);
    }
  }

  Future<void> _save() async {
    if (_income$ <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your monthly income first.')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await store.saveBudgetPlan(_income$, _savings$, {for (final c in _cats) c: _val(_amounts[c]!)});
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Budget saved.')));
    } catch (_) {
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't save. Check your connection.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    final leftColor = left.abs() < 0.5
        ? AppColors.income
        : (left < 0 ? const Color(0xFFD0573F) : AppColors.primary);
    return Scaffold(
      appBar: AppBar(title: const Text('Make a budget'), backgroundColor: AppColors.bg),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: leftColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(
                child: Text(
                  left.abs() < 0.5
                      ? 'Every pula has a job ✓'
                      : (left > 0 ? 'Left to assign' : 'Over your income by'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: leftColor),
                ),
              ),
              Text(pula(left.abs()), style: TextStyle(fontWeight: FontWeight.w800, color: leftColor)),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Save budget'),
          ),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        const Text(
          'Start with what comes in each month, put some aside, then give every category an amount '
          'until nothing is left to assign.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        BCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _MoneyField(
              controller: _income,
              label: 'Monthly income',
              hint: store.avgMonthlyIncome > 0
                  ? 'On average P${store.avgMonthlyIncome.round()} came in each month'
                  : 'Salary, allowance, money you get each month',
              icon: Icons.south_west,
            ),
            const SizedBox(height: 12),
            _MoneyField(
              controller: _savings,
              label: 'Save each month (optional)',
              hint: _income$ > 0 ? '20% would be P${(_income$ * 0.2).round()}' : 'Set aside before spending',
              icon: Icons.savings_outlined,
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const Expanded(
            child: Text('Spending per category',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
          if (store.hasData)
            TextButton(onPressed: _fillFromHistory, child: const Text('Use my usual spending')),
        ]),
        BCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: Column(children: [
            for (final c in _cats)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: c.color.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)),
                    child: Icon(c.icon, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (store.avgSpendFor(c) > 0)
                        Text('Usually ${pula(store.avgSpendFor(c), decimals: false)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    ]),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _amounts[c],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(prefixText: 'P ', hintText: '0', isDense: true),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        if (_left > 0.5 && _assigned > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _spreadLeftover,
              child: Text('Spread the ${pula(_left, decimals: false)} left over these categories'),
            ),
          ),
      ]),
    );
  }
}

class _MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  const _MoneyField({required this.controller, required this.label, required this.hint, required this.icon});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          prefixText: 'P ',
          prefixIcon: Icon(icon),
        ),
      );
}
