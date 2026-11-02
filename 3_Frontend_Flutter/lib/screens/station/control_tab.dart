import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/device_visuals.dart';
import 'station_screen.dart';

class ControlTab extends StatefulWidget {
  final Station station;
  final List<AlertItem> alerts;
  final Future<void> Function() onChanged;
  const ControlTab({super.key, required this.station, required this.alerts, required this.onChanged});

  @override
  State<ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends State<ControlTab> with AutomaticKeepAliveClientMixin {
  final _msg = TextEditingController();
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _mode(String m) async {
    setState(() => _busy = true);
    try {
      final note = await Session.I.setRelayMode(widget.station.id, m);
      if (mounted) toast(context, 'Đã chuyển sang ${_modeLabel(m)}. $note');
      await widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOled(String text) async {
    setState(() => _busy = true);
    try {
      final shown = await Session.I.setOled(widget.station.id, text);
      if (mounted) toast(context, shown.isEmpty ? 'Đã xoá dòng thông báo trên OLED' : 'OLED sẽ hiển thị: "$shown"');
      _msg.clear();
      await widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _modeLabel(String m) => switch (m) { 'ON' => 'BẬT thủ công', 'OFF' => 'TẮT thủ công', _ => 'Tự động' };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = widget.station;
    final admin = Session.I.isAdmin;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final relay = _relayCard(s, admin);
    final oled = _oledCard(s, admin);
    return TabBody(onRefresh: widget.onChanged, children: [
      if (!admin)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.warn.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.warn, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Tài khoản chỉ xem — đăng nhập admin để điều khiển relay và gửi thông báo OLED.', style: TextStyle(fontSize: 13))),
            ]),
          ),
        ),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: relay), const SizedBox(width: 16), Expanded(child: oled)])
      else ...[
        relay,
        const SizedBox(height: 16),
        oled,
      ],
      const SizedBox(height: 16),
      _logicCard(s),
    ]);
  }

  Widget _relayCard(Station s, bool admin) {
    final reason = s.relayLogs.isNotEmpty ? s.relayLogs.first.reason : 'Chưa có hoạt động';
    return SectionCard(
      title: 'Relay 5V',
      subtitle: s.relayLabel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          RelayVisual(on: s.relayOn, profile: s.profile),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: s.relayOn ? AppColors.ok : AppColors.muted),
                child: Text(s.relayOn ? 'ĐANG BẬT' : 'ĐANG TẮT'),
              ),
              const SizedBox(height: 2),
              Text(reason, style: const TextStyle(fontSize: 12.5, color: AppColors.text2)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'AUTO', label: Text('Tự động'), icon: Icon(Icons.auto_mode_rounded, size: 18)),
            ButtonSegment(value: 'ON', label: Text('Bật'), icon: Icon(Icons.power_settings_new_rounded, size: 18)),
            ButtonSegment(value: 'OFF', label: Text('Tắt'), icon: Icon(Icons.power_off_rounded, size: 18)),
          ],
          selected: {s.relayMode},
          onSelectionChanged: (!admin || _busy) ? null : (v) => _mode(v.first),
        ),
        const SizedBox(height: 10),
        Text(
          s.relayMode == 'AUTO'
              ? 'Server tự quyết định theo ngưỡng, có độ trễ ${fmt(s.hysteresis)}°C để relay không bật/tắt liên tục.'
              : 'Đang ghi đè thủ công — nhớ chuyển về Tự động sau khi xử lý xong.',
          style: TextStyle(fontSize: 12, color: s.relayMode == 'AUTO' ? AppColors.muted : AppColors.warn),
        ),
      ]),
    );
  }

  Widget _oledCard(Station s, bool admin) {
    final top = widget.alerts.isEmpty ? null : (widget.alerts.firstWhere((a) => a.level == 'DANGER', orElse: () => widget.alerts.first).type);
    const quick = ['DANG BAO TRI', 'KHONG MO CUA TU', 'LIEN HE KY THUAT'];
    return SectionCard(
      title: 'Màn hình OLED',
      subtitle: 'Xem trước nội dung tại thiết bị',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: FittedBox(child: OledPreview(s: s, topAlert: top))),
        const SizedBox(height: 16),
        TextField(
          controller: _msg,
          enabled: admin && !_busy,
          maxLength: 21,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (v) => _sendOled(v),
          decoration: InputDecoration(
            labelText: 'Gửi dòng thông báo lên OLED',
            hintText: 'Tối đa 21 ký tự, không dấu',
            prefixIcon: const Icon(Icons.short_text_rounded),
            suffixIcon: IconButton(
              tooltip: 'Gửi',
              icon: const Icon(Icons.send_rounded),
              onPressed: admin && !_busy ? () => _sendOled(_msg.text) : null,
            ),
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in quick) ActionChip(label: Text(q, style: const TextStyle(fontSize: 12)), onPressed: admin && !_busy ? () => _sendOled(q) : null),
          if ((s.oledMsg ?? '').isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.clear_rounded, size: 16, color: AppColors.danger),
              label: const Text('Xoá thông báo', style: TextStyle(fontSize: 12)),
              onPressed: admin && !_busy ? () => _sendOled('') : null,
            ),
        ]),
      ]),
    );
  }

  Widget _logicCard(Station s) {
    final rules = switch (s.profile) {
      'aquarium' => [
          'Nước > ${fmt(s.probeMax)}°C → bật quạt/bơm làm mát; tắt khi < ${fmt(s.probeMax - s.hysteresis)}°C.',
          'Nước < ${fmt(s.probeMin)}°C → cảnh báo nước quá lạnh.',
          'SHT30 trên mặt hồ dùng để đánh giá mức bay hơi.',
        ],
      'pharma' => [
          'Lõi tủ ngoài dải ${fmt(s.probeMin)}–${fmt(s.probeMax)}°C → NGUY HIỂM, hú còi.',
          'Sát ngưỡng 0.5°C → cảnh báo sớm.',
          'Biên sương < ${fmt(s.dewMargin)}°C → cảnh báo đọng nước bên ngoài tủ.',
        ],
      _ => [
          'Nước > ${fmt(s.probeMax)}°C hoặc không khí > ${fmt(s.airTempMax)}°C → bật relay.',
          'T − Td < ${fmt(s.dewMargin)}°C (nguy cơ đọng sương) → bật quạt thông gió.',
          'Relay tắt khi nhiệt độ thấp hơn ngưỡng ${fmt(s.hysteresis)}°C.',
        ],
    };
    return SectionCard(
      title: 'Luật điều khiển tự động',
      subtitle: ProfileStyle.of(s.profile).label,
      child: Column(children: [
        for (final r in rules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.rule_rounded, size: 16, color: AppColors.accent)),
              const SizedBox(width: 10),
              Expanded(child: Text(r, style: const TextStyle(fontSize: 13, color: AppColors.text2, height: 1.4))),
            ]),
          ),
      ]),
    );
  }
}
