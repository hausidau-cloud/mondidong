import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/qr_dialogs.dart';
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

  void _showAddStationDialog() {
    final nameCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool busy = false;
    String? err;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: AppColors.surface,
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.add_to_photos_rounded, color: AppColors.accent, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Thêm trạm giám sát mới', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (err != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(err!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
                    ]),
                  ),
                InkWell(
                  onTap: () {
                    setDState(() {
                      nameCtrl.text = 'Trạm Nhà Màng Thực Nghiệm';
                      locCtrl.text = 'Khu Thực Nghiệm Công Nghệ Cao';
                      descCtrl.text = 'Giám sát nhiệt độ, độ ẩm và kiểm soát sưởi';
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt_rounded, color: AppColors.accent, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚡ Bấm vào đây để điền nhanh thông tin trạm mẫu',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Text('Tên trạm hiển thị', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'VD: Trạm Nhà Màng 1, Trạm Phòng Lab B',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Vị trí đặt trạm', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  controller: locCtrl,
                  decoration: InputDecoration(
                    hintText: 'VD: Phòng Thí Nghiệm B / Nhà màng tầng 2',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Mô tả trạm (Tùy chọn)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    hintText: 'VD: Trạm theo dõi vi khí hậu và bảo quản sản phẩm',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '💡 Sau khi tạo trạm, bạn có thể vào trang "Quản lý thiết bị" để gán mạch vi điều khiển (Pico 2 W / ESP32) vào trạm này.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Hủy', style: TextStyle(color: AppColors.muted)),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        setDState(() => err = 'Vui lòng nhập Tên trạm giám sát');
                        return;
                      }
                      setDState(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        await Session.I.createStation(
                          name: nameCtrl.text.trim(),
                          location: locCtrl.text.trim().isNotEmpty ? locCtrl.text.trim() : null,
                          description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                        );
                        if (!mounted || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        _load();
                        _showCreatedSuccessDialog(nameCtrl.text.trim(), locCtrl.text.trim());
                      } catch (e) {
                        setDState(() {
                          busy = false;
                          err = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: const Color(0xFF04131D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Tạo trạm mới', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatedSuccessDialog(String name, String location) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surface,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.ok.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.check_circle_rounded, color: AppColors.ok, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Tạo trạm thành công! 🎉', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Trạm "$name"${location.isNotEmpty ? " ($location)" : ""} đã được tạo thành công!', style: const TextStyle(fontSize: 13.5, height: 1.4)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: AppColors.accent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bước tiếp theo: Vào "Quản lý thiết bị" để thêm vi điều khiển (Pico 2 W / ESP32) và chọn gán vào trạm này.',
                    style: TextStyle(fontSize: 12, color: AppColors.text2, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ]),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Đã hiểu / Hoàn tất'),
          ),
        ],
      ),
    );
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
                IconButton(
                  tooltip: 'Quét mã QR / Nhập mã vào trạm',
                  icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.accent),
                  onPressed: () => JoinStationDialog.show(context, onSuccess: _load),
                ),
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
    final items = [
      ('all', 'Tất cả', list.length),
      for (final s in list) (s.id.toString(), s.name, 1),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Trạm giám sát', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => JoinStationDialog.show(context, onSuccess: _load),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                label: const Text('Quét mã trạm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (Session.I.isAdmin) ...[
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _showAddStationDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Thêm trạm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      if (list.isNotEmpty) ...[
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
                  label: Text(it.$1 == 'all' ? '${it.$2}  ${it.$3}' : it.$2),
                  labelStyle: TextStyle(
                    color: _filter == it.$1 ? AppColors.bg : AppColors.text2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ]),
        ),
      ],
    ]);
  }

  Widget _grid(List<Station> all, double width, double hPad) {
    var list = all.where((s) => _filter == 'all' || s.id.toString() == _filter).toList();
    if (list.isEmpty && all.isNotEmpty && _filter != 'all') {
      list = all;
    }
    if (list.isEmpty) {
      if (all.isEmpty && !Session.I.isAdmin) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(color: AppColors.accent.withValues(alpha: 0.08), blurRadius: 24, spreadRadius: 2),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, size: 48, color: AppColors.accent),
                    ),
                    const SizedBox(height: 16),
                    const Text('Chưa kết nối trạm giám sát nào', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text(
                      'Tài khoản nhân viên cần kết nối với Trạm giám sát do Quản trị viên cấp. Bạn có thể quét mã QR dán trên tủ trạm hoặc nhập mã mời để kết nối ngay.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => JoinStationDialog.show(context, onSuccess: _load),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                      label: const Text('Quét mã QR kết nối trạm ngay', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: const Color(0xFF04131D),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: EmptyState(icon: Icons.sensors_off_rounded, text: 'Chưa có trạm giám sát nào'),
        ),
      );
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
          (ctx, i) => StationCard(
            station: list[i],
            onTap: () => _open(list[i]),
            onShowQr: Session.I.isAdmin ? () => StationQrDialog.show(context, list[i]) : null,
            onDelete: () => _deleteStation(list[i]),
          ),
          childCount: list.length,
        ),
      ),
    );
  }

  Future<void> _deleteStation(Station s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surface,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Xác nhận xóa trạm', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        content: Text(
          'Bạn có chắc chắn muốn xóa trạm "${s.name}" (${s.code}) khỏi hệ thống?\nToàn bộ phân công và dữ liệu liên quan sẽ bị xóa khỏi Database.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy', style: TextStyle(color: AppColors.muted))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Xóa trạm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Session.I.deleteStation(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xóa trạm "${s.name}" thành công!')));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.danger));
      }
    }
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
  final VoidCallback? onShowQr;
  final VoidCallback? onDelete;
  const StationCard({super.key, required this.station, required this.onTap, this.onShowQr, this.onDelete});

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
                      Text(s.code.isNotEmpty ? '${s.code} · ${s.location ?? p.label}' : 'Chưa gắn vi điều khiển · ${s.location ?? p.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  StatusPill(s.code.isEmpty ? 'UNASSIGNED' : s.status, dense: true),
                  if (Session.I.isAdmin && onShowQr != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.qr_code_2_rounded, size: 21, color: AppColors.accent),
                      tooltip: 'Mã QR & Mã mời vào trạm (Chỉ Admin)',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: onShowQr,
                    ),
                  ],
                  if (Session.I.isAdmin && onDelete != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.muted),
                      tooltip: 'Xóa trạm này',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: onDelete,
                    ),
                  ],
                ]),
                const SizedBox(height: 14),
                Opacity(
                  opacity: offline ? 0.45 : 1,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: s.isEsp32 ? AppColors.air : AppColors.probe, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 6),
                          Flexible(child: Text(s.isEsp32 ? 'Nhiệt độ không khí · DHT11' : '${p.probeLabel} · DS18B20', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                        ]),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: fmt(s.isEsp32 ? s.airTemp : s.probeTemp), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: s.isEsp32 ? AppColors.air : AppColors.probe, letterSpacing: -1.5, height: 1.05)),
                            const TextSpan(text: ' °C', style: TextStyle(fontSize: 15, color: AppColors.muted, fontWeight: FontWeight.w600)),
                          ]),
                          style: const TextStyle(fontFeatures: tabular),
                        ),
                      ]),
                    ),
                    SizedBox(width: 120, height: 46, child: Sparkline(values: s.spark, color: s.isEsp32 ? AppColors.air : AppColors.probe)),
                  ]),
                ),
                const SizedBox(height: 10),
                Opacity(opacity: offline ? 0.45 : 1, child: RangeBar(value: s.isEsp32 ? s.airTemp : s.probeTemp, min: s.isEsp32 ? 0 : s.probeMin, max: s.isEsp32 ? s.airTempMax : s.probeMax)),
                const SizedBox(height: 12),
                Opacity(
                  opacity: offline ? 0.45 : 1,
                  child: Row(children: [
                    if (!s.isEsp32) ...[
                      Expanded(child: MetricTile(label: 'Không khí', value: fmt(s.airTemp), unit: '°C', color: AppColors.air)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: MetricTile(label: s.isEsp32 ? 'Độ ẩm (DHT11)' : 'Độ ẩm', value: fmt(s.airHum), unit: '%', color: AppColors.hum)),
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
