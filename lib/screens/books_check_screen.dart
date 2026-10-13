import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

/// "Do the books balance?" for one statement:
/// opening + income − spending − charges ± transfers = closing.
class BooksCheckScreen extends StatelessWidget {
  final StatementRecord statement;
  const BooksCheckScreen(this.statement, {super.key});

  @override
  Widget build(BuildContext context) {
    final st = statement;
    final check = store.booksCheck(st);
    final range = st.periodStart == null || st.periodEnd == null
        ? ''
        : '${shortDate(st.periodStart!)} ${st.periodStart!.year} – ${shortDate(st.periodEnd!)} ${st.periodEnd!.year}';

    return Scaffold(
      appBar: AppBar(title: Text(st.bank ?? 'Statement'), backgroundColor: AppColors.bg),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        Text(range, style: const TextStyle(color: AppColors.muted)),
        Text(st.fileName, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 14),
        if (check == null)
          const BCard(child: Text('No dates were read from this statement.'))
        else ...[
          _Status(check),
          const SizedBox(height: 14),
          BCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Balancing the books',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 14),
              BooksWaterfall(check),
              const SizedBox(height: 10),
              _Row('Opening balance', check.opening, bold: true),
              _Row('+ Money in', check.income),
              _Row('− Spending', check.spending),
              _Row('− Bank charges', check.charges),
              if (check.statedCharges != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    (check.statedCharges! + check.charges).abs() < 0.01
                        ? "✓ Matches the statement's own fee total (${pula(check.statedCharges!)})"
                        : "⚠ The statement's own fee total is ${pula(check.statedCharges!)}",
                    style: TextStyle(
                      fontSize: 12,
                      color: (check.statedCharges! + check.charges).abs() < 0.01
                          ? AppColors.income
                          : const Color(0xFFD0573F),
                    ),
                  ),
                ),
              _Row('± Transfers between your accounts', check.transfers),
              const Divider(),
              _Row('= Should close at', check.expectedClosing, bold: true),
              _Row('Statement says', check.closing, bold: true),
            ]),
          ),
          if (check.flagged.isNotEmpty) ...[
            const SizedBox(height: 14),
            BCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${check.flagged.length} line${check.flagged.length == 1 ? '' : 's'} to check',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 4),
                const Text(
                  "These amounts didn't match the change in the running balance, so they may have been read wrongly. "
                  'Compare them with your statement.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                for (final t in check.flagged) TxnTile(t, onTap: () => showCategorySheet(context, t)),
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

class _Status extends StatelessWidget {
  final BooksCheck check;
  const _Status(this.check);

  @override
  Widget build(BuildContext context) {
    final diff = check.difference;
    final (icon, color, title, body) = diff == null
        ? (
            Icons.info_outline,
            AppColors.primary,
            "Can't check this one",
            "The statement didn't include an opening and closing balance, so bbt can't confirm every line was read.",
          )
        : check.balanced
            ? (
                Icons.check_circle,
                AppColors.income,
                'The books balance',
                'Every transaction adds up exactly to the closing balance on your statement.',
              )
            : (
                Icons.warning_amber_rounded,
                const Color(0xFFD0573F),
                "${pula(diff.abs())} doesn't add up",
                'Some lines may have been missed or read wrongly. The lines to check are listed below.',
              );
    return BCard(
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(body, style: const TextStyle(fontSize: 12, color: AppColors.ink)),
          ]),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double? value;
  final bool bold;
  const _Row(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: AppColors.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value == null ? '—' : pula(value!, sign: !bold), style: style),
      ]),
    );
  }
}
