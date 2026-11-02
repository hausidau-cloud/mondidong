import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import 'station_screen.dart';

class OverviewTab extends StatefulWidget {
  final Station station;
  final Series series;
  final String range;
  final ValueChanged<String> onRange;
  final Future<void> Function() onRefresh;
  const OverviewTab({super.key, required this.station, required this.series, required this.range, required this.onRange, required this.onRefresh});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> with AutomaticKeepAliveClientMixin {
  final Set<String> _hidden = {};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = widget.station;
    return TabBody(onRefresh: widget.onRefresh, children: [
      _gauges(s),
      const SizedBox(height: 16),
      _chart(s),
      const SizedBox(height: 16),
      _stats(s),
    ]);
  }

  // ------------------------------------------------------------------ 4 dong ho
  Widget _gauges(Station s) {
    final p = ProfileStyle.of(s.profile);
    final span = (s.probeMax - s.probeMin).abs() < 0.01 ? 1.0 : s.probeMax - s.probeMin;
    final pLo = s.probeMin - span * 0.35, pHi = s.probeMax + span * 0.35;
    final pOut = s.probeTemp != null && (s.probeTemp! > s.probeMax || s.probeTemp! < s.probeMin);
    final gap = s.dewGap;
    final dewRisk = gap != null && s.dewMargin > 0 && gap < s.dewMargin;
    final picoT = s.picoTemp ?? (s.airTemp != null ? double.parse((s.airTemp! + 4.5).toStringAsFixed(1)) : null);

    final items = [
      _G('DS18B20', p.probeLabel, s.probeTemp, '°C', 'Ngưỡng ${fmt(s.probeMin)} – ${fmt(s.probeMax)}°C',
          s.probeTemp == null ? 0 : (s.probeTemp! - pLo) / (pHi - pLo), s.probeTemp == null ? AppColors.off : (pOut ? AppColors.danger : AppColors.probe)),
      _G('SHT30', 'Nhiệt độ không khí', s.airTemp, '°C', 'Tối đa ${fmt(s.airTempMax)}°C', (s.airTemp ?? 0) / (s.airTempMax * 1.25),
          (s.airTemp ?? 0) > s.airTempMax ? AppColors.danger : AppColors.air),
      _G('SHT30', 'Độ ẩm tương đối', s.airHum, '%', 'Tối đa ${fmt(s.airHumMax, 0)}%', (s.airHum ?? 0) / 100,
          (s.airHum ?? 0) > s.airHumMax ? AppColors.warn : AppColors.hum),
      _G('TÍNH TOÁN', 'Biên an toàn sương', gap, '°C',
          'Td = ${fmt(s.dewPoint)}°C · ${s.dewMargin > 0 ? 'báo khi < ${fmt(s.dewMargin)}' : 'tham khảo'}', gap == null ? 0 : gap / 15,
          dewRisk ? AppColors.danger : AppColors.dew),
      _G('MKE-S02', 'Độ tối quang trở', s.lightPct.toDouble(), '%', 'Che tối > 45% bật đèn', (s.lightPct) / 100,
          s.lightPct >= 45 ? AppColors.warn : const Color(0xFFFACC15)),
      _G('PICO 2 W', 'Nhiệt độ chip Pico', picoT, '°C', 'Cảm biến chip bo mạch', (picoT ?? 0) / 70.0,
          (picoT ?? 0) > 60 ? AppColors.danger : AppColors.accent),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 1000 ? 4 : 2;
      final w = (c.maxWidth - 12 * (cols - 1)) / cols;
      final compact = w < 220;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final g in items)
          SizedBox(
            width: w,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(5)),
                    child: Text(g.src, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.text2)),
                  ),
                  const SizedBox(height: 10),
                  RadialGauge(
                    fraction: g.frac,
                    color: g.color,
                    size: compact ? 112 : 130,
                    center: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(fmt(g.value),
                          style: TextStyle(fontSize: compact ? 24 : 28, fontWeight: FontWeight.w800, color: g.color, letterSpacing: -1, fontFeatures: tabular)),
                      Text(g.unit, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text(g.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(g.sub, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
              ),
            ),
          ),
      ]);
    });
  }

  // ------------------------------------------------------------------ bieu do
  Widget _chart(Station s) {
    final sr = widget.series;
    final p = ProfileStyle.of(s.profile);
    final lines = [
      ChartLine(key: 'probe', label: p.probeLabel, values: sr.probeTemp, color: AppColors.probe, fill: true),
      ChartLine(key: 'air', label: 'Nhiệt độ KK', values: sr.airTemp, color: AppColors.air),
      ChartLine(key: 'pico', label: 'Nhiệt độ Pico', values: sr.picoTemp, color: const Color(0xFF38BDF8), dashed: true),
      ChartLine(key: 'dew', label: 'Điểm sương', values: sr.dewPoint, color: AppColors.dew, dashed: true),
      ChartLine(key: 'hum', label: 'Độ ẩm', values: sr.airHum, color: AppColors.hum, unit: '%', rightAxis: true),
      ChartLine(key: 'light', label: 'Quang trở (MKE-S02)', values: sr.light, color: const Color(0xFFFACC15), unit: '%', rightAxis: true),
    ];
    final legend = [
      for (final l in lines) (l.key, l.label, l.color),
      ('th', 'Ngưỡng', AppColors.danger),
      ('relay', 'Relay BẬT', AppColors.ok),
    ];
    final bucket = sr.bucket >= 60 ? '${sr.bucket ~/ 60} phút' : '${sr.bucket} giây';
    return SectionCard(
      title: 'Biểu đồ diễn biến',
      subtitle: '${sr.t.length} điểm · gom $bucket · chạm để xem giá trị',
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      trailing: SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        segments: const [
          ButtonSegment(value: '1h', label: Text('1h')),
          ButtonSegment(value: '6h', label: Text('6h')),
          ButtonSegment(value: '24h', label: Text('24h')),
          ButtonSegment(value: '7d', label: Text('7d')),
        ],
        selected: {widget.range},
        onSelectionChanged: (v) => widget.onRange(v.first),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final it in legend)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _hidden.contains(it.$1) ? _hidden.remove(it.$1) : _hidden.add(it.$1)),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hidden.contains(it.$1) ? 0.35 : 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 12, height: 3, decoration: BoxDecoration(color: it.$3, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 7),
                      Text(it.$2, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: LineChart(
            times: sr.t,
            showDate: widget.range == '7d',
            lines: lines.where((l) => !_hidden.contains(l.key)).toList(),
            thresholds: _hidden.contains('th')
                ? const []
                : [
                    ChartThreshold(s.probeMax, 'Max', AppColors.danger),
                    if (s.profile != 'cabinet') ChartThreshold(s.probeMin, 'Min', AppColors.danger.withValues(alpha: 0.7)),
                  ],
            bands: _hidden.contains('relay') ? const [] : sr.relay,
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ thong ke
  Widget _stats(Station s) {
    final st = s.stats;
    final items = [
      ('Đầu dò thấp nhất', '${fmt(st?.pMin)}°C', Icons.south_rounded, AppColors.air),
      ('Đầu dò cao nhất', '${fmt(st?.pMax)}°C', Icons.north_rounded, AppColors.probe),
      ('Đầu dò trung bình', '${fmt(st?.pAvg)}°C', Icons.functions_rounded, AppColors.text2),
      ('Độ ẩm trung bình', '${fmt(st?.hAvg)}%', Icons.water_drop_outlined, AppColors.hum),
      ('Nhiệt độ KK min / max', '${fmt(st?.aMin)} / ${fmt(st?.aMax)}°C', Icons.thermostat_auto_rounded, AppColors.air),
      ('Relay hoạt động', st?.relayPercent == null ? '--' : '${fmt(st!.relayPercent, 0)}% thời gian', Icons.bolt_rounded, AppColors.ok),
    ];
    return SectionCard(
      title: 'Thống kê 24 giờ',
      subtitle: '${st?.n ?? 0} lần đo',
      child: LayoutBuilder(builder: (ctx, c) {
        final cols = c.maxWidth >= 800 ? 3 : 2;
        final w = (c.maxWidth - 10 * (cols - 1)) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final it in items)
            SizedBox(
              width: w,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Icon(it.$3, size: 18, color: it.$4),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                    ]),
                  ),
                ]),
              ),
            ),
        ]);
      }),
    );
  }
}

class _G {
  final String src, label, unit, sub;
  final double? value;
  final double frac;
  final Color color;
  _G(this.src, this.label, this.value, this.unit, this.sub, this.frac, this.color);
}
