import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

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
  List<RelaySchedule> _schedules = [];
  List<StationActuator> _actuators = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    _loadActuators();
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  List<StationActuator> get _displayActuators {
    if (_actuators.isNotEmpty) return _actuators;
    return [
      StationActuator(id: 'misting', name: 'Hệ thống Phun sương Vi khí hậu', type: 'MISTING', state: false, mode: 'AUTO', level: 1, icon: 'water_drop', description: 'Bơm cao áp phun sương siêu mịn làm mát & tạo ẩm khi thời tiết hanh khô (Độ ẩm < 60%)', updatedAt: ''),
      StationActuator(id: 'fan', name: 'Quạt Thông gió Đối lưu Khí', type: 'FAN', state: false, mode: 'AUTO', level: 2, icon: 'air', description: 'Quạt hút nhiệt xả khí nóng và đối lưu khí tươi, đẩy ẩm chống va chạm điểm sương', updatedAt: ''),
      StationActuator(id: 'light', name: 'Đèn Sưởi Bức xạ & Quang hợp', type: 'LIGHT', state: false, mode: 'AUTO', level: 2, icon: 'lightbulb', description: 'Đèn nhiệt hồng ngoại sấy khô chống ngưng tụ ẩm và bổ sung quang phổ khi trời tối', updatedAt: ''),
      StationActuator(id: 'pump', name: 'Bơm Nước Tưới Nhỏ giọt & Tuần hoàn', type: 'PUMP', state: false, mode: 'MANUAL', level: 1, icon: 'opacity', description: 'Van điện từ & máy bơm cấp nước tưới tự động hoặc tuần hoàn nước dinh dưỡng', updatedAt: ''),
      StationActuator(id: 'siren', name: 'Còi Hú Báo động & Đèn Chớp Khẩn cấp', type: 'SIREN', state: false, mode: 'AUTO', level: 1, icon: 'emergency', description: 'Còi hú 105dB kết hợp đèn chớp strobe cảnh báo sự cố vi khí hậu tại hiện trường (DANGER)', updatedAt: ''),
    ];
  }

  Future<void> _loadActuators() async {
    try {
      final list = await Session.I.stationActuators(widget.station.id);
      if (mounted && list.isNotEmpty) setState(() => _actuators = list);
    } catch (_) {}
  }

  Future<void> _toggleActuator(StationActuator act, bool newState) async {
    HapticFeedback.lightImpact();
    final list = _displayActuators;
    final idx = list.indexWhere((a) => a.id == act.id);
    if (idx != -1) {
      final updatedList = List<StationActuator>.from(list);
      updatedList[idx] = StationActuator(
        id: act.id,
        name: act.name,
        type: act.type,
        state: newState,
        mode: 'MANUAL',
        level: act.level,
        icon: act.icon,
        description: act.description,
        updatedAt: act.updatedAt,
      );
      setState(() => _actuators = updatedList);
    }

    try {
      final updated = await Session.I.updateActuator(
        stationId: widget.station.id,
        actuatorId: act.id,
        state: newState,
        mode: 'MANUAL',
      );
      if (mounted && updated != null) {
        toast(context, 'Đã ${newState ? "BẬT" : "TẮT"} ${act.name}');
        _loadActuators();
      }
    } catch (e) {
      if (mounted) {
        toast(context, 'Lỗi điều khiển: $e', error: true);
        _loadActuators();
      }
    }
  }

  Future<void> _setActuatorMode(StationActuator act, String mode) async {
    HapticFeedback.selectionClick();
    try {
      final updated = await Session.I.updateActuator(
        stationId: widget.station.id,
        actuatorId: act.id,
        mode: mode,
      );
      if (mounted && updated != null) {
        toast(context, 'Đã chuyển ${act.name} sang ${mode == "AUTO" ? "Tự động" : "Thủ công"}');
        _loadActuators();
      }
    } catch (e) {
      if (mounted) toast(context, 'Lỗi: $e', error: true);
    }
  }

  Future<void> _setActuatorLevel(StationActuator act, int level) async {
    HapticFeedback.selectionClick();
    try {
      final updated = await Session.I.updateActuator(
        stationId: widget.station.id,
        actuatorId: act.id,
        level: level,
      );
      if (mounted && updated != null) {
        toast(context, 'Đã đặt ${act.name} ở Cấp $level');
        _loadActuators();
      }
    } catch (e) {
      if (mounted) toast(context, 'Lỗi: $e', error: true);
    }
  }

  Future<void> _testActuator(String actId, String name, int seconds) async {
    HapticFeedback.heavyImpact();
    setState(() => _busy = true);
    try {
      final ok = await Session.I.testActuator(
        stationId: widget.station.id,
        actuatorId: actId,
        durationSeconds: seconds,
      );
      if (mounted) {
        if (ok) {
          toast(context, '⚡ Đang kích hoạt TEST $name trong $seconds giây...');
          _loadActuators();
        } else {
          toast(context, 'Không thể kích hoạt test', error: true);
        }
      }
    } catch (e) {
      if (mounted) toast(context, 'Lỗi: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSchedules() async {
    try {
      final list = await Session.I.relaySchedules(widget.station.id);
      if (mounted) setState(() => _schedules = list);
    } catch (_) {}
  }

  Future<void> _setCountdown(int minutes, String mode) async {
    setState(() => _busy = true);
    try {
      final ok = await Session.I.createRelaySchedule(
        stationId: widget.station.id,
        minutes: minutes,
        targetMode: mode,
      );
      if (mounted) {
        if (ok) {
          toast(context, '⏱️ Đã kích hoạt hẹn giờ chuyển sang $mode sau $minutes phút');
          _loadSchedules();
        } else {
          toast(context, 'Không thể đặt hẹn giờ', error: true);
        }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelSchedule(int id) async {
    try {
      await Session.I.cancelRelaySchedule(id);
      if (mounted) {
        toast(context, 'Đã hủy lịch hẹn giờ');
        _loadSchedules();
      }
    } catch (_) {}
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
    final isEsp = s.isEsp32;
    final admin = Session.I.isAdmin;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final relay = _relayCard(s, admin);
    final oled = _oledCard(s, admin);
    final sched = _schedulerCard(s);
    final actuators = _actuatorsCard(s, admin);

    return TabBody(onRefresh: () async {
      await Future.wait([
        widget.onChanged(),
        _loadActuators(),
        _loadSchedules(),
      ]);
    }, children: [
      actuators,
      const SizedBox(height: 16),
      if (wide) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: relay),
          const SizedBox(width: 16),
          Expanded(child: sched),
        ]),
        if (!isEsp) ...[
          const SizedBox(height: 16),
          oled,
        ],
      ] else ...[
        relay,
        const SizedBox(height: 16),
        sched,
        if (!isEsp) ...[
          const SizedBox(height: 16),
          oled,
        ],
      ],
      const SizedBox(height: 16),
      _logicCard(s),
    ]);
  }

  Widget _schedulerCard(Station s) {
    return SectionCard(
      title: 'Hẹn giờ Đếm ngược (Smart Scheduler)',
      subtitle: 'Tự động Bật / Tắt Rơ-le sau một khoảng thời gian',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.timer_outlined, size: 16, color: AppColors.warn),
                label: const Text('Tắt sau 15p'),
                onPressed: _busy ? null : () => _setCountdown(15, 'OFF'),
              ),
              ActionChip(
                avatar: const Icon(Icons.timer_outlined, size: 16, color: AppColors.warn),
                label: const Text('Tắt sau 30p'),
                onPressed: _busy ? null : () => _setCountdown(30, 'OFF'),
              ),
              ActionChip(
                avatar: const Icon(Icons.timer_outlined, size: 16, color: AppColors.warn),
                label: const Text('Tắt sau 1 giờ'),
                onPressed: _busy ? null : () => _setCountdown(60, 'OFF'),
              ),
              ActionChip(
                avatar: const Icon(Icons.flash_on_rounded, size: 16, color: AppColors.ok),
                label: const Text('Bật sau 15p'),
                onPressed: _busy ? null : () => _setCountdown(15, 'ON'),
              ),
            ],
          ),
          if (_schedules.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            Text(
              'LỊCH HẸN GIỜ ĐANG CHẠY (${_schedules.length}):',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text3, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            ..._schedules.map((sc) {
              final minsLeft = (sc.secondsRemaining / 60).ceil();
              final isOff = sc.targetMode == 'OFF';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, size: 18, color: isOff ? AppColors.warn : AppColors.ok),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chuyển sang ${sc.targetMode == "ON" ? "BẬT" : "TẮT"} Rơ-le',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
                          ),
                          Text(
                            'Còn lại ~$minsLeft phút (Tổng ${sc.durationMinutes}p)',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.text2),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.danger),
                      tooltip: 'Hủy lịch này',
                      onPressed: () => _cancelSchedule(sc.id),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _relayCard(Station s, bool admin) {
    final isEsp = s.isEsp32;
    final reason = s.relayLogs.isNotEmpty ? s.relayLogs.first.reason : 'Chưa có hoạt động';
    return SectionCard(
      title: isEsp ? 'Đèn LED tích hợp (GPIO 2)' : 'Relay 5V',
      subtitle: isEsp ? (s.relayLabel.isNotEmpty ? s.relayLabel : 'Đèn LED trên vi điều khiển ESP32') : s.relayLabel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (isEsp)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: (s.relayOn ? const Color(0xFFFACC15) : AppColors.surface2),
                shape: BoxShape.circle,
                boxShadow: s.relayOn ? [BoxShadow(color: const Color(0xFFFACC15).withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 2)] : null,
              ),
              child: Icon(Icons.lightbulb_rounded, size: 28, color: s.relayOn ? Colors.black : AppColors.muted),
            )
          else
            RelayVisual(on: s.relayOn, profile: s.profile),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: s.relayOn ? (isEsp ? const Color(0xFFFACC15) : AppColors.ok) : AppColors.muted),
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
          onSelectionChanged: _busy ? null : (v) => _mode(v.first),
        ),
        const SizedBox(height: 10),
        Text(
          s.relayMode == 'AUTO'
              ? (isEsp
                  ? 'Server tự quyết định bật/tắt đèn LED theo ngưỡng nhiệt độ và độ ẩm của DHT11.'
                  : 'Server tự quyết định theo ngưỡng, có độ trễ ${fmt(s.hysteresis)}°C để relay không bật/tắt liên tục.')
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
          enabled: !_busy,
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
              onPressed: !_busy ? () => _sendOled(_msg.text) : null,
            ),
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in quick) ActionChip(label: Text(q, style: const TextStyle(fontSize: 12)), onPressed: !_busy ? () => _sendOled(q) : null),
          if ((s.oledMsg ?? '').isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.clear_rounded, size: 16, color: AppColors.danger),
              label: const Text('Xoá thông báo', style: TextStyle(fontSize: 12)),
              onPressed: !_busy ? () => _sendOled('') : null,
            ),
        ]),
      ]),
    );
  }

  Widget _logicCard(Station s) {
    final List<String> rules;
    if (s.isEsp32) {
      rules = [
        'Nhiệt độ không khí DHT11 > ${fmt(s.airTempMax)}°C → Tự động BẬT đèn LED cảnh báo (GPIO 2).',
        'Độ ẩm không khí DHT11 > ${fmt(s.airHumMax)}% → Tự động BẬT đèn LED cảnh báo.',
        'T − Td < ${fmt(s.dewMargin)}°C (nguy cơ đọng sương) → Cảnh báo nguy cơ ẩm mốc.',
        'Tắt đèn LED khi nhiệt độ và độ ẩm hạ xuống dưới ngưỡng an toàn.',
      ];
    } else {
      rules = switch (s.profile) {
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
    }
    return SectionCard(
      title: 'Luật điều khiển tự động',
      subtitle: s.isEsp32 ? 'ESP32 NodeMCU + DHT11 + LED' : ProfileStyle.of(s.profile).label,
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

  Color _actuatorColor(String id) {
    switch (id) {
      case 'misting':
        return const Color(0xFF38BDF8); // Sky blue
      case 'fan':
        return const Color(0xFF34D399); // Emerald green
      case 'light':
        return const Color(0xFFFBBF24); // Warm gold
      case 'pump':
        return const Color(0xFF60A5FA); // Royal blue
      case 'siren':
        return const Color(0xFFEF4444); // Alarm red
      default:
        return AppColors.primary;
    }
  }

  IconData _actuatorIcon(String id) {
    switch (id) {
      case 'misting':
        return Icons.water_drop_rounded;
      case 'fan':
        return Icons.air_rounded;
      case 'light':
        return Icons.lightbulb_rounded;
      case 'pump':
        return Icons.opacity_rounded;
      case 'siren':
        return Icons.emergency_rounded;
      default:
        return Icons.power_rounded;
    }
  }

  Widget _actuatorsCard(Station s, bool admin) {
    final list = _displayActuators;
    final activeCount = list.where((a) => a.state).length;

    return SectionCard(
      title: 'Bảng Điều khiển Thiết bị Chấp hành Ngoại vi',
      subtitle: '5 hệ thống điều khiển vi khí hậu thông minh (Đang hoạt động: $activeCount/5)',
      trailing: IconButton(
        icon: const Icon(Icons.refresh_rounded, size: 20),
        tooltip: 'Làm mới trạng thái thiết bị',
        onPressed: _loadActuators,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...list.map((act) => _buildActuatorItem(act, admin)),
        ],
      ),
    );
  }

  Widget _buildActuatorItem(StationActuator act, bool admin) {
    final color = _actuatorColor(act.id);
    final icon = _actuatorIcon(act.id);
    final isOn = act.state;
    final isAuto = act.mode == 'AUTO';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOn ? color.withValues(alpha: 0.08) : AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOn ? color.withValues(alpha: 0.45) : AppColors.border,
          width: isOn ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Icon, Name, Status, Switch
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isOn ? color.withValues(alpha: 0.22) : AppColors.surface3,
                  shape: BoxShape.circle,
                  boxShadow: isOn
                      ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: 1)]
                      : null,
                ),
                child: Icon(icon, size: 24, color: isOn ? color : AppColors.text3),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      act.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.text),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOn ? color : AppColors.muted,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isOn ? 'ĐANG BẬT' : 'ĐANG TẮT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isOn ? color : AppColors.text3,
                          ),
                        ),
                        Text(
                          ' · ${isAuto ? "Tự động" : "Thủ công"}${act.id == "fan" || act.id == "light" ? " (Cấp ${act.level})" : ""}',
                          style: const TextStyle(fontSize: 11, color: AppColors.text2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isOn,
                activeTrackColor: color.withValues(alpha: 0.5),
                activeThumbColor: color,
                onChanged: !_busy ? (val) => _toggleActuator(act, val) : null,
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            act.description,
            style: const TextStyle(fontSize: 11.5, color: AppColors.text2, height: 1.35),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),

          // Row 2: Control Toolbar
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Tự động (Auto)', style: TextStyle(fontSize: 11)),
                selected: isAuto,
                onSelected: !_busy ? (val) => _setActuatorMode(act, 'AUTO') : null,
              ),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Thủ công (Manual)', style: TextStyle(fontSize: 11)),
                selected: !isAuto,
                onSelected: !_busy ? (val) => _setActuatorMode(act, 'MANUAL') : null,
              ),

              if (act.id == 'fan') ...[
                const SizedBox(width: 4),
                const Text('Tốc độ:', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                ...[1, 2, 3].map((lv) => ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(lv == 1 ? '1-Êm' : (lv == 2 ? '2-Vừa' : '3-Mạnh'), style: const TextStyle(fontSize: 10.5)),
                      selected: act.level == lv,
                      onSelected: !_busy ? (val) => _setActuatorLevel(act, lv) : null,
                    )),
              ],

              if (act.id == 'light') ...[
                const SizedBox(width: 4),
                ...[1, 2].map((lv) => ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(lv == 1 ? '50% Sấy ấm' : '100% Cường độ cao', style: const TextStyle(fontSize: 10.5)),
                      selected: act.level == lv,
                      onSelected: !_busy ? (val) => _setActuatorLevel(act, lv) : null,
                    )),
              ],

              if (act.id == 'misting') ...[
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.flash_on_rounded, size: 13, color: Color(0xFF38BDF8)),
                  label: const Text('Phun thử 15s', style: TextStyle(fontSize: 11, color: Color(0xFF38BDF8))),
                  onPressed: !_busy ? () => _testActuator('misting', 'Phun sương', 15) : null,
                ),
              ],

              if (act.id == 'pump') ...[
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.timer_outlined, size: 13, color: Color(0xFF60A5FA)),
                  label: const Text('Tưới nhanh 5p', style: TextStyle(fontSize: 11, color: Color(0xFF60A5FA))),
                  onPressed: !_busy ? () => _testActuator('pump', 'Bơm tưới', 300) : null,
                ),
              ],

              if (act.id == 'siren') ...[
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFF3A1320),
                  avatar: const Icon(Icons.volume_up_rounded, size: 13, color: AppColors.danger),
                  label: const Text('🔔 Test Còi 5 Giây', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.danger)),
                  onPressed: !_busy ? () => _testActuator('siren', 'Còi hú báo động', 5) : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
