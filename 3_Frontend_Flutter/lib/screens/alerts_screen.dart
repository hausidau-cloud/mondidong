import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'station/station_screen.dart';

class AlertsScreen extends StatefulWidget {
  final VoidCallback? onChanged;
  const AlertsScreen({super.key, this.onChanged});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String _state = 'open';
  String _level = '';
  AlertPage? _data;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!Session.I.loggedIn) return;
    try {
      final d = await Session.I.alerts(state: _state, level: _level, limit: 100);
      if (mounted) {
        final user = Session.I.user;
        final bool isAdmin = Session.I.isAdmin;
        final assignedStationIds = user?.stationIds ?? [];
        final filteredRows = isAdmin
            ? d.rows
            : d.rows.where((r) => assignedStationIds.contains(r.stationId ?? r.deviceId)).toList();

        setState(() {
          _data = AlertPage(
            rows: filteredRows,
            total: isAdmin ? d.total : filteredRows.length,
            page: d.page,
            pages: d.pages,
            openTotal: isAdmin ? d.openTotal : filteredRows.where((r) => !r.resolved).length,
            openDanger: isAdmin ? d.openDanger : filteredRows.where((r) => !r.resolved && r.level == 'DANGER').length,
            unack: isAdmin ? d.unack : filteredRows.where((r) => !r.resolved).length,
            last24h: isAdmin ? d.last24h : filteredRows.length,
          );
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _changed() async {
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final w = MediaQuery.sizeOf(context).width;
    final pad = w >= 600 ? 24.0 : 16.0;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: pad,
        title: const Text('Cảnh báo'),
        actions: [
          if ((d?.unack ?? 0) > 0)
            TextButton.icon(
              onPressed: () async {
                try {
                  await Session.I.ackAll();
                  if (context.mounted) toast(context, 'Đã xác nhận tất cả cảnh báo');
                  _changed();
                } catch (e) {
                  if (context.mounted) toast(context, e.toString(), error: true);
                }
              },
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Đã xem tất cả'),
            ),
          SizedBox(width: pad - 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (d != null) _counts(d),
                  const SizedBox(height: 16),
                  Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'open', label: Text('Đang mở')),
                        ButtonSegment(value: 'resolved', label: Text('Đã xử lý')),
                        ButtonSegment(value: 'all', label: Text('Tất cả')),
                      ],
                      selected: {_state},
                      onSelectionChanged: (v) {
                        setState(() => _state = v.first);
                        _load();
                      },
                    ),
                    for (final l in const [('', 'Mọi mức'), ('DANGER', 'Nguy hiểm'), ('WARNING', 'Cảnh báo')])
                      ChoiceChip(
                        selected: _level == l.$1,
                        label: Text(l.$2),
                        labelStyle: TextStyle(color: _level == l.$1 ? AppColors.bg : AppColors.text2, fontWeight: FontWeight.w700),
                        onSelected: (_) {
                          setState(() => _level = l.$1);
                          _load();
                        },
                      ),
                  ]),
                  const SizedBox(height: 16),
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorBanner(_error!, onRetry: _load)),
                  if (d == null && _error == null)
                    const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else if (d != null && d.rows.isEmpty)
                    const Card(child: EmptyState(icon: Icons.verified_rounded, text: 'Không có cảnh báo nào', sub: 'Tất cả các trạm đang hoạt động bình thường'))
                  else if (d != null)
                    for (final a in d.rows) Padding(padding: const EdgeInsets.only(bottom: 10), child: AlertTile(alert: a, onChanged: _changed)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counts(AlertPage d) {
    final items = [
      ('Đang mở', d.openTotal, AppColors.warn, Icons.notifications_active_outlined),
      ('Nguy hiểm', d.openDanger, AppColors.danger, Icons.emergency_outlined),
      ('Chưa xem', d.unack, AppColors.accent, Icons.mark_email_unread_outlined),
      ('24 giờ qua', d.last24h, AppColors.hum, Icons.schedule_rounded),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 700 ? 4 : 2;
      final w = (c.maxWidth - 12 * (cols - 1)) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final it in items)
          SizedBox(
            width: w,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(it.$4, color: it.$3, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(it.$1, style: const TextStyle(color: AppColors.text2, fontSize: 13))),
                  Text('${it.$2}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFeatures: tabular)),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}

/// 1 dong canh bao (dung chung cho man Canh bao va tab Nhat ky)
class AlertTile extends StatelessWidget {
  final AlertItem alert;
  final Future<void> Function() onChanged;
  final bool showDevice;
  const AlertTile({super.key, required this.alert, required this.onChanged, this.showDevice = true});

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final danger = a.level == 'DANGER';
    final c = a.resolved ? AppColors.off : (danger ? AppColors.danger : AppColors.warn);
    final icon = a.type == 'OFFLINE' ? Icons.wifi_off_rounded : (danger ? Icons.emergency_rounded : Icons.warning_amber_rounded);
    final admin = Session.I.isAdmin;

    Future<void> act(Future<void> Function() f, String ok) async {
      try {
        await f();
        if (context.mounted) toast(context, ok);
        await onChanged();
      } catch (e) {
        if (context.mounted) toast(context, e.toString(), error: true);
      }
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: showDevice
            ? () {
                final targetId = (a.stationId != null && a.stationId! > 0) ? a.stationId! : a.deviceId;
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => StationScreen(stationId: targetId)));
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: c, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.message, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: a.resolved ? AppColors.text2 : AppColors.text)),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (showDevice) Text(a.deviceName, style: const TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                  Text(alertTypeLabels[a.type] ?? a.type, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text(
                    a.resolved
                        ? 'Lúc ${ddmmHhmm(a.createdAt)} · Xong ${ddmmHhmm(a.resolvedAt)}'
                        : 'Lúc ${ddmmHhmm(a.createdAt)} · ${ago(a.createdAt)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  _tag(a),
                ]),
                if (!a.resolved)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, children: [
                      if (!a.acknowledged)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () => act(() => Session.I.ackAlert(a.id), 'Đã xác nhận'),
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('Đã xem'),
                        ),
                      if (admin)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () => act(() => Session.I.resolveAlert(a.id), 'Đã đóng cảnh báo'),
                          icon: const Icon(Icons.task_alt_rounded, size: 16),
                          label: const Text('Đóng'),
                        ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tag(AlertItem a) {
    final (String t, Color c) = a.resolved
        ? ('Đã xử lý', AppColors.ok)
        : a.acknowledged
            ? ('Đã xem${a.ackBy != null ? ' · ${a.ackBy}' : ''}', AppColors.text2)
            : ('Mới', AppColors.warn);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
    );
  }
}
