import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Categorical palette in fixed order (validated: CVD-safe on light surfaces).
/// A month's colour comes from its position in the user's history, so it never
/// changes when other months are toggled on or off.
const _monthColors = [
  Color(0xFF2A78D6), // blue
  Color(0xFFEB6834), // orange
  Color(0xFF1BAF7A), // aqua
  Color(0xFFEDA100), // yellow
  Color(0xFFE87BA4), // magenta
  Color(0xFF008300), // green
  Color(0xFF6250D6), // violet
  Color(0xFFE34948), // red
];

enum _Measure { allOut, moneyIn, category }

enum _Shape { running, weekly }

/// "Compare months": one line per month for a chosen measure (all spending,
/// money in, or one category), as a running total through the month or as
/// weekly totals. Tap or drag on the chart to read the values for a day/week.
class MonthCompareCard extends StatefulWidget {
  const MonthCompareCard({super.key});

  @override
  State<MonthCompareCard> createState() => _MonthCompareCardState();
}

class _MonthCompareCardState extends State<MonthCompareCard> {
  _Measure _measure = _Measure.allOut;
  Cat _cat = Cat.food;
  _Shape _shape = _Shape.running;
  Set<DateTime>? _picked; // null = default (latest 3)
  int? _hover; // x index under the finger

  static const _maxMonths = 4;

  List<DateTime> get _all => store.monthsOldestFirst;

  Set<DateTime> get _selected {
    final all = _all;
    final p = _picked?.where(all.contains).toSet();
    if (p != null && p.isNotEmpty) return p;
    return all.skip(math.max(0, all.length - 3)).toSet();
  }

  Color _colorOf(DateTime m) => _monthColors[_all.indexOf(m) % _monthColors.length];

  List<double> _series(DateTime m) {
    final daily = store.dailyAmounts(
      m,
      cat: _measure == _Measure.category ? _cat : null,
      moneyIn: _measure == _Measure.moneyIn,
    );
    if (_shape == _Shape.weekly) {
      return [
        for (var w = 0; w * 7 < daily.length; w++)
          daily.skip(w * 7).take(7).fold(0.0, (a, b) => a + b),
      ];
    }
    var run = 0.0;
    return [for (final v in daily) run += v];
  }

  String get _measureLabel => switch (_measure) {
        _Measure.allOut => 'All money out',
        _Measure.moneyIn => 'Money in',
        _Measure.category => _cat.label,
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build());

