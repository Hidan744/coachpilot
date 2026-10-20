// Графики для профиля игрока и дашбордов: радар, линии, столбцы «было/стало», кольцо, бублик.
// Без сторонних библиотек: CustomPainter, единый стиль клуба.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

const chartGrey = Color(0xFF6B6B74);
const chartBlue = Color(0xFF4FC3F7);
const chartPalette = [AppColors.red, Colors.white, chartBlue, AppColors.warn, AppColors.good, Color(0xFFBA68C8)];

/// Карточка блока дашборда: заголовок капсом и содержимое.
class DashCard extends StatelessWidget {
  const DashCard({super.key, required this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(14)});

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.6)),
        ),
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontFamily: AppTheme.display,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: AppColors.text,
                ),
              ),
            ),
            ?trailing,
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );
}

/// Показатель: большое число, подпись, изменение и полоса.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.delta, this.caption, this.progress, this.icon});

  final String label, value;

  /// Изменение в процентах или пунктах: «+8%». Положительное — зелёное.
  final String? delta;
  final String? caption;
  final double? progress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final up = delta != null && !delta!.startsWith('-') && !delta!.startsWith('−') && delta != '0';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: AppColors.red), const SizedBox(width: 6)],
          Expanded(
            child: Text(label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, letterSpacing: 1, color: AppColors.textMuted)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(fontFamily: AppTheme.display, fontSize: 30, fontWeight: FontWeight.w700)),
            ),
          ),
          if (delta != null) ...[
            const SizedBox(width: 8),
            Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: up ? AppColors.good : AppColors.warn),
            Text(delta!, style: TextStyle(color: up ? AppColors.good : AppColors.warn, fontWeight: FontWeight.w600)),
          ],
        ]),
        if (caption != null) Text(caption!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        if (progress != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress!.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.outline,
            ),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- радар

class RadarChart extends StatelessWidget {
  const RadarChart({super.key, required this.labels, required this.values, this.compare, this.size = 240, this.showValues = true});

  final List<String> labels;

  /// Значения 0–100 (null — нет данных).
  final List<num?> values;

  /// Прежние значения для сравнения (серым).
  final List<num?>? compare;
  final double size;
  final bool showValues;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Радар: ${[for (var i = 0; i < labels.length; i++) '${labels[i]} ${values[i] ?? '—'}'].join(', ')}',
        child: SizedBox(
          height: size,
          child: CustomPaint(painter: _RadarPainter(labels, values, compare, showValues), size: Size.infinite),
        ),
      );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.labels, this.values, this.compare, this.showValues);

  final List<String> labels;
  final List<num?> values;
  final List<num?>? compare;
  final bool showValues;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n < 3) return;
    final c = Offset(size.width / 2, size.height / 2 + 4);
    final r = math.min(size.width, size.height) / 2 - 34;
    Offset pt(int i, double f) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      return c + Offset(math.cos(a), math.sin(a)) * r * f;
    }

    final grid = Paint()
      ..color = AppColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final f in [0.25, 0.5, 0.75, 1.0]) {
      final p = Path()..moveTo(pt(0, f).dx, pt(0, f).dy);
      for (var i = 1; i < n; i++) {
        p.lineTo(pt(i, f).dx, pt(i, f).dy);
      }
      canvas.drawPath(p..close(), grid);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, pt(i, 1), grid);
    }

    void shape(List<num?> v, Color color, {bool dots = true}) {
      final p = Path();
      for (var i = 0; i < n; i++) {
        final q = pt(i, ((v[i] ?? 0) / 100).clamp(0.0, 1.0).toDouble());
        i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
      }
      p.close();
      canvas.drawPath(p, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawPath(
        p,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (dots) {
        for (var i = 0; i < n; i++) {
          if (v[i] != null) canvas.drawCircle(pt(i, ((v[i]!) / 100).clamp(0.0, 1.0).toDouble()), 3.5, Paint()..color = color);
        }
      }
    }

    if (compare != null) shape(compare!, chartGrey, dots: false);
    shape(values, AppColors.red);

    for (var i = 0; i < n; i++) {
      final q = pt(i, 1.18);
      final text = showValues && values[i] != null ? '${labels[i]}\n${values[i]!.round()}' : labels[i];
      final tp = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(color: AppColors.text, fontSize: 10.5, height: 1.15)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 112);
      tp.paint(canvas, q - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.values != values || old.compare != compare || old.labels != labels;
}

// ---------------------------------------------------------------- линии

class LineSeries {
  const LineSeries(this.name, this.color, this.values);

  final String name;
  final Color color;

  /// Значение для каждой подписи оси X (null — пропуск).
  final List<double?> values;
}

class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.xLabels, required this.series, this.height = 180, this.minY, this.maxY, this.unit = ''});

  final List<String> xLabels;
  final List<LineSeries> series;
  final double height;
  final double? minY, maxY;
  final String unit;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: height,
          child: CustomPaint(painter: _LinePainter(xLabels, series, minY, maxY, unit), size: Size.infinite),
        ),
        if (series.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            for (final s in series)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(s.name, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
          ]),
        ],
      ]);
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.xLabels, this.series, this.minY, this.maxY, this.unit);

  final List<String> xLabels;
  final List<LineSeries> series;
  final double? minY, maxY;
  final String unit;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in series) ...s.values.whereType<double>()];
    if (all.isEmpty || xLabels.isEmpty) return;
    var lo = minY ?? all.reduce(math.min), hi = maxY ?? all.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.1;
    if (minY == null) lo -= pad;
    if (maxY == null) hi += pad;
    const left = 36.0, bottom = 22.0;
    final w = size.width - left - 8, h = size.height - bottom - 6;
    double x(int i) => left + (xLabels.length == 1 ? w / 2 : w * i / (xLabels.length - 1));
    double y(double v) => 6 + h * (1 - (v - lo) / (hi - lo));
    final grid = Paint()..color = AppColors.outline.withValues(alpha: 0.6);
    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      canvas.drawLine(Offset(left, y(v)), Offset(size.width - 8, y(v)), grid);
      _label(canvas, _fmt(v), Offset(left - 6, y(v)), align: TextAlign.right);
    }
    final step = (xLabels.length / 6).ceil();
    for (var i = 0; i < xLabels.length; i += step) {
      _label(canvas, xLabels[i], Offset(x(i), size.height - 9), align: TextAlign.center);
    }
    for (final s in series) {
      final p = Path();
      var started = false;
      for (var i = 0; i < s.values.length && i < xLabels.length; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final q = Offset(x(i), y(v));
        started ? p.lineTo(q.dx, q.dy) : p.moveTo(q.dx, q.dy);
        started = true;
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
      for (var i = 0; i < s.values.length && i < xLabels.length; i++) {
        final v = s.values[i];
        if (v != null) canvas.drawCircle(Offset(x(i), y(v)), 3.5, Paint()..color = s.color);
      }
    }
  }

  String _fmt(double v) => v.abs() >= 100 || v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  void _label(Canvas canvas, String text, Offset at, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => -tp.width,
      TextAlign.center => -tp.width / 2,
      _ => 0.0,
    };
    tp.paint(canvas, at + Offset(dx, -tp.height / 2));
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.series != series || old.xLabels != xLabels;
}

