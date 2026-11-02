import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'station_screen.dart';

class ConfigTab extends StatefulWidget {
  final Station station;
  final Future<void> Function() onSaved;
  const ConfigTab({super.key, required this.station, required this.onSaved});

  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> with AutomaticKeepAliveClientMixin {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  bool _busy = false, _dirty = false;

  static const _keys = ['probe_temp_min', 'probe_temp_max', 'air_temp_max', 'air_hum_max', 'dew_margin', 'hysteresis', 'offline_after', 'offset_air', 'offset_probe'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _c = {for (final k in _keys) k: TextEditingController()};
    _fill(widget.station);
  }

  @override
  void didUpdateWidget(covariant ConfigTab old) {
    super.didUpdateWidget(old);
    if (!_dirty) _fill(widget.station); // khong ghi de khi nguoi dung dang sua
  }

  void _fill(Station s) {
    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    _c['probe_temp_min']!.text = n(s.probeMin);
    _c['probe_temp_max']!.text = n(s.probeMax);
    _c['air_temp_max']!.text = n(s.airTempMax);
    _c['air_hum_max']!.text = n(s.airHumMax);
    _c['dew_margin']!.text = n(s.dewMargin);
    _c['hysteresis']!.text = n(s.hysteresis);
    _c['offline_after']!.text = '${s.offlineAfter}';
    _c['offset_air']!.text = n(s.offsetAir);
    _c['offset_probe']!.text = n(s.offsetProbe);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{};
      for (final k in _keys) {
        final text = _c[k]!.text.trim().replaceAll(',', '.');
        final numVal = double.tryParse(text);
        if (numVal != null) {
          payload[k] = (k == 'offline_after') ? numVal.toInt() : numVal;
        }
      }
      await Session.I.saveThresholds(widget.station.id, payload);
      _dirty = false;
      if (mounted) toast(context, 'Đã lưu cấu hình — áp dụng từ lần đo kế tiếp');
      await widget.onSaved();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = widget.station;
    final admin = Session.I.isAdmin;
    final p = ProfileStyle.of(s.profile);

    Widget field(String k, String label, String unit, {String? hint, bool integer = false}) => TextFormField(
          controller: _c[k],
          enabled: admin && !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          onChanged: (_) => _dirty = true,
          validator: (v) {
            final x = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
            if (x == null) return 'Nhập số';
            if (k == 'air_hum_max' && (x < 0 || x > 100)) return '0–100%';
            if (k.startsWith('offset') && x.abs() > 10) return 'Trong khoảng ±10';
            if (k == 'probe_temp_max') {
              final mn = double.tryParse(_c['probe_temp_min']!.text.replaceAll(',', '.'));
              if (mn != null && x <= mn) return 'Phải lớn hơn ngưỡng dưới';
            }
            return null;
          },
          style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600),
          decoration: InputDecoration(labelText: label, suffixText: unit, helperText: hint, helperMaxLines: 2),
        );

    Widget grid(List<Widget> children) => LayoutBuilder(builder: (ctx, c) {
          final cols = c.maxWidth >= 640 ? 2 : 1;
          final w = (c.maxWidth - 14 * (cols - 1)) / cols;
          return Wrap(spacing: 14, runSpacing: 16, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
        });

    return TabBody(children: [
      Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionCard(
            title: 'Ngưỡng cảnh báo',
            subtitle: p.label,
            trailing: admin
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Lưu'),
                  )
                : const Chip(label: Text('Chỉ xem')),
            child: grid([
              field('probe_temp_min', '${p.probeLabel} tối thiểu', '°C', hint: s.profile == 'pharma' ? 'Vắc-xin: 2°C' : 'DS18B20'),
              field('probe_temp_max', '${p.probeLabel} tối đa', '°C',
                  hint: s.profile == 'pharma' ? 'Vắc-xin: 8°C' : 'Vượt ngưỡng → bật ${p.relayVerb.toLowerCase()}'),
              field('air_temp_max', 'Nhiệt độ không khí tối đa', '°C', hint: 'SHT30'),
              field('air_hum_max', 'Độ ẩm tối đa', '%', hint: 'SHT30'),
              field('dew_margin', 'Biên cảnh báo đọng sương (T − Td)', '°C', hint: s.profile == 'aquarium' ? 'Hồ cá: đặt 0 để tắt' : 'Nhỏ hơn → nguy cơ đọng nước'),
              field('hysteresis', 'Độ trễ tắt relay', '°C', hint: 'Chống relay bật/tắt liên tục'),
              field('offline_after', 'Báo mất kết nối sau', 'giây', integer: true),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Hiệu chỉnh cảm biến',
            subtitle: 'Cộng thêm vào giá trị đo (bù sai số)',
            child: grid([
              field('offset_air', 'Bù nhiệt độ SHT30', '°C', hint: 'VD: −0.5 nếu SHT30 đo cao hơn nhiệt kế chuẩn'),
              field('offset_probe', 'Bù nhiệt độ DS18B20', '°C'),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      _deviceInfo(s, admin),
    ]);
  }

  String _serverBase() {
    final host = Uri.parse(Session.I.baseUrl);
    final h = (host.host == 'localhost' || host.host == '127.0.0.1' || host.host == '10.0.2.2') ? 'IP_MAY_TINH' : host.host;
    final port = host.hasPort ? ':${host.port}' : '';
    return 'http://$h$port';
  }

  String _snippet(Station s, String apiKey) => '''WIFI_SSID   = "Ten_WiFi"
WIFI_PASS   = "Mat_khau_WiFi"
SERVER_URL  = "${_serverBase()}"
DEVICE_CODE = "${s.code}"
API_KEY     = "$apiKey"''';

  /// Hop thoai nhap lai mat khau cho thao tac nhay cam (xem/doi key)
  Future<String?> _askPassword(String title, String action) async {
    final c = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu của bạn', helperText: 'Xác nhận lại để bảo vệ API key'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(action)),
        ],
      ),
    );
    c.dispose();
    return (pw == null || pw.isEmpty) ? null : pw;
  }

  void _showSnippet(Station s, String key) {
    final snippet = _snippet(s, key);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nội dung config.py'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mở 4 file lên Pico bằng Thonny. Dán nội dung này vào config.py:', style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: SelectableText(snippet, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: AppColors.text2, height: 1.5)),
            ),
            const SizedBox(height: 8),
            const Text('API key là bí mật — đừng gửi file này cho người khác (kể cả thầy chấm bài).', style: TextStyle(fontSize: 12, color: AppColors.warn)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: snippet));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) toast(context, 'Đã sao chép config.py');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Sao chép'),
          ),
        ],
      ),
    );
  }

  Future<void> _revealKey(Station s) async {
    final pw = await _askPassword('Xem API key của ${s.code}', 'Xem');
    if (pw == null) return;
    setState(() => _busy = true);
    try {
      _showSnippet(s, await Session.I.revealKey(s.id, pw));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotateKey(Station s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi API key mới?'),
        content: const Text('Key cũ sẽ hết hiệu lực ngay. Bạn phải nạp lại config.py cho Pico thì trạm mới gửi dữ liệu được. Dùng khi nghi ngờ key bị lộ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đổi key')),
        ],
      ),
    );
    if (ok != true) return;
    final pw = await _askPassword('Xác nhận đổi key ${s.code}', 'Đổi key');
    if (pw == null) return;
    setState(() => _busy = true);
    try {
      final key = await Session.I.rotateKey(s.id, pw);
      await widget.onSaved();
      if (mounted) _showSnippet(s, key);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockIp(Station s) async {
    setState(() => _busy = true);
    try {
      await Session.I.setIpLock(s.id, unlock: true);
      await widget.onSaved();
      if (mounted) toast(context, 'Đã mở khóa — trạm sẽ ghim lại IP ở gói hợp lệ kế tiếp');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _deviceInfo(Station s, bool admin) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        );
    final locked = (s.ipLock ?? 'exact') == 'exact';
    return SectionCard(
      title: 'Thông tin trạm & nạp Pico 2 W',
      subtitle: s.description,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row('Mã trạm', s.code),
        row('Vị trí', s.location ?? '—'),
        row('Tải relay', s.relayLabel),
        row('Chu kỳ gửi', '${s.sendInterval} giây'),
        row('Firmware', s.firmware ?? '—'),
        row('Lần cuối', '${ddmmHhmm(s.lastSeen)} (${ago(s.lastSeen)})'),
        if (admin) ...[
          const Divider(height: 28),
          Row(children: [
            const Icon(Icons.shield_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            const Expanded(child: Text('Bảo mật thiết bị', style: TextStyle(fontWeight: FontWeight.w700))),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(locked ? 'Khóa theo IP' : 'Không khóa IP', style: const TextStyle(fontSize: 12)),
              avatar: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 15),
            ),
          ]),
          const SizedBox(height: 6),
          row('IP được phép', s.allowedIp ?? '(chưa ghim — gói đầu tiên sẽ ghim)'),
          row('IP gần nhất', s.lastIp ?? '—'),
          row('Phiên bản key', 'v${s.keyVersion}'),
          row('Kiểu xác thực', (s.ingestAuth ?? 'hmac') == 'hmac' ? 'Ký HMAC (an toàn)' : 'API key trần (cũ)'),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(onPressed: _busy ? null : () => _revealKey(s), icon: const Icon(Icons.vpn_key_rounded, size: 18), label: const Text('Xem / sao chép config.py')),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _rotateKey(s),
              icon: const Icon(Icons.autorenew_rounded, size: 18),
              label: const Text('Đổi API key'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.warn),
            ),
            if (locked && s.allowedIp != null)
              OutlinedButton.icon(onPressed: _busy ? null : () => _unlockIp(s), icon: const Icon(Icons.lock_reset_rounded, size: 18), label: const Text('Mở khóa IP')),
          ]),
          if (s.securityEvents.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Cảnh báo bảo mật gần đây (gói giả mạo bị chặn):', style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
            const SizedBox(height: 6),
            for (final ev in s.securityEvents.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.block_rounded, size: 14, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${ev.label}${ev.ip != null ? ' — ${ev.ip}' : ''}  ·  ${ddmmHhmm(ev.at)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                  ),
                ]),
              ),
          ],
        ],
      ]),
    );
  }
}