  Widget _build() {
    final all = _all;
    if (all.length < 2) return const SizedBox.shrink();
    final selected = all.where(_selected.contains).toList(); // oldest → newest
    final series = {for (final m in selected) m: _series(m)};
    final totals = {for (final m in selected) m: _total(m)};

    return BCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Compare months',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 4),
        Text(
          _shape == _Shape.running
              ? '$_measureLabel, adding up through each month'
              : '$_measureLabel, week by week',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 12),

        // What to compare
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('All money out', _measure == _Measure.allOut, () => setState(() => _measure = _Measure.allOut)),
            _chip('Money in', _measure == _Measure.moneyIn, () => setState(() => _measure = _Measure.moneyIn)),
            for (final c in store.activeOutflowCats)
              _chip(c.label, _measure == _Measure.category && _cat == c, () => setState(() {
                    _measure = _Measure.category;
                    _cat = c;
                  }), icon: c.icon),
          ]),
        ),
        const SizedBox(height: 8),

        // Which months
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final m in all)
            FilterChip(
              label: Text(monthShort(m) + (all.first.year != all.last.year ? ' ${m.year % 100}' : '')),
              selected: selected.contains(m),
              showCheckmark: false,
              avatar: CircleAvatar(backgroundColor: _colorOf(m), radius: 5),
              onSelected: (on) => _toggle(m, on),
            ),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<_Shape>(
          segments: const [
            ButtonSegment(value: _Shape.running, label: Text('Running total')),
            ButtonSegment(value: _Shape.weekly, label: Text('Per week')),
          ],
          selected: {_shape},
          onSelectionChanged: (s) => setState(() {
            _shape = s.first;
            _hover = null;
          }),
        ),
        const SizedBox(height: 14),

        // Readout for the point under the finger
        SizedBox(
          height: 20,
          child: _hover == null
              ? const Text('Tap or drag on the chart to compare a day',
                  style: TextStyle(fontSize: 12, color: AppColors.muted))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    Text(_shape == _Shape.running ? 'By day ${_hover! + 1}: ' : 'Week ${_hover! + 1}: ',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    for (final m in selected)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: _colorOf(m), shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text(
                            '${monthShort(m)} ${_hover! < series[m]!.length ? pula(series[m]![_hover!], decimals: false) : '–'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.ink),
                          ),
                        ]),
                      ),
                  ]),
                ),
        ),
        const SizedBox(height: 6),

        // The chart
        LayoutBuilder(builder: (context, box) {
          final points = _shape == _Shape.running ? 31 : 5;
          void hit(Offset p) {
            final i = ((p.dx - _LinePainter.left) / (box.maxWidth - _LinePainter.left - _LinePainter.right) * (points - 1))
                .round()
                .clamp(0, points - 1);
            if (i != _hover) setState(() => _hover = i);
          }

          return GestureDetector(
            onTapDown: (d) => hit(d.localPosition),
            onHorizontalDragUpdate: (d) => hit(d.localPosition),
            child: SizedBox(
              height: 210,
              width: double.infinity,
              child: CustomPaint(
                painter: _LinePainter(
                  [for (final m in selected) (series[m]!, _colorOf(m))],
                  points: points,
                  xLabel: _shape == _Shape.running ? (int i) => '${i + 1}' : (int i) => 'W${i + 1}',
                  labelEvery: _shape == _Shape.running ? 5 : 1,
                  hover: _hover,
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),

        // Legend with totals and change vs the month before
        for (var i = 0; i < selected.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 14, height: 3, color: _colorOf(selected[i])),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  store.coversMonth(selected[i]) ? monthYear(selected[i]) : '${monthYear(selected[i])} (part)',
                  style: const TextStyle(color: AppColors.ink),
                ),
              ),
              Text(pula(totals[selected[i]]!, decimals: false),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              SizedBox(
                width: 70,
                child: Text(
                  i == 0 ? '' : _change(totals[selected[i - 1]]!, totals[selected[i]]!),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  double _total(DateTime m) =>
      store.dailyAmounts(m, cat: _measure == _Measure.category ? _cat : null, moneyIn: _measure == _Measure.moneyIn)
          .fold(0.0, (a, b) => a + b);

  String _change(double before, double now) {
    if (before <= 0) return '';
    final pct = ((now - before) / before * 100).round();
    if (pct == 0) return 'same';
    return pct > 0 ? '▲ $pct%' : '▼ ${-pct}%';
  }

  void _toggle(DateTime m, bool on) {
    final s = {..._selected};
    if (on) {
      if (s.length >= _maxMonths) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compare up to 4 months at a time — untick one first.')),
        );
        return;
      }
      s.add(m);
    } else {
      if (s.length <= 1) return; // keep at least one line
      s.remove(m);
    }
    setState(() => _picked = s);
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          avatar: icon == null ? null : Icon(icon, size: 16),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
}

class _LinePainter extends CustomPainter {
  final List<(List<double>, Color)> lines;
  final int points;
  final String Function(int) xLabel;
  final int labelEvery;
  final int? hover;
  _LinePainter(this.lines, {required this.points, required this.xLabel, required this.labelEvery, this.hover});

  static const left = 44.0, right = 8.0, top = 8.0, bottom = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    var maxV = 0.0;
    for (final (l, _) in lines) {
      for (final v in l) {
        maxV = math.max(maxV, v);
      }
    }
    final niceMax = _niceCeil(maxV <= 0 ? 1 : maxV);
    double x(int i) => left + (points <= 1 ? 0 : w * i / (points - 1));
    double y(double v) => top + h * (1 - v / niceMax);

    // Recessive grid + y labels (3 lines).
    final grid = Paint()
      ..color = const Color(0xFFE6ECF2)
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final v = niceMax * g / 3;
      canvas.drawLine(Offset(left, y(v)), Offset(left + w, y(v)), grid);
      _text(canvas, _short(v), Offset(left - 6, y(v)), align: TextAlign.right);
    }
    // x labels
    for (var i = 0; i < points; i += labelEvery) {
      _text(canvas, xLabel(i), Offset(x(i), size.height - bottom + 12), align: TextAlign.center);
    }

    // Hover crosshair
    if (hover != null) {
      canvas.drawLine(Offset(x(hover!), top), Offset(x(hover!), top + h),
          Paint()
            ..color = const Color(0xFF9AA8B8)
            ..strokeWidth = 1);
    }

    // Lines (2px), each with an end marker ringed by the surface.
    for (final (l, c) in lines) {
      if (l.isEmpty) continue;
      final path = Path()..moveTo(x(0), y(l[0]));
      for (var i = 1; i < l.length && i < points; i++) {
        path.lineTo(x(i), y(l[i]));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      final last = math.min(l.length, points) - 1;
      final markAt = hover != null && hover! <= last ? hover! : last;
      final p = Offset(x(markAt), y(l[markAt]));
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4, Paint()..color = c);
    }
  }

  static double _niceCeil(double v) {
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in const <double>[1, 2, 2.5, 5, 10]) {
      if (v <= m * mag) return m * mag;
    }
    return 10 * mag;
  }

  static String _short(double v) {
    if (v >= 1000) return 'P${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    return 'P${v.round()}';
  }

  void _text(Canvas c, String s, Offset at, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}
