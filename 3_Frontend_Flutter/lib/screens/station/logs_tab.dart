import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../alerts_screen.dart';
import 'station_screen.dart';

class LogsTab extends StatefulWidget {
  final Station station;
  const LogsTab({super.key, required this.station});

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> with AutomaticKeepAliveClientMixin {
  String _view = 'alerts';
  List<AlertItem>? _alerts;
  Paged<Reading>? _readings;
  int _page = 1;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_view == 'alerts') {
        final a = await Session.I.alerts(state: 'all', deviceId: widget.station.id, limit: 50);
        if (mounted) setState(() => _alerts = a.rows);
      } else if (_view == 'data') {
        final r = await Session.I.readings(widget.station.id, page: _page);
        if (mounted) setState(() => _readings = r);
      }
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TabBody(onRefresh: _load, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'alerts', label: Text('Cảnh báo'), icon: Icon(Icons.notifications_outlined, size: 18)),
            ButtonSegment(value: 'relay', label: Text('Relay'), icon: Icon(Icons.bolt_rounded, size: 18)),
            ButtonSegment(value: 'data', label: Text('Dữ liệu đo'), icon: Icon(Icons.table_rows_outlined, size: 18)),
          ],
          selected: {_view},
          onSelectionChanged: (v) {
            setState(() => _view = v.first);
            _load();
          },
        ),
      ),
      const SizedBox(height: 14),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorBanner(_error!, onRetry: _load)),
      switch (_view) {
        'relay' => _relay(),
        'data' => _data(),
        _ => _alertList(),
      },
    ]);
  }

  Widget _alertList() {
    final a = _alerts;
    if (a == null) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    if (a.isEmpty) return const Card(child: EmptyState(icon: Icons.verified_rounded, text: 'Trạm này chưa có cảnh báo nào'));
    return Column(children: [
      for (final x in a) Padding(padding: const EdgeInsets.only(bottom: 10), child: AlertTile(alert: x, onChanged: _load, showDevice: false)),
    ]);
  }

  Widget _relay() {
    final logs = widget.station.relayLogs;
    if (logs.isEmpty) return const Card(child: EmptyState(icon: Icons.bolt_rounded, text: 'Chưa có lần bật/tắt nào'));
    return Card(
      child: Column(children: [
        for (var i = 0; i < logs.length; i++) ...[
          if (i > 0) const Divider(),
          ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (logs[i].action == 'ON' ? AppColors.ok : AppColors.off).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(logs[i].action == 'ON' ? Icons.power_settings_new_rounded : Icons.power_off_rounded,
                  color: logs[i].action == 'ON' ? AppColors.ok : AppColors.muted, size: 20),
            ),
            title: Text('${logs[i].action == 'ON' ? 'BẬT' : 'TẮT'} · ${logs[i].reason}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${logs[i].source == 'AUTO' ? 'Tự động' : 'Thủ công'}${logs[i].by != null ? ' · ${logs[i].by}' : ''} · ${ddmmHhmm(logs[i].at)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _data() {
    final r = _readings;
    if (r == null) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    if (r.rows.isEmpty) return const Card(child: EmptyState(icon: Icons.table_rows_outlined, text: 'Chưa có dữ liệu đo'));
    const h = TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5);
    const c = TextStyle(fontSize: 13, fontFeatures: tabular);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: const WidgetStatePropertyAll(AppColors.surface2),
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 44,
            columnSpacing: 22,
            columns: const [
              DataColumn(label: Text('THỜI GIAN', style: h)),
              DataColumn(label: Text('KK °C', style: h), numeric: true),
              DataColumn(label: Text('ẨM %', style: h), numeric: true),
              DataColumn(label: Text('SƯƠNG °C', style: h), numeric: true),
              DataColumn(label: Text('ĐẦU DÒ °C', style: h), numeric: true),
              DataColumn(label: Text('PICO °C', style: h), numeric: true),
              DataColumn(label: Text('QUANG TRỞ', style: h), numeric: true),
              DataColumn(label: Text('RELAY', style: h)),
              DataColumn(label: Text('TRẠNG THÁI', style: h)),
            ],
            rows: [
              for (final x in r.rows)
                DataRow(cells: [
                  DataCell(Text(ddmmHhmm(x.at), style: c)),
                  DataCell(Text(fmt(x.airTemp), style: c.copyWith(color: AppColors.air))),
                  DataCell(Text(fmt(x.airHum), style: c.copyWith(color: AppColors.hum))),
                  DataCell(Text(fmt(x.dewPoint), style: c.copyWith(color: AppColors.dew))),
                  DataCell(Text(fmt(x.probeTemp), style: c.copyWith(color: AppColors.probe, fontWeight: FontWeight.w700))),
                  DataCell(Text(fmt(x.picoTemp), style: c.copyWith(color: AppColors.accent))),
                  DataCell(Text('${x.lightPct}%', style: c.copyWith(color: const Color(0xFFFACC15)))),
                  DataCell(Text(x.relay ? 'BẬT' : 'TẮT', style: c.copyWith(color: x.relay ? AppColors.ok : AppColors.muted))),
                  DataCell(StatusPill(x.status, dense: true)),
                ]),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: Text('${r.total} bản ghi · Trang ${r.page}/${r.pages}', style: const TextStyle(fontSize: 12, color: AppColors.muted))),
            IconButton(
              onPressed: r.page > 1
                  ? () {
                      _page = r.page - 1;
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              onPressed: r.page < r.pages
                  ? () {
                      _page = r.page + 1;
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
        ),
      ]),
    );
  }
}
