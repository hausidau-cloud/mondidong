import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'station/station_screen.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  List<Station>? _stations;
  String? _error;
  String _filter = 'all';
  Timer? _timer;
  DateTime? _updated;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await Session.I.stations();
      if (!mounted) return;
      setState(() {
        _stations = s;
        _error = null;
        _updated = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _open(Station s) {
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, a, _) => StationScreen(stationId: s.id, initial: s),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = _stations;
    final width = MediaQuery.sizeOf(context).width;
    final hPad = width >= 600 ? 24.0 : 16.0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 68,
              titleSpacing: hPad,
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Xin chào, ${Session.I.user?.fullName ?? ''}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
                const Text('Tổng quan hệ thống'),
              ]),
              actions: [
                _LiveBadge(updated: _updated, error: _error != null),
                SizedBox(width: hPad - 4),
              ],
            ),
            if (Session.I.demo)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 2, hPad, 8),
                sliver: const SliverToBoxAdapter(child: DemoBanner()),
              ),
            if (_error != null)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 8),
                sliver: SliverToBoxAdapter(child: ErrorBanner(_error!, onRetry: _load)),
              ),
            if (list == null && _error == null)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (list != null) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 0),
                sliver: SliverToBoxAdapter(child: _HeroCard(list)),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                sliver: SliverToBoxAdapter(child: _Kpis(list)),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 22, hPad, 12),
                sliver: SliverToBoxAdapter(child: _filters(list)),
              ),
              _grid(list, width, hPad),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filters(List<Station> list) {
    int c(String p) => list.where((s) => s.profile == p).length;
    final items = [
      ('all', 'Tất cả', list.length),
      for (final p in ProfileStyle.all) (p, ProfileStyle.of(p).label, c(p)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Trạm giám sát', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: _filter == it.$1,
                onSelected: (_) => setState(() => _filter = it.$1),
                label: Text('${it.$2}  ${it.$3}'),
                labelStyle: TextStyle(
                  color: _filter == it.$1 ? AppColors.bg : AppColors.text2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _grid(List<Station> all, double width, double hPad) {
    final list = all.where((s) => _filter == 'all' || s.profile == _filter).toList();
    if (list.isEmpty) {
      if (all.isEmpty && !Session.I.isAdmin) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: EmptyState(
              icon: Icons.assignment_late_outlined,
              text: 'Bạn chưa được phân công trạm giám sát nào.\nVui lòng liên hệ Quản trị viên để được gán trạm phụ trách.',
            ),
          ),
        );
      }
      return const SliverToBoxAdapter(child: EmptyState(icon: Icons.sensors_off_rounded, text: 'Chưa có trạm nào trong nhóm này'));
    }
    final cols = math.max(1, ((width - hPad * 2 - (width >= 900 ? 92 : 0)) / 380).floor());
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          mainAxisExtent: 318,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => StationCard(station: list[i], onTap: () => _open(list[i])),
          childCount: list.length,
        ),
      ),
    );
  }
}

/// Cham "Truc tiep" + gio cap nhat
class _LiveBadge extends StatelessWidget {
  final DateTime? updated;
  final bool error;
  const _LiveBadge({this.updated, required this.error});

  @override
  Widget build(BuildContext context) {
    final c = error ? AppColors.danger : AppColors.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c, blurRadius: 6)])),
        const SizedBox(width: 7),
        Text(error ? 'Mất kết nối' : (updated == null ? 'Trực tiếp' : hhmmss(updated!)),
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: tabular)),
      ]),
    );
  }
}

/// Banner tinh trang chung
class _HeroCard extends StatelessWidget {
  final List<Station> list;
  const _HeroCard(this.list);

