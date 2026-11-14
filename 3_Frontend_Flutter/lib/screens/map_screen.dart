import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'station/station_screen.dart';

class StationGeo {
  final Station station;
  final double lat;
  final double lon;
  final String address;

  StationGeo({
    required this.station,
    required this.lat,
    required this.lon,
    required this.address,
  });
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  List<Station> _stations = [];
  bool _loading = true;
  String? _error;
  StationGeo? _selected;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await Session.I.stations();
      if (!mounted) return;
      setState(() {
        _stations = list;
        _loading = false;
        _error = null;
        if (_selected != null) {
          final updated = list.firstWhere((s) => s.id == _selected!.station.id, orElse: () => _selected!.station);
          _selected = _parseGeo(updated);
        } else if (list.isNotEmpty) {
          _selected = _parseGeo(list.first);
        }
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  StationGeo _parseGeo(Station s) {
    final loc = s.location ?? '';
    // Regex tìm tọa độ (lat, lon) trong chuỗi location, vd "(10.822, 106.6257)"
    final reg = RegExp(r'\(([-+]?[0-9]*\.?[0-9]+)\s*,\s*([-+]?[0-9]*\.?[0-9]+)\)');
    final m = reg.firstMatch(loc);

    double lat = 10.8220;
    double lon = 106.6257;
    String addr = loc;

    if (m != null) {
      lat = double.tryParse(m.group(1)!) ?? 10.8220;
      lon = double.tryParse(m.group(2)!) ?? 106.6257;
      addr = loc.replaceAll(m.group(0)!, '').trim();
      if (addr.isEmpty) addr = 'Tọa độ GPS ($lat, $lon)';
    } else {
      // Fallback offset nhẹ theo ID trạm để phân tán điểm trên bản đồ mô phỏng
      lat = 10.8220 + ((s.id % 5) * 0.0035);
      lon = 106.6257 + ((s.id % 4) * 0.0040);
      if (addr.isEmpty) addr = 'Vị trí trạm ${s.name}';
    }

    return StationGeo(station: s, lat: lat, lon: lon, address: addr);
  }

  Future<void> _openGoogleMaps(double lat, double lon) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở Google Maps trên thiết bị này')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi mở bản đồ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final geos = _stations.map(_parseGeo).toList();
    final onlineCount = _stations.where((s) => s.online).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.map_rounded, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('Bản đồ số GIS IoT', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppColors.ok, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('$onlineCount/${_stations.length} Trực tuyến',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text2)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _load(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading && _stations.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _stations.isEmpty
              ? Center(child: ErrorBanner(_error!, onRetry: () => _load()))
              : Column(
                  children: [
                    // Horizontal Station Selector Pills
                    Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: geos.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final g = geos[idx];
                          final isSel = _selected?.station.id == g.station.id;
                          return ChoiceChip(
                            showCheckmark: false,
                            selected: isSel,
                            selectedColor: AppColors.primary.withValues(alpha: 0.25),
                            backgroundColor: AppColors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSel ? AppColors.primary : AppColors.border,
                                width: isSel ? 1.5 : 1,
                              ),
                            ),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: g.station.online ? AppColors.ok : AppColors.text3,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  g.station.name,
                                  style: TextStyle(
                                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                    color: isSel ? AppColors.primary : AppColors.text,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            onSelected: (_) => setState(() => _selected = g),
                          );
                        },
                      ),
                    ),

                    // Digital GIS Radar & Vector Map Viewport
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _buildGisMapCanvas(geos),
                          ),
                          // Floating Map Info Overlay (Top Left)
                          Positioned(
                            top: 12,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surface.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.satellite_alt_rounded, size: 16, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    _selected != null
                                        ? '${_selected!.lat.toStringAsFixed(4)}°N, ${_selected!.lon.toStringAsFixed(4)}°E'
                                        : 'TP. Hồ Chí Minh (WGS84)',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Selected Station Info & Navigation Card
                    if (_selected != null) _buildStationDetailCard(_selected!),
                  ],
                ),
    );
  }

  /// Khung vẽ bản đồ GIS vector tương tác
  Widget _buildGisMapCanvas(List<StationGeo> geos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Tìm min/max lat & lon để định tỉ lệ trên khung hình
        double minLat = 999, maxLat = -999, minLon = 999, maxLon = -999;
        for (var g in geos) {
          if (g.lat < minLat) minLat = g.lat;
          if (g.lat > maxLat) maxLat = g.lat;
          if (g.lon < minLon) minLon = g.lon;
          if (g.lon > maxLon) maxLon = g.lon;
        }

        if (geos.isEmpty || minLat == maxLat) {
          minLat -= 0.01;
          maxLat += 0.01;
          minLon -= 0.01;
          maxLon += 0.01;
        }

        final dLat = (maxLat - minLat).abs();
        final dLon = (maxLon - minLon).abs();
        final padLat = dLat < 0.002 ? 0.005 : dLat * 0.35;
        final padLon = dLon < 0.002 ? 0.005 : dLon * 0.35;

        final boundMinLat = minLat - padLat;
        final boundMaxLat = maxLat + padLat;
        final boundMinLon = minLon - padLon;
        final boundMaxLon = maxLon + padLon;

        return Container(
          color: const Color(0xFF0F172A), // Dark Navy GIS Background
          child: Stack(
            children: [
              // Lưới tọa độ GIS & Vòng quét Radar
              Positioned.fill(
                child: CustomPaint(
                  painter: _GisGridPainter(pulseValue: _pulseController.value),
                ),
              ),

              // Các điểm trạm IoT trên tọa độ
              ...geos.map((g) {
                // Ánh xạ tọa độ GPS sang điểm ảnh X, Y
                final normX = (g.lon - boundMinLon) / (boundMaxLon - boundMinLon);
                // Lat càng lớn càng ở phía Bắc (trên màn hình Y nhỏ hơn)
                final normY = 1.0 - ((g.lat - boundMinLat) / (boundMaxLat - boundMinLat));

                final posX = (normX * (w - 120)) + 60;
                final posY = (normY * (h - 140)) + 70;

                final isSel = _selected?.station.id == g.station.id;
                final statusColor = g.station.online
                    ? (g.station.status == 'DANGER' ? AppColors.danger : (g.station.status == 'WARNING' ? AppColors.warn : AppColors.ok))
                    : AppColors.text3;

                return Positioned(
                  left: posX - 40,
                  top: posY - 50,
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = g),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tag thông số nhiệt độ nổi
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.primary : AppColors.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSel ? Colors.white : AppColors.border,
                              width: isSel ? 1.5 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            g.station.airTemp != null ? '${g.station.airTemp!.toStringAsFixed(1)}°C' : '--°C',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSel ? Colors.white : AppColors.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),

                        // Pin Icon với hiệu ứng vòng tròn phát sáng
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            if (isSel && g.station.online)
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  return Container(
                                    width: 36 + (_pulseController.value * 16),
                                    height: 36 + (_pulseController.value * 16),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: statusColor.withValues(alpha: 0.3 * (1.0 - _pulseController.value)),
                                    ),
                                  );
                                },
                              ),
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.6),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.sensors_rounded, color: Colors.white, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Tên trạm
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            g.station.name,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                              color: isSel ? AppColors.primaryLight : AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Card thông tin chi tiết trạm & nút chỉ đường
  Widget _buildStationDetailCard(StationGeo g) {
    final s = g.station;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tiêu đề & Trạng thái
            Row(
              children: [
                ProfileIcon(s.profile, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.text)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 14, color: AppColors.primaryLight),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              g.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.text2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                StatusPill(s.status),
              ],
            ),
            const SizedBox(height: 12),

            // Các chỉ số cảm biến thời gian thực
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metricTile(Icons.thermostat_rounded, 'Nhiệt độ', s.airTemp != null ? '${s.airTemp!.toStringAsFixed(1)}°C' : '--', AppColors.primary),
                  _metricTile(Icons.water_drop_rounded, 'Độ ẩm', s.airHum != null ? '${s.airHum!.toStringAsFixed(0)}%' : '--', Colors.cyan),
                  _metricTile(Icons.grain_rounded, 'Điểm sương', s.dewPoint != null ? '${s.dewPoint!.toStringAsFixed(1)}°C' : '--', Colors.amber),
                  _metricTile(s.online ? Icons.wifi_rounded : Icons.wifi_off_rounded, 'Tín hiệu', s.rssi != null ? '${s.rssi} dBm' : '--', AppColors.ok),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Nút bấm: Chỉ đường Google Maps & Xem trạm
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF334155)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.directions_rounded, color: Color(0xFF38BDF8), size: 18),
                    label: const Text('Chỉ đường Maps', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    onPressed: () => _openGoogleMaps(g.lat, g.lon),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.analytics_rounded, size: 18),
                    label: const Text('Mở trạm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StationScreen(stationId: s.id, initial: s),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(IconData icon, String label, String val, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.text3)),
          ],
        ),
        const SizedBox(height: 3),
        Text(val, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text, fontFeatures: tabular)),
      ],
    );
  }
}

/// Painter vẽ lưới tọa độ GIS và hiệu ứng radar
class _GisGridPainter extends CustomPainter {
  final double pulseValue;
  _GisGridPainter({required this.pulseValue});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    const step = 45.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vòng tròn Radar ở tâm
    final center = Offset(size.width / 2, size.height / 2);
    final radarPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int r = 80; r <= 240; r += 80) {
      canvas.drawCircle(center, r.toDouble(), radarPaint);
    }

    // Tia quét radar xoay
    final sweepPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final maxR = 240.0 * pulseValue;
    canvas.drawCircle(center, maxR, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _GisGridPainter oldDelegate) => oldDelegate.pulseValue != pulseValue;
}
