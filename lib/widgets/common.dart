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
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.type == TxnType.transfer
                    ? AppColors.muted
                    : (t.isIncome ? AppColors.income : AppColors.expense),
              ),
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
          if (t.fee > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Bank fee for this: ${pula(t.fee)}',
                  style: TextStyle(fontSize: 12, color: Cat.charges.color, fontWeight: FontWeight.w600)),
            ),
          if (t.type == TxnType.income)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(store.isRegularIncome(t) ? 'Regular income (paid in more than one month)' : 'One-off income',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          if (t.flagged)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text("⚠ This amount didn't match the change in your balance. Check it against your statement.",
                  style: TextStyle(fontSize: 12, color: Color(0xFFD0573F))),
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
                  CatSource.rule => switch (t.cat) {
                      Cat.transfer => 'Money moved between your own accounts. Not counted as income or spending.',
                      Cat.charges => 'A bank fee or charge.',
                      Cat.income => 'Income: salary, allowance, interest or a refund.',
                      Cat.received => 'Money someone sent you. Counted as money in, not as income.',
                      _ => 'Matched a known merchant keyword.',
                    },
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
  const EmptyState({super.key, required this.onUpload});

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
          const SizedBox(height: 10),
          const Text(
            'The file is read on your phone and never uploaded. Only the transactions are saved, '
            'to your private account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
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

/// Money in, money out and what was left, for each month. Tap a month to open it.
class MonthBreakdown extends StatelessWidget {
  const MonthBreakdown({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() {
    final sums = store.monthSummaries;
    return BCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Month by month',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 4),
        Text('Average ${pula(store.avgMonthlySpent, decimals: false)} out a month · tap a month to open it',
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 10),
        const Row(children: [
          Expanded(flex: 4, child: Text('Month', style: _head)),
          Expanded(flex: 3, child: Text('In', textAlign: TextAlign.right, style: _head)),
          Expanded(flex: 3, child: Text('Out', textAlign: TextAlign.right, style: _head)),
          Expanded(flex: 3, child: Text('Left', textAlign: TextAlign.right, style: _head)),
        ]),
        const Divider(height: 14),
        for (final m in sums)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => store.month = m.month,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      store.coversMonth(m.month) ? monthLong(m.month) : '${monthLong(m.month)} (part)',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(pula(m.income, decimals: false),
                        textAlign: TextAlign.right, style: const TextStyle(color: AppColors.income)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(pula(m.spent, decimals: false), textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      pula(m.net, decimals: false),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: m.net >= 0 ? const Color(0xFF5BB0E8) : const Color(0xFFD0573F),
                      ),
                    ),
                  ),
                ]),
                if (m.charges > 0 || m.movedToOwn.abs() >= 0.01)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (m.charges > 0) 'incl. ${pula(m.charges)} bank charges',
                        if (m.movedToOwn >= 0.01) '${pula(m.movedToOwn, decimals: false)} moved to your accounts',
                        if (m.movedToOwn <= -0.01) '${pula(-m.movedToOwn, decimals: false)} brought back from your accounts',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}

const _head = TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600);

/// Circle with the user's initials.
class UserAvatar extends StatelessWidget {
  final String name;
  final String email;
  final double radius;
  const UserAvatar({super.key, required this.name, required this.email, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? (email.isEmpty ? '?' : email[0].toUpperCase())
        : parts.take(2).map((p) => p[0].toUpperCase()).join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFDCEBF8),
      child: Text(initials, style: TextStyle(fontSize: radius * 0.75, color: AppColors.ink)),
    );
  }
}