// ---------------------------------------------------------------- столбцы

class BarGroup {
  const BarGroup(this.label, this.values, {this.caption});

  final String label;

  /// Значения столбцов группы (null — нет данных), по цветам [colors].
  final List<double?> values;
  final String? caption;
}

/// Сгруппированные столбцы: «было / стало», посещаемость по неделям.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.groups,
    this.colors = const [chartGrey, AppColors.red],
    this.legend,
    this.height = 160,
    this.maxY,
    this.valueLabels = true,
    this.percent = false,
  });

  final List<BarGroup> groups;
  final List<Color> colors;
  final List<String>? legend;
  final double height;
  final double? maxY;
  final bool valueLabels, percent;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: height,
          child: CustomPaint(painter: _BarPainter(groups, colors, maxY, valueLabels, percent), size: Size.infinite),
        ),
        if (legend != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, children: [
            for (var i = 0; i < legend!.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(legend![i], style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
          ]),
        ],
      ]);
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.groups, this.colors, this.maxY, this.valueLabels, this.percent);

  final List<BarGroup> groups;
  final List<Color> colors;
  final double? maxY;
  final bool valueLabels, percent;

  @override
  void paint(Canvas canvas, Size size) {
    if (groups.isEmpty) return;
    final all = [for (final g in groups) ...g.values.whereType<double>()];
    final hi = maxY ?? (all.isEmpty ? 1 : all.reduce(math.max) * 1.15);
    const bottom = 30.0, top = 14.0;
    final h = size.height - bottom - top;
    final gw = size.width / groups.length;
    final n = groups.map((g) => g.values.length).fold(1, math.max);
    final bw = math.min(26.0, gw * 0.7 / n);
    canvas.drawLine(Offset(0, top + h), Offset(size.width, top + h), Paint()..color = AppColors.outline);
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      final x0 = gw * gi + (gw - bw * g.values.length - 3 * (g.values.length - 1)) / 2;
      for (var k = 0; k < g.values.length; k++) {
        final v = g.values[k];
        final x = x0 + k * (bw + 3);
        if (v == null) continue;
        final bh = hi == 0 ? 0.0 : h * (v / hi).clamp(0.0, 1.0);
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(x, top + h - bh, bw, bh),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rect, Paint()..color = colors[k % colors.length]);
        if (valueLabels && bw >= 14) {
          _text(canvas, percent ? '${(v * 100).round()}%' : _fmt(v), Offset(x + bw / 2, top + h - bh - 8), 10, AppColors.text);
        }
      }
      _text(canvas, g.label, Offset(gw * gi + gw / 2, top + h + 10), 10, AppColors.textMuted, maxWidth: gw - 2);
      if (g.caption != null) {
        _text(canvas, g.caption!, Offset(gw * gi + gw / 2, top + h + 23), 10,
            g.caption!.startsWith('-') ? AppColors.warn : AppColors.good, maxWidth: gw - 2);
      }
    }
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(v.abs() < 10 ? 2 : 1);

  void _text(Canvas canvas, String s, Offset center, double size, Color color, {double maxWidth = 80}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(10, maxWidth));
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.groups != groups;
}

