import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../theme/app_theme.dart';

const _incomeColor = Color(0xFF2E9E6B);
const _balanceColor = Color(0xFFB8C2D0);
const _leftOverColor = Color(0xFF5BB0E8);

/// Money-flow (Sankey) diagram: money in on the left, flowing into each
/// category, bank charges and "left over" on the right. If more went out than
/// came in, the extra is shown coming "from your balance".
class FlowChart extends StatelessWidget {
  final FlowData data;
  const FlowChart(this.data, {super.key});

  /// Keep the diagram readable: biggest 6 outflows, the rest merged.
  List<(String, double, Color)> get _right {
    final entries = data.outflows.entries.toList();
    final out = <(String, double, Color)>[];
    var rest = 0.0;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (i < 6 || entries.length == 7) {
        out.add((e.key.label, e.value, e.key.color));
      } else {
        rest += e.value;
      }
    }
    if (rest > 0) out.add(('Everything else', rest, Cat.other.color));
    if (data.leftOver > 0) out.add(('Left over', data.leftOver, _leftOverColor));
    return out;
  }

  List<(String, double, Color)> get _left => [
        if (data.income > 0) ('Money in', data.income, _incomeColor),
        if (data.fromBalance > 0) ('From your balance', data.fromBalance, _balanceColor),
      ];

  @override
  Widget build(BuildContext context) {
    final right = _right;
    final left = _left;
    if (right.isEmpty || left.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Not enough data for this period', style: TextStyle(color: AppColors.muted)),
      );
    }
    final height = math.max(220.0, right.length * 34.0);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _FlowPainter(left, right)),
    );
  }
}

class _FlowPainter extends CustomPainter {
  final List<(String, double, Color)> left;
  final List<(String, double, Color)> right;
  _FlowPainter(this.left, this.right);

  static const _barW = 10.0;
  static const _gap = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final total = left.fold(0.0, (a, e) => a + e.$2);
    if (total <= 0) return;
    final leftX = 0.0;
    final rightX = size.width * 0.46;

    // Vertical scale shared by both sides so bands keep their thickness.
    final usableRight = size.height - _gap * (right.length - 1);
    final usableLeft = size.height - _gap * (left.length - 1);
    final scale = math.min(usableRight, usableLeft) / total;

    // Left nodes.
    var y = 0.0;
    final leftSpans = <(double, double)>[];
    for (final (_, v, c) in left) {
      final h = math.max(2.0, v * scale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(leftX, y, _barW, h), const Radius.circular(3)),
        Paint()..color = c,
      );
      leftSpans.add((y, y + h));
      y += h + _gap;
    }

    // Right nodes, and a continuous "cursor" down the left stack for bands.
    var ry = 0.0;
    var li = 0;
    var lCursor = leftSpans.first.$1;
    final band = Paint()..style = PaintingStyle.fill;
    final labelYs = <double>[];
    for (final (_, v, c) in right) {
      final h = math.max(2.0, v * scale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(rightX, ry, _barW, h), const Radius.circular(3)),
        Paint()..color = c,
      );

      // Band from the left (possibly spanning two left nodes) to this node.
      var remaining = h;
      var target = ry;
      while (remaining > 0.01 && li < leftSpans.length) {
        final avail = leftSpans[li].$2 - lCursor;
        final take = math.min(avail, remaining);
        _drawBand(canvas, band..color = c.withValues(alpha: 0.35), leftX + _barW, lCursor, take, rightX, target);
        lCursor += take;
        target += take;
        remaining -= take;
        if (leftSpans[li].$2 - lCursor < 0.01 && li + 1 < leftSpans.length) {
          li++;
          lCursor = leftSpans[li].$1;
        }
      }
      labelYs.add(ry + h / 2);
      ry += h + _gap;
    }

    // Right labels, nudged apart so they never overlap.
    const minGap = 30.0;
    for (var i = 1; i < labelYs.length; i++) {
      if (labelYs[i] - labelYs[i - 1] < minGap) labelYs[i] = labelYs[i - 1] + minGap;
    }
    final overflow = labelYs.isEmpty ? 0 : labelYs.last + 14 - size.height;
    for (var i = 0; i < labelYs.length; i++) {
      final (name, v, _) = right[i];
      final yy = labelYs[i] - (overflow > 0 ? overflow * i / math.max(1, labelYs.length - 1) : 0);
      _label(canvas, Offset(rightX + _barW + 8, yy), name, pula(v, decimals: false), size.width - rightX - _barW - 8);
    }

    // Left labels inside the band area, next to their node.
    for (var i = 0; i < left.length; i++) {
      final (name, v, _) = left[i];
      final (top, bottom) = leftSpans[i];
      final yy = math.min(math.max((top + bottom) / 2, 14.0), size.height - 14);
      _label(canvas, Offset(leftX + _barW + 6, yy), name, pula(v, decimals: false), rightX - _barW - 12, onBand: true);
    }
  }

  void _drawBand(Canvas canvas, Paint p, double x0, double y0, double h, double x1, double y1) {
    final mid = (x0 + x1) / 2;
    final path = Path()
      ..moveTo(x0, y0)
      ..cubicTo(mid, y0, mid, y1, x1, y1)
      ..lineTo(x1, y1 + h)
      ..cubicTo(mid, y1 + h, mid, y0 + h, x0, y0 + h)
      ..close();
    canvas.drawPath(path, p);
  }

  void _label(Canvas canvas, Offset at, String name, String value, double maxW, {bool onBand = false}) {
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(
          text: '$name\n',
          style: TextStyle(fontSize: 11, color: AppColors.ink, fontWeight: onBand ? FontWeight.w700 : FontWeight.w500),
        ),
        TextSpan(text: value, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxW));
    tp.paint(canvas, Offset(at.dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) => old.left != left || old.right != right;
}

