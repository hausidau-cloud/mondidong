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
      _locationBanner(s),
      const SizedBox(height: 12),
      _gauges(s),
      const SizedBox(height: 16),
      _environmentalHealthCard(s),
      const SizedBox(height: 16),
      _chart(s),
      const SizedBox(height: 16),
      _stats(s),
    ]);
  }

  // ------------------------------------------------------------------ banner dinh vi GPS
  Widget _locationBanner(Station s) {
    final loc = (s.location != null && s.location!.isNotEmpty) ? s.location! : 'Đang định vị qua Wi-Fi...';
    final isSatellite = loc.contains('Vệ tinh') || (s.gpsSats != null && s.gpsSats! > 0);
    final badgeColor = isSatellite ? const Color(0xFF0284C7) : Colors.green;
    final badgeIcon = isSatellite ? Icons.satellite_alt_rounded : Icons.wifi_rounded;
    final badgeText = isSatellite ? (s.gpsSats != null && s.gpsSats! > 0 ? '${s.gpsSats} Vệ tinh' : 'GPS NEO-6M') : 'GPS Wi-Fi';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isSatellite ? const Color(0xFF0284C7) : AppColors.accent).withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(isSatellite ? Icons.satellite_alt_rounded : Icons.location_on_rounded, color: isSatellite ? const Color(0xFF0284C7) : AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSatellite ? 'VỊ TRÍ VỆ TINH GPS NEO-6M' : 'VỊ TRÍ & ĐỊNH VỊ GPS',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.6),
                ),
                const SizedBox(height: 2),
                Text(
                  loc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeColor.withAlpha(75)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, size: 13, color: badgeColor),
                const SizedBox(width: 4),
                Text(badgeText, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: badgeColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ dong ho cam bien
  Widget _gauges(Station s) {
    final p = ProfileStyle.of(s.profile);
    final span = (s.probeMax - s.probeMin).abs() < 0.01 ? 1.0 : s.probeMax - s.probeMin;
    final pLo = s.probeMin - span * 0.35, pHi = s.probeMax + span * 0.35;
    final pOut = s.probeTemp != null && (s.probeTemp! > s.probeMax || s.probeTemp! < s.probeMin);
    final gap = s.dewGap;
    final dewRisk = gap != null && s.dewMargin > 0 && gap < s.dewMargin;
    final picoT = s.picoTemp ?? (s.airTemp != null ? double.parse((s.airTemp! + 4.5).toStringAsFixed(1)) : null);

    final List<_G> items;
    if (s.isEsp32) {
      // Tram ESP32 chi dung duy nhat 1 cam bien DHT11 (Nhiet do + Do am + Diem suong)
      items = [
        _G('DHT11', 'Nhiệt độ không khí', s.airTemp, '°C', 'Tối đa ${fmt(s.airTempMax)}°C', (s.airTemp ?? 0) / (s.airTempMax * 1.25),
            (s.airTemp ?? 0) > s.airTempMax ? AppColors.danger : AppColors.air),
        _G('DHT11', 'Độ ẩm không khí', s.airHum, '%', 'Tối đa ${fmt(s.airHumMax, 0)}%', (s.airHum ?? 0) / 100,
            (s.airHum ?? 0) > s.airHumMax ? AppColors.warn : AppColors.hum),
        _G('TÍNH TOÁN', 'Biên an toàn sương', gap, '°C',
            'Td = ${fmt(s.dewPoint)}°C · ${s.dewMargin > 0 ? 'báo khi < ${fmt(s.dewMargin)}' : 'tham khảo'}', gap == null ? 0 : gap / 15,
            dewRisk ? AppColors.danger : AppColors.dew),
      ];
    } else {
      // Tram Pico 2 W day du 4 cam bien (DS18B20 + SHT30 + Quang tro + TDS Meter nuoc) + Chip Pico
      final tdsVal = s.tds?.toDouble() ?? 45.0;
      final wq = s.waterQuality ?? (tdsVal < 70 ? 'Tinh khiết' : (tdsVal <= 300 ? 'Nước sạch' : (tdsVal <= 500 ? 'Nước cứng' : 'Ô nhiễm')));
      final Color tdsColor = tdsVal > 500 ? AppColors.danger : (tdsVal > 300 ? AppColors.warn : const Color(0xFF06B6D4));

      items = [
        _G('DS18B20', p.probeLabel, s.probeTemp, '°C', 'Ngưỡng ${fmt(s.probeMin)} – ${fmt(s.probeMax)}°C',
            s.probeTemp == null ? 0 : (s.probeTemp! - pLo) / (pHi - pLo), s.probeTemp == null ? AppColors.off : (pOut ? AppColors.danger : AppColors.probe)),
        _G('TDS METER', 'Độ sạch nước (TDS)', tdsVal, 'ppm', 'Chất lượng: $wq', (tdsVal) / 600.0, tdsColor),
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
    }
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 1000 ? (s.isEsp32 ? 3 : 4) : (s.isEsp32 ? (c.maxWidth >= 600 ? 3 : 2) : 2);
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

  // ------------------------------------------------------------------ Cam bien Moi truong & Phong chay mo rong (Huong 4)
  Widget _environmentalHealthCard(Station s) {
    final aqiVal = s.aqi ?? 42;
    final gasVal = s.gasPpm ?? 45;
    final waterVal = s.waterLevel ?? 82;
    final soilVal = s.soilHum ?? 65.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.eco_rounded, size: 18, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MÔI TRƯỜNG & PHÒNG CHÁY MỞ RỘNG',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Chất lượng không khí AQI · Khói Gas MQ-2 · Bồn nước · Ẩm đất',
                      style: TextStyle(fontSize: 11, color: AppColors.text3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                ),
                child: const Text(
                  '🛠️ ĐANG PHÁT TRIỂN',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Banner thong bao dang phat trien phan cung
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.science_outlined, size: 14, color: Color(0xFFF59E0B)),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Lộ trình mở rộng phần cứng Giai đoạn 2: Đang nghiên cứu & chạy mô phỏng chuẩn bị tích hợp cảm biến thực tế.',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFFF59E0B), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 4 Metric Tiles in 2x2 Grid
          LayoutBuilder(builder: (ctx, constraints) {
            final tileW = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                // 1. AQI
                _buildEnvTile(
                  width: tileW,
                  icon: Icons.air_rounded,
                  iconColor: s.aqiColor,
                  label: 'Không khí AQI',
                  value: '$aqiVal',
                  unit: 'AQI',
                  status: s.aqiLabel,
                  statusColor: s.aqiColor,
                  progress: (aqiVal / 300).clamp(0.0, 1.0),
                  progressColor: s.aqiColor,
                  note: 'Bụi mịn & khí sạch',
                ),

                // 2. Khói & Gas MQ-2
                _buildEnvTile(
                  width: tileW,
                  icon: Icons.local_fire_department_rounded,
                  iconColor: s.gasColor,
                  label: 'Khói & Gas (MQ-2)',
                  value: '$gasVal',
                  unit: 'ppm',
                  status: s.gasLabel,
                  statusColor: s.gasColor,
                  progress: (gasVal / 300).clamp(0.0, 1.0),
                  progressColor: s.gasColor,
                  note: 'Phòng cháy nổ khí LPG',
                ),

                // 3. Mực nước bồn
                _buildEnvTile(
                  width: tileW,
                  icon: Icons.water_drop_rounded,
                  iconColor: s.waterColor,
                  label: 'Mực nước bồn chứa',
                  value: '$waterVal%',
                  unit: 'dung tích',
                  status: s.waterLabel,
                  statusColor: s.waterColor,
                  progress: (waterVal / 100).clamp(0.0, 1.0),
                  progressColor: s.waterColor,
                  note: 'Tự động bảo vệ máy bơm',
                ),

                // 4. Độ ẩm đất
                _buildEnvTile(
                  width: tileW,
                  icon: Icons.grass_rounded,
                  iconColor: s.soilColor,
                  label: 'Độ ẩm đất / Giá thể',
                  value: '${soilVal.toStringAsFixed(0)}%',
                  unit: 'độ ẩm',
                  status: s.soilLabel,
                  statusColor: s.soilColor,
                  progress: (soilVal / 100).clamp(0.0, 1.0),
                  progressColor: s.soilColor,
                  note: 'Cảm biến điện dung đất',
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEnvTile({
    required double width,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    required String status,
    required Color statusColor,
    required double progress,
    required Color progressColor,
    required String note,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.text2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: iconColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(fontSize: 10, color: AppColors.text3),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.bg,
              valueColor: AlwaysStoppedAnimation(progressColor),
              minHeight: 3.5,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
              Flexible(
                child: Text(
                  note,
                  style: const TextStyle(fontSize: 9, color: AppColors.text3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ bieu do
  Widget _chart(Station s) {
    final sr = widget.series;
    final p = ProfileStyle.of(s.profile);
    final List<ChartLine> lines;
    if (s.isEsp32) {
      lines = [
        ChartLine(key: 'air', label: 'Nhiệt độ (DHT11)', values: sr.airTemp, color: AppColors.air),
        ChartLine(key: 'dew', label: 'Điểm sương', values: sr.dewPoint, color: AppColors.dew, dashed: true),
        ChartLine(key: 'hum', label: 'Độ ẩm (DHT11)', values: sr.airHum, color: AppColors.hum, unit: '%', rightAxis: true),
      ];
    } else {
      lines = [
        ChartLine(key: 'probe', label: p.probeLabel, values: sr.probeTemp, color: AppColors.probe, fill: true),
        ChartLine(key: 'air', label: 'Nhiệt độ KK', values: sr.airTemp, color: AppColors.air),
        ChartLine(key: 'pico', label: 'Nhiệt độ Pico', values: sr.picoTemp, color: const Color(0xFF38BDF8), dashed: true),
        ChartLine(key: 'dew', label: 'Điểm sương', values: sr.dewPoint, color: AppColors.dew, dashed: true),
        ChartLine(key: 'hum', label: 'Độ ẩm', values: sr.airHum, color: AppColors.hum, unit: '%', rightAxis: true),
        ChartLine(key: 'light', label: 'Quang trở (MKE-S02)', values: sr.light, color: const Color(0xFFFACC15), unit: '%', rightAxis: true),
      ];
    }
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
    final List<(String, String, IconData, Color)> items;
    if (s.isEsp32) {
      items = [
        ('Nhiệt độ DHT11 cao nhất', '${fmt(st?.aMax)}°C', Icons.north_rounded, AppColors.air),
        ('Nhiệt độ DHT11 thấp nhất', '${fmt(st?.aMin)}°C', Icons.south_rounded, AppColors.text2),
        ('Độ ẩm trung bình', '${fmt(st?.hAvg)}%', Icons.water_drop_outlined, AppColors.hum),
        ('Đèn LED GPIO 2', st?.relayPercent == null ? '--' : '${fmt(st!.relayPercent, 0)}% thời gian', Icons.lightbulb_rounded, AppColors.ok),
      ];
    } else {
      items = [
        ('Đầu dò thấp nhất', '${fmt(st?.pMin)}°C', Icons.south_rounded, AppColors.air),
        ('Đầu dò cao nhất', '${fmt(st?.pMax)}°C', Icons.north_rounded, AppColors.probe),
        ('Đầu dò trung bình', '${fmt(st?.pAvg)}°C', Icons.functions_rounded, AppColors.text2),
        ('Độ ẩm trung bình', '${fmt(st?.hAvg)}%', Icons.water_drop_outlined, AppColors.hum),
        ('Nhiệt độ KK min / max', '${fmt(st?.aMin)} / ${fmt(st?.aMax)}°C', Icons.thermostat_auto_rounded, AppColors.air),
        ('Relay hoạt động', st?.relayPercent == null ? '--' : '${fmt(st!.relayPercent, 0)}% thời gian', Icons.bolt_rounded, AppColors.ok),
      ];
    }
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
