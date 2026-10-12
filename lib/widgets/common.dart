import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/spending_store.dart';
import '../theme/app_theme.dart';

class BCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const BCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: AppColors.primary.withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        child: child,
      );
}

class TxnTile extends StatelessWidget {
  final Txn t;
  final VoidCallback? onTap;
  const TxnTile(this.t, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final unknown = t.source == CatSource.none && !t.isIncome;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: t.cat.color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(13)),
            child: Icon(unknown ? Icons.help_outline : t.cat.icon, size: 20, color: AppColors.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
              Row(children: [
                Flexible(
                  child: Text(
                    unknown ? 'Tap to choose a category' : t.sub,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: unknown ? AppColors.primary : AppColors.muted),
                  ),
                ),
                if (t.source == CatSource.model) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.auto_awesome, size: 12, color: AppColors.primary),
                ],
                if (t.source == CatSource.user) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle, size: 12, color: AppColors.income),
                ],
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              pula(t.amount, sign: true),
              style: TextStyle(fontWeight: FontWeight.w700, color: t.isIncome ? AppColors.income : AppColors.expense),
            ),
            Text(shortDate(t.date), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ]),
      ),
    );
  }
}

/// Bottom sheet to correct a transaction's category. The choice teaches the model.
Future<void> showCategorySheet(BuildContext context, Txn t) async {
  final messenger = ScaffoldMessenger.of(context);
  final picked = await showModalBottomSheet<Cat>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text('${pula(t.amount, sign: true)} · ${shortDate(t.date)} ${t.date.year}',
              style: const TextStyle(color: AppColors.muted)),
          if (t.raw.isNotEmpty && t.raw != t.name)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('On statement: ${t.raw}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFEAF4FC), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(switch (t.source) {
                  CatSource.user => 'You taught bbt this one.',
                  CatSource.model => 'bbt guessed this from what you\'ve taught it (${(t.confidence * 100).round()}% sure).',
                  CatSource.rule => 'Matched a known merchant keyword.',
                  CatSource.none => "bbt doesn't recognise this yet.",
                }, style: const TextStyle(fontSize: 12, color: AppColors.ink)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          const Text('What is this?', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in Cat.values)
              ChoiceChip(
                avatar: Icon(c.icon, size: 16),
                label: Text(c.label),
                selected: t.cat == c && t.source != CatSource.none,
                onSelected: (_) => Navigator.pop(ctx, c),
              ),
          ]),
          const SizedBox(height: 12),
          const Text(
            'bbt remembers this merchant and learns from it to categorise similar transactions.',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ]),
      ),
    ),
  );
  if (picked == null) return;
  final changed = await store.teach(t, picked);
  final others = changed - (t.cat == picked ? 0 : 1);
  messenger.showSnackBar(SnackBar(
    content: Text(others > 0
        ? 'Learned: ${t.name} → ${picked.label}. Updated $others similar transaction${others == 1 ? '' : 's'}.'
        : 'Learned: ${t.name} → ${picked.label}.'),
  ));
}

class DonutChart extends StatelessWidget {
  final Map<Cat, double> data;
  final double size;
  final Widget? center;
  const DonutChart({super.key, required this.data, this.size = 190, this.center});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _DonutPainter(data), child: Center(child: center)),
      );
}

class _DonutPainter extends CustomPainter {
  final Map<Cat, double> data;
  _DonutPainter(this.data);

  @override
  void paint(Canvas canvas, Size s) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(14, 14, s.width - 28, s.height - 28);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26;
    var start = -math.pi / 2;
    data.forEach((cat, v) {
      final sweep = v / total * 2 * math.pi;
      p.color = cat.color;
      canvas.drawArc(rect, start, sweep - 0.05, false, p);
      start += sweep;
    });
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.data != data;
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionTitle(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink)),
        if (subtitle != null) Text(subtitle!, style: const TextStyle(color: AppColors.muted)),
      ]);
}

/// Shown on every tab until a statement has been uploaded.
class EmptyState extends StatelessWidget {
  final VoidCallback onUpload;
  final VoidCallback onSample;
  const EmptyState({super.key, required this.onUpload, required this.onSample});

  @override
  Widget build(BuildContext context) => BCard(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: const Color(0xFFEAF4FC), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.description_outlined, size: 30, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          const Text('Upload a bank statement',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 6),
          const Text(
            "PDF or CSV from your bank. We'll sort every transaction into categories and show where your money went.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onUpload,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: const Text('Upload statement'),
          ),
          TextButton(onPressed: onSample, child: const Text('Try with sample data')),
          const Text('Your statement is read on this device and never uploaded to a server.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      );
}

/// [All 3 months] [Aug] [Sep] [Oct] — picks the period every screen shows.
class MonthChips extends StatelessWidget {
  const MonthChips({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final ms = store.months.reversed.toList(); // oldest first
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ChoiceChip(
                label: Text('All ${ms.length} months'),
                selected: store.allMonths,
                onSelected: (_) => store.selectAllMonths(),
              ),
              for (final m in ms)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(ms.first.year == ms.last.year ? monthLong(m) : '${monthShort(m)} ${m.year}'),
                    selected: !store.allMonths && store.month == m,
                    onSelected: (_) => store.month = m,
                  ),
                ),
            ]),
          );
        },
      );
}

/// Month-by-month spending and money in. Tap a row to open that month.
class MonthBreakdown extends StatelessWidget {
  const MonthBreakdown({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() {
    final sums = store.monthSummaries;
    final maxSpent = sums.fold(0.0, (a, s) => s.spent > a ? s.spent : a);
    return BCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Month by month',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 4),
        Text('Average ${pula(store.avgMonthlySpent, decimals: false)} spent a month',
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 8),
        for (final s in sums)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => store.month = s.month,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      store.coversMonth(s.month) ? monthYear(s.month) : '${monthYear(s.month)} (part)',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                  ),
                  Text(pula(-s.spent, decimals: false), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  Text(pula(s.income, sign: true, decimals: false),
                      style: const TextStyle(color: AppColors.income, fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: maxSpent == 0 ? 0.0 : s.spent / maxSpent,
                    minHeight: 6,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