/// Opening balance → +income → −spending → −charges → ±transfers → closing.
class BooksWaterfall extends StatelessWidget {
  final BooksCheck check;
  const BooksWaterfall(this.check, {super.key});

  @override
  Widget build(BuildContext context) {
    final opening = check.opening ?? 0;
    final steps = <(String, double, Color, bool)>[
      ('Opening', opening, AppColors.primary, true),
      ('Money in', check.income, _incomeColor, false),
      ('Spending', check.spending, const Color(0xFFF5B88A), false),
      ('Charges', check.charges, Cat.charges.color, false),
      ('Transfers', check.transfers, Cat.transfer.color, false),
      ('Closing', check.closing ?? (opening + check.income + check.spending + check.charges + check.transfers),
          AppColors.primary, true),
    ];
    return SizedBox(height: 220, width: double.infinity, child: CustomPaint(painter: _WaterfallPainter(steps)));
  }
}

class _WaterfallPainter extends CustomPainter {
  final List<(String, double, Color, bool)> steps; // label, value, colour, isTotal
  _WaterfallPainter(this.steps);

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 34.0;
    final chartH = size.height - labelH - 16;
    // Running totals to find the range.
    final tops = <(double, double)>[];
    var running = 0.0;
    for (final (_, v, _, isTotal) in steps) {
      if (isTotal) {
        tops.add((0, v));
        running = v;
      } else {
        tops.add((running, running + v));
        running += v;
      }
    }
    final all = [0.0, for (final t in tops) ...[t.$1, t.$2]];
    final lo = all.reduce(math.min), hi = all.reduce(math.max);
    final span = (hi - lo) == 0 ? 1.0 : hi - lo;
    double yOf(double v) => 16 + chartH * (1 - (v - lo) / span);

    final slot = size.width / steps.length;
    final barW = slot * 0.56;
    // Zero line
    canvas.drawLine(Offset(0, yOf(0)), Offset(size.width, yOf(0)), Paint()..color = const Color(0xFFE3EAF2));

    for (var i = 0; i < steps.length; i++) {
      final (label, v, color, _) = steps[i];
      final (a, b) = tops[i];
      final x = slot * i + (slot - barW) / 2;
      final top = math.min(yOf(a), yOf(b));
      final h = math.max(2.0, (yOf(a) - yOf(b)).abs());
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, top, barW, h), const Radius.circular(4)),
        Paint()..color = color,
      );
      // Connector to next bar
      if (i < steps.length - 1) {
        canvas.drawLine(
          Offset(x + barW, yOf(b)),
          Offset(x + slot, yOf(b)),
          Paint()
            ..color = const Color(0xFFB8C2D0)
            ..strokeWidth = 1,
        );
      }
      final value = steps[i].$4 ? pula(v, decimals: false) : pula(v, sign: true, decimals: false);
      _text(canvas, value, Offset(slot * i + slot / 2, top - 14), 10, AppColors.ink, slot);
      _text(canvas, label, Offset(slot * i + slot / 2, size.height - labelH + 6), 10, AppColors.muted, slot);
    }
  }

  void _text(Canvas c, String s, Offset center, double size, Color color, double maxW) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    )..layout(maxWidth: maxW);
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter old) => old.steps != steps;
}
