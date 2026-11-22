import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';

class ComparisonScreen extends StatefulWidget {
  final int initialStationId1;
  final int initialStationId2;

  const ComparisonScreen({
    super.key,
    this.initialStationId1 = 1,
    this.initialStationId2 = 2,
  });

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  late int _s1;
  late int _s2;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  List<Station> _stations = [];

  @override
  void initState() {
    super.initState();
    _s1 = widget.initialStationId1;
    _s2 = widget.initialStationId2;
    _initLoad();
  }

  Future<void> _initLoad() async {
    try {
      final list = await Session.I.stations();
      if (mounted) {
        setState(() {
          _stations = list;
          if (_stations.length >= 2) {
            _s1 = _stations[0].id;
            _s2 = _stations[1].id;
          }
        });
      }
    } catch (_) {}
    _loadComparison();
  }

  Future<void> _loadComparison() async {
    setState(() => _loading = true);
    try {
      final res = await Session.I.compareStations(_s1, _s2);
      if (mounted) {
        setState(() {
          _data = res;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _swap() {
    setState(() {
      final tmp = _s1;
      _s1 = _s2;
      _s2 = tmp;
    });
    _loadComparison();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('So sánh Đối chiếu Đa trạm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Đổi vị trí 2 trạm',
            onPressed: _swap,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Làm mới',
            onPressed: _loadComparison,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadComparison,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Selector Row
              _buildSelectorRow(),
              const SizedBox(height: 16),

              if (_loading)
                const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                _buildError()
              else if (_data != null) ...[
                _buildHeadToHead(),
                const SizedBox(height: 16),
                _buildAiAssessment(),
                const SizedBox(height: 16),
                _buildComparisonTable(),
                const SizedBox(height: 20),
                _buildPdfExportActions(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectorRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('s1-$_s1'),
              isExpanded: true,
              initialValue: _s1,
              decoration: const InputDecoration(
                labelText: 'Trạm A',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: _stations.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) {
                if (v != null && v != _s1) {
                  setState(() => _s1 = v);
                  _loadComparison();
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: IconButton(
              icon: const Icon(Icons.compare_arrows_rounded, color: AppColors.accent),
              onPressed: _swap,
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('s2-$_s2'),
              isExpanded: true,
              initialValue: _s2,
              decoration: const InputDecoration(
                labelText: 'Trạm B',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: _stations.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) {
                if (v != null && v != _s2) {
                  setState(() => _s2 = v);
                  _loadComparison();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 36),
          const SizedBox(height: 8),
          Text('Không thể tải số liệu so sánh: $_error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _loadComparison, child: const Text('Thử lại')),
        ],
      ),
    );
  }

  Widget _buildHeadToHead() {
    final s1 = _data!['station1'] as Map<String, dynamic>;
    final s2 = _data!['station2'] as Map<String, dynamic>;

    return Row(
      children: [
        Expanded(child: _stationCard(s1, const Color(0xFF0284C7))),
        const SizedBox(width: 12),
        Expanded(child: _stationCard(s2, const Color(0xFF10B981))),
      ],
    );
  }

  Widget _stationCard(Map<String, dynamic> st, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(100), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                st['name']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(st['location']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Nhiệt độ TB:', style: TextStyle(fontSize: 11.5, color: AppColors.text2)),
              Text('${st['avg_temp']}°C', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFE11D48))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Độ ẩm TB:', style: TextStyle(fontSize: 11.5, color: AppColors.text2)),
              Text('${st['avg_hum']}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Độ tin cậy:', style: TextStyle(fontSize: 11.5, color: AppColors.text2)),
              Text('${st['uptime']}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiAssessment() {
    final aiText = _data!['ai_analysis']?.toString() ?? '';
    final diff = _data!['diff'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.accent.withAlpha(40), shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 16),
            ),
            const SizedBox(width: 8),
            const Text('Chẩn đoán So sánh từ AI Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accent)),
          ]),
          const SizedBox(height: 10),
          Text(aiText, style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.text)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.thermostat_rounded, size: 14, color: Color(0xFFE11D48)),
                label: Text('Lệch nhiệt: ΔT = ${diff['delta_temp']}°C', style: const TextStyle(fontSize: 11.5)),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.water_drop_rounded, size: 14, color: Color(0xFF0284C7)),
                label: Text('Lệch ẩm: ΔH = ${diff['delta_hum']}%', style: const TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonTable() {
    final s1 = _data!['station1'] as Map<String, dynamic>;
    final s2 = _data!['station2'] as Map<String, dynamic>;
    final diff = _data!['diff'] as Map<String, dynamic>? ?? {};

    Widget row(String label, String v1, String v2, String delta, {bool highlight = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        decoration: BoxDecoration(
          color: highlight ? AppColors.surface2 : Colors.transparent,
          border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.7)),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2))),
            Expanded(flex: 2, child: Text(v1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text(v2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text(delta, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w700))),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: const BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Expanded(flex: 3, child: Text('TIÊU CHÍ SO SÁNH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted))),
                Expanded(flex: 2, child: Text(s1['name']?.toString() ?? 'Trạm A', textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0284C7)))),
                Expanded(flex: 2, child: Text(s2['name']?.toString() ?? 'Trạm B', textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF10B981)))),
                const Expanded(flex: 2, child: Text('CHÊNH LỆCH', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted))),
              ],
            ),
          ),
          row('Nhiệt độ trung bình', '${s1['avg_temp']}°C', '${s2['avg_temp']}°C', '${diff['delta_temp']}°C', highlight: true),
          row('Nhiệt độ đỉnh (Max)', '${s1['max_temp']}°C', '${s2['max_temp']}°C', '${((s1['max_temp'] as num) - (s2['max_temp'] as num)).abs().toStringAsFixed(1)}°C'),
          row('Độ ẩm trung bình', '${s1['avg_hum']}%', '${s2['avg_hum']}%', '${diff['delta_hum']}%', highlight: true),
          row('Độ ổn định Uptime', '${s1['uptime']}%', '${s2['uptime']}%', '${((s1['uptime'] as num) - (s2['uptime'] as num)).abs().toStringAsFixed(1)}%'),
          row('Khu vực nóng hơn', diff['hotter_station']?.toString() ?? '', '—', 'Cao hơn'),
          row('Khu vực khô hơn', diff['drier_station']?.toString() ?? '', '—', 'Thấp hơn', highlight: true),
        ],
      ),
    );
  }

  Widget _buildPdfExportActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: const Text('In PDF Trạm A', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () => launchUrl(Uri.parse(Session.I.htmlReportUrl(_s1)), mode: LaunchMode.externalApplication),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: const Text('In PDF Trạm B', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () => launchUrl(Uri.parse(Session.I.htmlReportUrl(_s2)), mode: LaunchMode.externalApplication),
          ),
        ),
      ],
    );
  }
}
