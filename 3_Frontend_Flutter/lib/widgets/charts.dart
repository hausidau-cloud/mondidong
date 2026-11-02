import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

// =====================================================================
// SPARKLINE — duong xu huong nho tren the tram
// =====================================================================
class Sparkline extends StatelessWidget {
  final List<double?> values;
  final Color color;
  const Sparkline({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SparkPainter(values, color), size: Size.infinite);
}

class _SparkPainter extends CustomPainter {
  final List<double?> v;
  final Color color;
  _SparkPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    final vals = v.whereType<double>().toList();
    if (vals.length < 2) return;
    final mn = vals.reduce(math.min), mx = vals.reduce(math.max);
    final span = (mx - mn) == 0 ? 1.0 : mx - mn;
    for (var i = 0; i < v.length; i++) {
      final x = v[i];
      if (x == null) continue;
      pts.add(Offset(i / (v.length - 1) * size.width, size.height - 3 - (x - mn) / span * (size.height - 8)));
    }
    final line = _smooth(pts);
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [color.withValues(alpha: 0.32), color.withValues(alpha: 0)]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(pts.last, 3, Paint()..color = color);
    canvas.drawCircle(pts.last, 6, Paint()..color = color.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.v != v || old.color != color;
}

/// Duong cong muot (Catmull-Rom -> Bezier)
Path _smooth(List<Offset> p) {
  final path = Path();
  if (p.isEmpty) return path;
  path.moveTo(p.first.dx, p.first.dy);
  for (var i = 0; i < p.length - 1; i++) {
    final p0 = i > 0 ? p[i - 1] : p[i];
    final p1 = p[i];
    final p2 = p[i + 1];
    final p3 = i + 2 < p.length ? p[i + 2] : p2;
    const t = 0.18;
    final c1 = Offset(p1.dx + (p2.dx - p0.dx) * t, p1.dy + (p2.dy - p0.dy) * t);
    final c2 = Offset(p2.dx - (p3.dx - p1.dx) * t, p2.dy - (p3.dy - p1.dy) * t);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

// =====================================================================
// RADIAL GAUGE — dong ho vong 270 do
// =====================================================================
class RadialGauge extends StatelessWidget {
  final double fraction; // 0..1
  final Color color;
  final double size;
  final Widget center;
  const RadialGauge({super.key, required this.fraction, required this.color, required this.center, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fraction.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (ctx, f, _) => CustomPaint(
          painter: _GaugePainter(f, color),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double f;
  final Color color;
  _GaugePainter(this.f, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    final track = Paint()
      ..color = AppColors.surface3
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);
    if (f <= 0.001) return;
    final val = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: [color.withValues(alpha: 0.45), color],
        transform: const GradientRotation(0),
      ).createShader(rect);
    canvas.drawArc(rect, start, sweep * f, false, val);
    // Glow dau kim
    final a = start + sweep * f;
    final c = rect.center + Offset(math.cos(a), math.sin(a)) * (rect.width / 2);
    canvas.drawCircle(c, stroke * 0.9, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(c, stroke * 0.42, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.f != f || old.color != color;
}

// =====================================================================
// LINE CHART — bieu do nhieu duong, nguong, vung relay, cham de xem gia tri
// =====================================================================
class ChartLine {
  final String key, label, unit;
  final List<double?> values;
  final Color color;
  final bool rightAxis, dashed, fill;
  const ChartLine({
    required this.key,
    required this.label,
    required this.values,
    required this.color,
    this.unit = '°C',
    this.rightAxis = false,
    this.dashed = false,
    this.fill = false,
  });
}

class ChartThreshold {
  final double value;
  final String label;
  final Color color;
  const ChartThreshold(this.value, this.label, this.color);
}

class LineChart extends StatefulWidget {
  final List<DateTime> times;
  final List<ChartLine> lines;
  final List<ChartThreshold> thresholds;
  final List<bool> bands; // vung relay BAT
  final bool showDate;
  const LineChart({super.key, required this.times, required this.lines, this.thresholds = const [], this.bands = const [], this.showDate = false});

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _hover;

  void _update(Offset p, Size size) {
    final n = widget.times.length;
    if (n < 2) return;
    final plotW = size.width - _ChartPainter.padL - _ChartPainter.padR;
    final i = (((p.dx - _ChartPainter.padL) / plotW) * (n - 1)).round().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return MouseRegion(
        onHover: (e) => _update(e.localPosition, size),
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          onPanDown: (d) => _update(d.localPosition, size),
          onPanUpdate: (d) => _update(d.localPosition, size),
          onPanEnd: (_) => setState(() => _hover = null),
          onPanCancel: () => setState(() => _hover = null),
          child: CustomPaint(
            size: size,
            painter: _ChartPainter(widget.times, widget.lines, widget.thresholds, widget.bands, _hover, widget.showDate),
          ),
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  static const padL = 38.0, padR = 36.0, padT = 10.0, padB = 24.0;
  final List<DateTime> t;
  final List<ChartLine> lines;
  final List<ChartThreshold> th;
  final List<bool> bands;
  final int? hover;
  final bool showDate;
  _ChartPainter(this.t, this.lines, this.th, this.bands, this.hover, this.showDate);

  TextPainter _tp(String s, {Color color = AppColors.muted, double size = 10, FontWeight w = FontWeight.w500}) => TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: w, fontFeatures: tabular)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final n = t.length;
    final plot = Rect.fromLTRB(padL, padT, size.width - padR, size.height - padB);
    if (n < 2) {
      final tp = _tp('Chưa đủ dữ liệu để vẽ biểu đồ', size: 12);
      tp.paint(canvas, plot.center - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    // ---- Mien gia tri truc trai (nhiet do) & phai (do am 0-100)
    final left = <double>[for (final l in lines.where((l) => !l.rightAxis)) ...l.values.whereType<double>(), for (final x in th) x.value];
    var lo = left.isEmpty ? 0.0 : left.reduce(math.min);
    var hi = left.isEmpty ? 1.0 : left.reduce(math.max);
    final pad = math.max((hi - lo) * 0.12, 1.0);
    lo = (lo - pad).floorToDouble();
    hi = (hi + pad).ceilToDouble();
    final step = _niceStep((hi - lo) / 4);
    lo = (lo / step).floorToDouble() * step;
    hi = (hi / step).ceilToDouble() * step;

    double x(int i) => plot.left + i / (n - 1) * plot.width;
    double yL(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    double yR(double v) => plot.bottom - v / 100 * plot.height;

    // ---- Vung relay bat
    if (bands.length == n) {
      final bp = Paint()..color = AppColors.ok.withValues(alpha: 0.10);
      int? s;
      for (var i = 0; i <= n; i++) {
        final on = i < n && bands[i];
        if (on && s == null) s = i;
        if (!on && s != null) {
          final x0 = x(s) - (s > 0 ? plot.width / (n - 1) / 2 : 0);
          final x1 = x(i - 1) + (i - 1 < n - 1 ? plot.width / (n - 1) / 2 : 0);
          canvas.drawRect(Rect.fromLTRB(x0, plot.top, x1, plot.bottom), bp);
          s = null;
        }
      }
    }

    // ---- Luoi + nhan truc
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var v = lo; v <= hi + 0.001; v += step) {
      final y = yL(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final tp = _tp('${v.toStringAsFixed(step < 1 ? 1 : 0)}°');
      tp.paint(canvas, Offset(plot.left - tp.width - 6, y - tp.height / 2));
    }
    if (lines.any((l) => l.rightAxis)) {
      for (var v = 0; v <= 100; v += 25) {
        final tp = _tp('$v%');
        tp.paint(canvas, Offset(plot.right + 6, yR(v.toDouble()) - tp.height / 2));
      }
    }
    final ticks = math.min(6, n);
    for (var k = 0; k < ticks; k++) {
      final i = (k * (n - 1) / (ticks - 1)).round();
      final d = t[i];
      final tp = _tp(showDate ? '${two(d.day)}/${two(d.month)} ${hhmm(d)}' : hhmm(d));
      var dx = x(i) - tp.width / 2;
      dx = dx.clamp(plot.left - 4, plot.right - tp.width + 4);
      tp.paint(canvas, Offset(dx, plot.bottom + 7));
    }

    // ---- Nguong
    for (final h in th) {
      final y = yL(h.value);
      _dashLine(canvas, Offset(plot.left, y), Offset(plot.right, y), Paint()
        ..color = h.color.withValues(alpha: 0.85)
        ..strokeWidth = 1.1, 6, 5);
      final tp = _tp('${h.label} ${fmt(h.value)}°', color: h.color, size: 9.5, w: FontWeight.w700);
      tp.paint(canvas, Offset(plot.right - tp.width - 4, y - tp.height - 2));
    }

    // ---- Cac duong du lieu
    for (final l in lines) {
      final segs = <List<Offset>>[];
      var cur = <Offset>[];
      for (var i = 0; i < n && i < l.values.length; i++) {
        final v = l.values[i];
        if (v == null) {
          if (cur.isNotEmpty) segs.add(cur);
          cur = [];
          continue;
        }
        cur.add(Offset(x(i), l.rightAxis ? yR(v) : yL(v)));
      }
      if (cur.isNotEmpty) segs.add(cur);
      for (final s in segs) {
        if (s.length < 2) continue;
        final path = _smooth(s);
        if (l.fill) {
          final f = Path.from(path)
            ..lineTo(s.last.dx, plot.bottom)
            ..lineTo(s.first.dx, plot.bottom)
            ..close();
          canvas.drawPath(
            f,
            Paint()..shader = ui.Gradient.linear(Offset(0, plot.top), Offset(0, plot.bottom), [l.color.withValues(alpha: 0.28), l.color.withValues(alpha: 0)]),
          );
        }
        final p = Paint()
          ..color = l.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = l.fill ? 2.4 : 1.7
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;
        if (l.dashed) {
          _dashPath(canvas, path, p, 5, 4);
        } else {
          canvas.drawPath(path, p);
        }
      }
    }

    // ---- Con tro + tooltip
    final h = hover;
    if (h != null && h < n) {
      final hx = x(h);
      canvas.drawLine(Offset(hx, plot.top), Offset(hx, plot.bottom), Paint()
        ..color = AppColors.text.withValues(alpha: 0.35)
        ..strokeWidth = 1);
      final rows = <TextPainter>[_tp('${two(t[h].day)}/${two(t[h].month)} ${hhmm(t[h])}', color: AppColors.text, size: 11, w: FontWeight.w700)];
      final dots = <Color?>[null];
      for (final l in lines) {
        if (h >= l.values.length) continue;
        final v = l.values[h];
        if (v != null) {
          canvas.drawCircle(Offset(hx, l.rightAxis ? yR(v) : yL(v)), 4, Paint()..color = l.color);
          canvas.drawCircle(Offset(hx, l.rightAxis ? yR(v) : yL(v)), 2, Paint()..color = AppColors.surface);
        }
        rows.add(_tp('${l.label}: ${fmt(v)}${l.unit}', color: AppColors.text2, size: 11));
        dots.add(l.color);
      }
      if (bands.length == n) {
        rows.add(_tp('Relay: ${bands[h] ? 'BẬT' : 'TẮT'}', color: bands[h] ? AppColors.ok : AppColors.muted, size: 11, w: FontWeight.w600));
        dots.add(bands[h] ? AppColors.ok : AppColors.off);
      }
      final w = rows.map((r) => r.width).reduce(math.max) + 34;
      final hgt = rows.fold<double>(0, (s, r) => s + r.height + 4) + 14;
      var bx = hx + 12;
      if (bx + w > size.width) bx = hx - w - 12;
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(bx, plot.top + 4, w, hgt), const Radius.circular(10));
      canvas.drawRRect(box, Paint()..color = AppColors.surface2.withValues(alpha: 0.96));
      canvas.drawRRect(box, Paint()
        ..color = AppColors.borderStrong
        ..style = PaintingStyle.stroke);
      var yy = plot.top + 11;
      for (var i = 0; i < rows.length; i++) {
        final d = dots[i];
        if (d != null) canvas.drawCircle(Offset(bx + 14, yy + rows[i].height / 2), 3.5, Paint()..color = d);
        rows[i].paint(canvas, Offset(bx + (d != null ? 24 : 10), yy));
        yy += rows[i].height + 4;
      }
    }
  }

  double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final r = raw / mag;
    final double nice = r <= 1 ? 1.0 : r <= 2 ? 2.0 : r <= 2.5 ? 2.5 : r <= 5 ? 5.0 : 10.0;
    return nice * mag;
  }

  void _dashLine(Canvas c, Offset a, Offset b, Paint p, double on, double off) {
    final len = (b - a).distance;
    final dir = (b - a) / len;
    for (double d = 0; d < len; d += on + off) {
      c.drawLine(a + dir * d, a + dir * math.min(d + on, len), p);
    }
  }

  void _dashPath(Canvas c, Path path, Paint p, double on, double off) {
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += on + off) {
        c.drawPath(m.extractPath(d, math.min(d + on, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter o) => o.t != t || o.lines != lines || o.hover != hover || o.th != th || o.bands != bands;
}