// ---------------------------------------------------------------- кольцо и бублик

/// Кольцо прогресса с числом в центре.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.center, this.caption, this.size = 120});

  /// 0..1
  final double value;
  final String center;
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(value),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(center, style: TextStyle(fontFamily: AppTheme.display, fontSize: size * 0.24, fontWeight: FontWeight.w700)),
              if (caption != null)
                Text(caption!, textAlign: TextAlign.center, style: TextStyle(fontSize: size * 0.09, color: AppColors.textMuted)),
            ]),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 8;
    final c = size.center(Offset.zero);
    final base = Paint()
      ..color = AppColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(c, r, base);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * value.clamp(0.0, 1.0),
      false,
      base
        ..color = AppColors.red
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// Бублик со структурой (например, нагрузки по направлениям).
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.parts, this.size = 130});

  final Map<String, num> parts;
  final double size;

  @override
  Widget build(BuildContext context) {
    final total = parts.values.fold<num>(0, (a, b) => a + b);
    final entries = parts.entries.where((e) => e.value > 0).toList();
    return Row(children: [
      SizedBox.square(dimension: size, child: CustomPaint(painter: _DonutPainter([for (final e in entries) e.value.toDouble()]))),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: chartPalette[i % chartPalette.length], shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(entries[i].key, style: const TextStyle(fontSize: 13))),
                Text('${(entries[i].value * 100 / (total == 0 ? 1 : total)).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 12;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22;
    if (total == 0) {
      canvas.drawCircle(c, r, p..color = AppColors.outline);
      return;
    }
    var a = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, sweep - 0.03, false, p..color = chartPalette[i % chartPalette.length]);
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values != values;
}

/// Горизонтальная полоса «сейчас → цель» с отметкой цели.
class TargetBar extends StatelessWidget {
  const TargetBar({super.key, required this.progress, this.height = 10});

  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Stack(children: [
          Container(height: height, decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(height))),
          Container(
            height: height,
            width: c.maxWidth * progress.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF8A0710), AppColors.red]),
              borderRadius: BorderRadius.circular(height),
            ),
          ),
        ]),
      );
}
