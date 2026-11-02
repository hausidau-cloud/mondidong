import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'config_tab.dart';
import 'control_tab.dart';
import 'logs_tab.dart';
import 'overview_tab.dart';

/// Chi tiet 1 tram: Tong quan · Dieu khien · Nhat ky · Cau hinh
class StationScreen extends StatefulWidget {
  final int stationId;
  final Station? initial;
  const StationScreen({super.key, required this.stationId, this.initial});

  @override
  State<StationScreen> createState() => _StationScreenState();
}

class _StationScreenState extends State<StationScreen> {
  Station? _s;
  Series _series = Series.empty();
  List<AlertItem> _alerts = [];
  String _range = '1h';
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _s = widget.initial;
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final r = await Future.wait([
        Session.I.station(widget.stationId),
        Session.I.series(widget.stationId, _range),
        Session.I.alerts(state: 'open', deviceId: widget.stationId, limit: 10),
      ]);
      if (!mounted) return;
      setState(() {
        _s = r[0] as Station;
        _series = r[1] as Series;
        _alerts = (r[2] as AlertPage).rows;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _setRange(String r) {
    setState(() => _range = r);
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _error != null ? ErrorBanner(_error!, onRetry: refresh) : const CircularProgressIndicator()),
      );
    }
    final p = ProfileStyle.of(s.profile);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 168,
              titleSpacing: 0,
              title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(tooltip: 'Làm mới', onPressed: refresh, icon: const Icon(Icons.refresh_rounded)),
                const SizedBox(width: 6),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [p.color.withValues(alpha: 0.16), AppColors.bg],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 58),
                  alignment: Alignment.bottomLeft,
                  child: SafeArea(
                    bottom: false,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      ProfileIcon(s.profile, size: 48),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            StatusPill(s.status),
                            _chip(Icons.memory_rounded, s.code),
                            _chip(s.online ? Icons.wifi_rounded : Icons.wifi_off_rounded, s.rssi == null ? '--' : '${s.rssi} dBm'),
                          ]),
                          const SizedBox(height: 6),
                          Text('${p.label} · ${s.location ?? ''} · ${ago(s.lastSeen)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text2, fontSize: 12.5)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Tổng quan'),
                  Tab(text: 'Điều khiển'),
                  Tab(text: 'Nhật ký'),
                  Tab(text: 'Cấu hình'),
                ],
              ),
            ),
          ],
          body: Column(children: [
            if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: ErrorBanner(_error!, onRetry: refresh)),
            Expanded(
              child: TabBarView(children: [
                OverviewTab(station: s, series: _series, range: _range, onRange: _setRange, onRefresh: refresh),
                ControlTab(station: s, alerts: _alerts, onChanged: refresh),
                LogsTab(station: s),
                ConfigTab(station: s, onSaved: refresh),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chip(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surface2.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: AppColors.text2),
          const SizedBox(width: 5),
          Text(t, style: const TextStyle(fontSize: 11.5, color: AppColors.text2, fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ]),
      );
}

/// Khung noi dung chung cho cac tab (gioi han be rong tren man rong)
class TabBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  const TabBody({super.key, required this.children, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w >= 600 ? 24.0 : 14.0;
    Widget list = ListView(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    if (onRefresh != null) list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    return list;
  }
}