  @override
  Widget build(BuildContext context) {
    final bad = list.where((s) => s.status == 'DANGER' || s.status == 'OFFLINE').toList();
    final warn = list.where((s) => s.status == 'WARNING').toList();
    Color c;
    IconData i;
    String t, sub;
    if (bad.isNotEmpty) {
      c = AppColors.danger;
      i = Icons.emergency_rounded;
      t = '${bad.length} trạm cần xử lý ngay';
      sub = bad.map((s) => s.name).join(' · ');
    } else if (warn.isNotEmpty) {
      c = AppColors.warn;
      i = Icons.warning_amber_rounded;
      t = '${warn.length} trạm đang cảnh báo';
      sub = warn.map((s) => s.name).join(' · ');
    } else {
      c = AppColors.ok;
      i = Icons.verified_user_rounded;
      t = 'Hệ thống hoạt động ổn định';
      sub = 'Tất cả ${list.length} trạm đều nằm trong ngưỡng an toàn';
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.28)),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withValues(alpha: 0.16), AppColors.surface]),
      ),
      child: Row(children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
          child: Icon(i, color: c, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text2, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

class _Kpis extends StatelessWidget {
  final List<Station> list;
  const _Kpis(this.list);

  @override
  Widget build(BuildContext context) {
    final online = list.where((s) => s.online).length;
    final relay = list.where((s) => s.relayOn && s.online).length;
    final alerts = list.fold<int>(0, (a, s) => a + s.openAlerts);
    final probes = list.where((s) => s.probeTemp != null && s.online).toList();
    final hottest = probes.isEmpty ? null : probes.reduce((a, b) => a.probeTemp! >= b.probeTemp! ? a : b);
    final items = [
      ('Trạm online', '$online', '/${list.length}', Icons.wifi_rounded, AppColors.ok),
      ('Cảnh báo mở', '$alerts', '', Icons.notifications_active_outlined, alerts > 0 ? AppColors.warn : AppColors.muted),
      ('Relay đang bật', '$relay', '/${list.length}', Icons.bolt_rounded, AppColors.accent),
      ('Đầu dò cao nhất', fmt(hottest?.probeTemp), '°C', Icons.thermostat_rounded, AppColors.probe),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 760 ? 4 : 2;
      final w = (c.maxWidth - 12 * (cols - 1)) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final it in items)
          SizedBox(
            width: w,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: it.$5.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                    child: Icon(it.$4, color: it.$5, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: it.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          TextSpan(text: it.$3, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                        ]),
                        style: const TextStyle(fontFeatures: tabular),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}

/// The tram tren man tong quan
class StationCard extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;
  const StationCard({super.key, required this.station, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = station;
    final st = StatusStyle.of(s.status);
    final p = ProfileStyle.of(s.profile);
    final offline = s.status == 'OFFLINE';
    final danger = s.status == 'DANGER';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: danger ? AppColors.danger.withValues(alpha: 0.5) : AppColors.border),
        boxShadow: danger ? [BoxShadow(color: AppColors.danger.withValues(alpha: 0.22), blurRadius: 28, spreadRadius: -8)] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Stack(children: [
            // Vach mau trang thai ben trai
            Positioned(left: 0, top: 18, bottom: 18, child: Container(width: 3, decoration: BoxDecoration(color: st.color, borderRadius: BorderRadius.circular(3)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ProfileIcon(s.profile, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('${s.code} · ${s.location ?? p.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(s.status, dense: true),
                ]),
                const SizedBox(height: 14),
                Opacity(
                  opacity: offline ? 0.45 : 1,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.probe, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 6),
                          Flexible(child: Text('${p.probeLabel} · DS18B20', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                        ]),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: fmt(s.probeTemp), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.probe, letterSpacing: -1.5, height: 1.05)),
                            const TextSpan(text: ' °C', style: TextStyle(fontSize: 15, color: AppColors.muted, fontWeight: FontWeight.w600)),
                          ]),
                          style: const TextStyle(fontFeatures: tabular),
                        ),
                      ]),
                    ),
                    SizedBox(width: 120, height: 46, child: Sparkline(values: s.spark, color: AppColors.probe)),
                  ]),
                ),
                const SizedBox(height: 10),
                Opacity(opacity: offline ? 0.45 : 1, child: RangeBar(value: s.probeTemp, min: s.probeMin, max: s.probeMax)),
                const SizedBox(height: 12),
                Opacity(
                  opacity: offline ? 0.45 : 1,
                  child: Row(children: [
                    Expanded(child: MetricTile(label: 'Không khí', value: fmt(s.airTemp), unit: '°C', color: AppColors.air)),
                    const SizedBox(width: 8),
                    Expanded(child: MetricTile(label: 'Độ ẩm', value: fmt(s.airHum), unit: '%', color: AppColors.hum)),
                    const SizedBox(width: 8),
                    Expanded(child: MetricTile(label: 'Điểm sương', value: fmt(s.dewPoint), unit: '°C', color: AppColors.dew)),
                  ]),
                ),
                const Spacer(),
                const Divider(),
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: s.relayOn ? AppColors.ok : AppColors.off,
                      shape: BoxShape.circle,
                      boxShadow: s.relayOn ? const [BoxShadow(color: AppColors.ok, blurRadius: 8)] : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${s.relayLabel}: '),
                        TextSpan(text: s.relayOn ? 'BẬT' : 'TẮT', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.text2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: s.relayMode == 'AUTO' ? AppColors.surface3 : AppColors.warn.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(s.relayMode == 'AUTO' ? 'TỰ ĐỘNG' : 'THỦ CÔNG',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: s.relayMode == 'AUTO' ? AppColors.muted : AppColors.warn)),
                  ),
                  const Spacer(),
                  Text(ago(s.lastSeen), style: const TextStyle(fontSize: 11, color: AppColors.muted, fontFeatures: tabular)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Nhan bao dang o che do Demo
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.dew.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dew.withValues(alpha: 0.3)),
      ),
      child: const Row(children: [
        Icon(Icons.science_outlined, color: AppColors.dew, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text('Chế độ Demo — dữ liệu 3 trạm được giả lập ngay trong máy, không cần server/MySQL.',
              style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
        ),
      ]),
    );
  }
}
