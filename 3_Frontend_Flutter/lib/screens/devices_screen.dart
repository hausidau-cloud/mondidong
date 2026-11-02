import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Station>? _devices;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await Session.I.devices();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _showAddDeviceDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final relayCtrl = TextEditingController(text: 'Bóng đèn 220V / Rơ-le');
    final keyCtrl = TextEditingController();
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
              decoration: BoxDecoration(color: AppColors.probe.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.developer_board_rounded, color: AppColors.probe, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Thêm thiết bị IoT mới', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
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
                      codeCtrl.text = 'PICO-01';
                      nameCtrl.text = 'Trạm Pico 2 W - Phòng Lab';
                      locCtrl.text = 'Phòng Thực Nghiệm IoT';
                      relayCtrl.text = 'Bóng đèn 220V / Rơ-le';
                      keyCtrl.text = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
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
                            '⚡ Bấm vào đây để tự điền nhanh thông tin mạch Pico 2 W có sẵn',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Text('Mã thiết bị (Device Code)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'VD: PICO-02, ESP32-01',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Tên thiết bị hiển thị', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'VD: Mạch Pico 2 W - Phòng Lab B',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Vị trí lắp đặt', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  controller: locCtrl,
                  decoration: InputDecoration(
                    hintText: 'VD: Bàn thực nghiệm số 2',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Thiết bị điều khiển Relay', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  controller: relayCtrl,
                  decoration: InputDecoration(
                    hintText: 'VD: Quạt thông gió / Đèn sưởi',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Khóa bí mật API Key HMAC (Tùy chọn)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  controller: keyCtrl,
                  decoration: InputDecoration(
                    hintText: 'Để trống để tự tạo, hoặc dán key từ config.py',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '💡 Nếu để trống, hệ thống sẽ tự động tạo API Key mới. Khóa này phải trùng với API_KEY trong config.py của Pico.',
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
                      if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                        setDState(() => err = 'Vui lòng nhập Mã và Tên thiết bị');
                        return;
                      }
                      setDState(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        final res = await Session.I.createDevice(
                          deviceCode: codeCtrl.text.trim().toUpperCase(),
                          name: nameCtrl.text.trim(),
                          location: locCtrl.text.trim(),
                          relayLabel: relayCtrl.text.trim(),
                          apiKey: keyCtrl.text.trim().isNotEmpty ? keyCtrl.text.trim() : null,
                        );
                        if (!mounted || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        _load();
                        final key = res['api_key']?.toString() ?? '';
                        _showDeviceCreatedDialog(nameCtrl.text.trim(), codeCtrl.text.trim().toUpperCase(), key);
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
                  : const Text('Thêm thiết bị', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceCreatedDialog(String name, String code, String apiKey) {
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
          const Expanded(child: Text('Thêm thiết bị thành công! 🎉', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Thiết bị "$name" ($code) đã được kích hoạt thành công trên hệ thống.', style: const TextStyle(fontSize: 13.5, height: 1.4)),
          const SizedBox(height: 16),
          const Text('API KEY HMAC (NẠP VÀO PICO 2 W):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Expanded(
                child: SelectableText(
                  apiKey,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, color: AppColors.accent, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.accent),
                tooltip: 'Sao chép',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: apiKey));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép API Key!')));
                },
              ),
            ]),
          ),
          const SizedBox(height: 10),
          const Text('💡 Dán mã key này vào file config.py của thiết bị để nạp dữ liệu bảo mật.', style: TextStyle(fontSize: 12, color: AppColors.text2, height: 1.4)),
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

  Future<void> _deleteDevice(Station d) async {
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
          const Expanded(child: Text('Xóa thiết bị phần cứng?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        content: Text('Bạn có chắc muốn xóa thiết bị "${d.name}" (${d.code}) khỏi hệ thống?\nMọi dữ liệu đo đạc của thiết bị này sẽ bị xóa khỏi cơ sở dữ liệu.',
            style: const TextStyle(fontSize: 13.5, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy', style: TextStyle(color: AppColors.muted))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Session.I.deleteDevice(d.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xóa thiết bị "${d.name}" thành công!')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.danger));
    }
  }

  void _copyConfigSnippet(Station d) {
    final snippet = '''
# ========================================================
# File cau hinh config.py cho vi dieu khien ${d.code}
# ========================================================
WIFI_SSID = "YOUR_WIFI_NAME"
WIFI_PASS = "YOUR_WIFI_PASSWORD"

SERVER_URL = "${Session.I.baseUrl}"
DEVICE_CODE = "${d.code}"
API_KEY = "${d.apiKey ?? 'a1b2c3d4e5f60718293a4b5c6d7e8f90'}"

SEND_INTERVAL = ${d.sendInterval}  # Giay
''';
    Clipboard.setData(ClipboardData(text: snippet));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã sao chép cấu hình config.py cho ${d.code}!'), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w >= 600 ? 24.0 : 16.0;
    final list = _devices ?? [];
    final onlineCount = list.where((d) => d.online).length;
    final offlineCount = list.length - onlineCount;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: pad,
        title: const Text('Quản lý thiết bị IoT'),
        actions: [
          FilledButton.tonalIcon(
            onPressed: _showAddDeviceDialog,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Thêm thiết bị', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent.withValues(alpha: 0.15),
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              visualDensity: VisualDensity.compact,
            ),
          ),
          SizedBox(width: pad),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // KPI Thong ke thiet bi
                  Row(children: [
                    Expanded(
                      child: _statCard('Tổng thiết bị', '${list.length}', Icons.developer_board_rounded, AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard('Đang Online', '$onlineCount', Icons.wifi_rounded, AppColors.ok),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard('Offline', '$offlineCount', Icons.wifi_off_rounded, AppColors.off),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Danh sách vi điều khiển & Cảm biến', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.muted),
                        onPressed: _load,
                        tooltip: 'Làm mới',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_loading)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
                  else if (_error != null)
                    ErrorBanner(_error!, onRetry: _load)
                  else if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: EmptyState(icon: Icons.developer_board_off_rounded, text: 'Chưa có thiết bị nào trong hệ thống'),
                    )
                  else
                    for (final d in list) ...[
                      _deviceCard(d),
                      const SizedBox(height: 14),
                    ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: tabular)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }

  Widget _deviceCard(Station d) {
    final online = d.online;
    final statusColor = online ? AppColors.ok : AppColors.off;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: Text(
                d.code,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.accent, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${d.location ?? "Phòng Lab"} · ${d.relayLabel}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(online ? 'Online' : 'Offline', style: TextStyle(color: statusColor, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.muted, size: 20),
              tooltip: 'Xóa thiết bị',
              onPressed: () => _deleteDevice(d),
            ),
          ]),
          const Divider(height: 24),
          Row(children: [
            Expanded(
              child: _infoItem('IP kết nối', d.lastIp ?? 'Chưa ghi nhận', Icons.network_check_rounded),
            ),
            Expanded(
              child: _infoItem('Firmware', d.firmware ?? 'MicroPython v1.20+', Icons.memory_rounded),
            ),
            Expanded(
              child: _infoItem('Lần gửi cuối', d.lastSeen != null ? ago(d.lastSeen!) : 'Chưa có', Icons.access_time_rounded),
            ),
          ]),
          const SizedBox(height: 12),
          // API Key Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              const Icon(Icons.key_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text('API Key: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
              Expanded(
                child: Text(
                  d.apiKey != null && d.apiKey!.length > 10 ? '${d.apiKey!.substring(0, 8)}••••••••••••••••' : (d.apiKey ?? '—'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: AppColors.text2),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  if (d.apiKey != null) {
                    Clipboard.setData(ClipboardData(text: d.apiKey!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép API Key!')));
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Copy Key', style: TextStyle(fontSize: 11.5)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: () => _copyConfigSnippet(d),
                icon: const Icon(Icons.code_rounded, size: 14),
                label: const Text('Copy config.py', style: TextStyle(fontSize: 11.5)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ok,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _infoItem(String label, String value, IconData icon) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: AppColors.muted),
      const SizedBox(width: 6),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    ]);
  }
}
