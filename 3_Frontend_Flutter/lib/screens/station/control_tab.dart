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
  List<AutomationRule> _automations = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    _loadActuators();
    _loadAutomations();
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

  Future<void> _loadAutomations() async {
    try {
      final list = await Session.I.stationAutomations(widget.station.id);
      if (mounted && list.isNotEmpty) setState(() => _automations = list);
    } catch (_) {}
  }

  Future<void> _toggleAutomation(AutomationRule rule, bool enabled) async {
    setState(() => rule.isEnabled = enabled);
    try {
      final ok = await Session.I.toggleAutomation(rule.id, enabled);
      if (ok) {
        if (mounted) toast(context, enabled ? '⚡ Đã kích hoạt kịch bản "${rule.name}"' : '⏸️ Đã tạm dừng kịch bản "${rule.name}"');
      } else {
        setState(() => rule.isEnabled = !enabled);
      }
    } catch (e) {
      setState(() => rule.isEnabled = !enabled);
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _runAutomation(AutomationRule rule) async {
    setState(() => _busy = true);
    try {
      final ok = await Session.I.runAutomation(rule.id);
      if (mounted) {
        if (ok) {
          toast(context, '🚀 Đang chạy thử kịch bản "${rule.name}"...');
          await Future.wait([
            _loadActuators(),
            _loadAutomations(),
            widget.onChanged(),
          ]);
        } else {
          toast(context, 'Không thể chạy thử kịch bản', error: true);
        }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAutomation(AutomationRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa kịch bản?'),
        content: Text('Bạn có chắc chắn muốn xóa kịch bản "${rule.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final res = await Session.I.deleteAutomation(rule.id);
      if (mounted) {
        if (res) {
          toast(context, 'Đã xóa kịch bản');
          _loadAutomations();
        } else {
          toast(context, 'Không thể xóa kịch bản', error: true);
        }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final automations = _automationsCard(s);

    return TabBody(onRefresh: () async {
      await Future.wait([
        widget.onChanged(),
        _loadActuators(),
        _loadSchedules(),
        _loadAutomations(),
      ]);
    }, children: [
      actuators,
      const SizedBox(height: 16),
      automations,
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

  Widget _automationsCard(Station s) {
    return SectionCard(
      title: 'Kịch bản Tự động hóa Thông minh (Smart Routines)',
      subtitle: 'Tự động kích hoạt thiết bị khi chạm điều kiện vi khí hậu',
      trailing: FilledButton.tonalIcon(
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: _busy ? null : () => _showAddAutomationDialog(s),
        icon: const Icon(Icons.add_rounded, size: 17),
        label: const Text('Thêm kịch bản'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_automations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('Đang tải danh sách kịch bản tự động hóa...', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ),
            )
          else
            ..._automations.map((rule) => _buildAutomationItem(rule, s)),
        ],
      ),
    );
  }

  Widget _buildAutomationItem(AutomationRule rule, Station s) {
    IconData icon = Icons.bolt_rounded;
    Color iconColor = AppColors.accent;
    if (rule.icon == 'ac_unit' || rule.targetId == 'fan') {
      icon = Icons.ac_unit_rounded;
      iconColor = const Color(0xFF38BDF8);
    } else if (rule.icon == 'water_drop' || rule.targetId == 'misting') {
      icon = Icons.water_drop_rounded;
      iconColor = const Color(0xFF0EA5E9);
    } else if (rule.icon == 'fire' || rule.conditionType == 'GAS_GT') {
      icon = Icons.local_fire_department_rounded;
      iconColor = AppColors.danger;
    } else if (rule.icon == 'air' || rule.conditionType == 'AQI_GT') {
      icon = Icons.air_rounded;
      iconColor = const Color(0xFF8B5CF6);
    } else if (rule.conditionType == 'WATER_LT') {
      icon = Icons.water_drop_rounded;
      iconColor = const Color(0xFF38BDF8);
    } else if (rule.conditionType == 'SOIL_LT') {
      icon = Icons.grass_rounded;
      iconColor = const Color(0xFF10B981);
    } else if (rule.icon == 'shield' || (rule.targetId == 'light' && rule.conditionType == 'DEW_MARGIN_LT')) {
      icon = Icons.shield_rounded;
      iconColor = const Color(0xFFF59E0B);
    } else if (rule.icon == 'lightbulb' || rule.conditionType.startsWith('LIGHT') || rule.targetId == 'light') {
      icon = Icons.lightbulb_rounded;
      iconColor = const Color(0xFFFACC15);
    } else if (rule.icon == 'eco' || rule.targetId == 'pump') {
      icon = Icons.eco_rounded;
      iconColor = const Color(0xFF10B981);
    } else if (rule.icon == 'warning' || rule.targetId == 'siren') {
      icon = Icons.warning_amber_rounded;
      iconColor = AppColors.danger;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rule.isEnabled ? AppColors.surface2 : AppColors.surface2.withAlpha(120),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rule.isEnabled ? iconColor.withAlpha(70) : AppColors.border,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(rule.isEnabled ? 40 : 20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: rule.isEnabled ? iconColor : AppColors.muted, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: rule.isEnabled ? AppColors.text : AppColors.text2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'NẾU: ${rule.conditionText} ➔ THÌ: ${rule.actionText}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: rule.isEnabled ? iconColor : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: rule.isEnabled,
                activeTrackColor: iconColor.withAlpha(120),
                activeThumbColor: iconColor,
                onChanged: _busy ? null : (val) => _toggleAutomation(rule, val),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Đã kích hoạt: ${rule.triggerCount} lần${rule.lastTriggeredAt != null ? ' · ${rule.lastTriggeredAt}' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.text3),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  side: BorderSide(color: iconColor.withAlpha(100)),
                ),
                onPressed: _busy ? null : () => _runAutomation(rule),
                icon: Icon(Icons.play_arrow_rounded, size: 15, color: iconColor),
                label: Text('Chạy thử', style: TextStyle(fontSize: 11, color: iconColor)),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.text3),
                tooltip: 'Xóa kịch bản',
                onPressed: _busy ? null : () => _deleteAutomation(rule),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAddAutomationDialog(Station s) async {
    final conditionConfigs = {
      'TEMP_GT': {
        'label': '🔥 Nhiệt độ quá nóng (≥)',
        'unit': '°C',
        'defaultThresh': '36.0',
        'defaultName': 'Hạ nhiệt khi trời quá nóng',
        'helper': 'Nhiệt độ không khí đo từ cảm biến (°C)',
        'targetId': 'fan',
        'targetLevel': 3,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 120,
      },
      'TEMP_LT': {
        'label': '❄️ Nhiệt độ quá lạnh (≤)',
        'unit': '°C',
        'defaultThresh': '18.0',
        'defaultName': 'Sưởi ấm khi trời lạnh',
        'helper': 'Nhiệt độ môi trường hạ thấp (°C)',
        'targetId': 'light',
        'targetLevel': 1,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 300,
      },
      'HUM_LT': {
        'label': '🌵 Độ ẩm hanh khô (≤)',
        'unit': '%',
        'defaultThresh': '45.0',
        'defaultName': 'Phun sương tạo ẩm khi hanh khô',
        'helper': 'Độ ẩm không khí xuống thấp (%)',
        'targetId': 'misting',
        'targetLevel': 1,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 20,
      },
      'HUM_GT': {
        'label': '💧 Độ ẩm quá cao (≥)',
        'unit': '%',
        'defaultThresh': '85.0',
        'defaultName': 'Quạt thông gió đẩy ẩm',
        'helper': 'Độ ẩm không khí tăng cao (%)',
        'targetId': 'fan',
        'targetLevel': 2,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 120,
      },
      'LIGHT_LT': {
        'label': '🌙 Trời tối / Thiếu sáng (≤)',
        'unit': '%',
        'defaultThresh': '20.0',
        'defaultName': 'Tự động bật đèn khi trời tối',
        'helper': 'Quang trở LDR: 0% = Tối om, 100% = Sáng rực',
        'targetId': 'light',
        'targetLevel': 2,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 0,
      },
      'LIGHT_GT': {
        'label': '☀️ Nắng gắt / Sáng chói (≥)',
        'unit': '%',
        'defaultThresh': '80.0',
        'defaultName': 'Bật quạt khi nắng gắt',
        'helper': 'Cường độ quang trở đo được (%)',
        'targetId': 'fan',
        'targetLevel': 2,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 120,
      },
      'DEW_MARGIN_LT': {
        'label': '🛡️ Nguy cơ đọng sương (T−Td ≤)',
        'unit': '°C',
        'defaultThresh': '2.0',
        'defaultName': 'Sấy khô chống đọng sương vi mạch',
        'helper': 'Biên an toàn sương: ≤ 2°C có nguy cơ đọng ẩm',
        'targetId': 'light',
        'targetLevel': 2,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 180,
      },
      'GAS_GT': {
        'label': '🔥 Khói / Gas MQ-2 cao (≥) [Đang phát triển]',
        'unit': 'ppm',
        'defaultThresh': '100.0',
        'defaultName': 'Bật còi hú & quạt khi có khói gas',
        'helper': 'Nồng độ khói / gas rò rỉ (ppm) [Lộ trình mở rộng]',
        'targetId': 'siren',
        'targetLevel': 1,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 15,
      },
      'AQI_GT': {
        'label': '🌬️ Không khí ô nhiễm AQI (≥) [Đang phát triển]',
        'unit': 'AQI',
        'defaultThresh': '120.0',
        'defaultName': 'Bật quạt đối lưu lọc bụi AQI',
        'helper': 'Chỉ số chất lượng không khí (>100 là kém) [Lộ trình mở rộng]',
        'targetId': 'fan',
        'targetLevel': 3,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 180,
      },
      'WATER_LT': {
        'label': '🚰 Bồn nước sắp cạn (≤) [Đang phát triển]',
        'unit': '%',
        'defaultThresh': '20.0',
        'defaultName': 'Tự ngắt máy bơm bảo vệ cháy bơm',
        'helper': 'Mực nước bồn chứa còn lại (%) [Lộ trình mở rộng]',
        'targetId': 'pump',
        'targetLevel': 1,
        'actionType': 'ACTUATOR_OFF',
        'durationSec': 0,
      },
      'SOIL_LT': {
        'label': '🌱 Đất trồng khô hạn (≤) [Đang phát triển]',
        'unit': '%',
        'defaultThresh': '40.0',
        'defaultName': 'Tự động bơm tưới ẩm đất',
        'helper': 'Độ ẩm đất / chất nền trồng trọt (%) [Lộ trình mở rộng]',
        'targetId': 'pump',
        'targetLevel': 1,
        'actionType': 'ACTUATOR_ON',
        'durationSec': 180,
      },
    };

    final initCfg = conditionConfigs['TEMP_GT']!;
    final nameCtrl = TextEditingController(text: initCfg['defaultName'] as String);
    String conditionType = 'TEMP_GT';
    final threshCtrl = TextEditingController(text: initCfg['defaultThresh'] as String);
    String targetId = initCfg['targetId'] as String;
    String actionType = initCfg['actionType'] as String;
    int targetLevel = initCfg['targetLevel'] as int;
    int durationSec = initCfg['durationSec'] as int;

    final actuatorsMap = {
      'fan': 'Quạt thông gió',
      'misting': 'Phun sương vi khí hậu',
      'pump': 'Máy bơm tưới',
      'light': 'Đèn sưởi & quang hợp',
      'siren': 'Còi hú báo động',
      'relay': s.relayLabel.isNotEmpty ? s.relayLabel : 'Rơ-le điện 220V',
    };

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMState) {
          final curCfg = conditionConfigs[conditionType] ?? initCfg;
          final curUnit = curCfg['unit'] as String;
          final curHelper = curCfg['helper'] as String;

          void applyPreset(String newCond) {
            final cfg = conditionConfigs[newCond];
            if (cfg != null) {
              setMState(() {
                conditionType = newCond;
                threshCtrl.text = cfg['defaultThresh'] as String;
                nameCtrl.text = cfg['defaultName'] as String;
                targetId = cfg['targetId'] as String;
                targetLevel = cfg['targetLevel'] as int;
                actionType = cfg['actionType'] as String;
                durationSec = cfg['durationSec'] as int;
              });
            }
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.accent.withAlpha(40), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.bolt_rounded, color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Tạo Kịch bản Tự động hóa mới', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên kịch bản',
                      hintText: 'VD: Hạ nhiệt buổi trưa, Tưới cây tự động...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('ĐIỀU KIỆN KÍCH HOẠT (NẾU):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: ValueKey('cond-$conditionType'),
                    isExpanded: true,
                    initialValue: conditionType,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: conditionConfigs.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        e.value['label'] as String,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) applyPreset(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: threshCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Ngưỡng giá trị kích hoạt ($curUnit)',
                      suffixText: curUnit,
                      helperText: curHelper,
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('HÀNH ĐỘNG THỰC THI (THÌ):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ok)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: ValueKey('target-$conditionType-$targetId'),
                    isExpanded: true,
                    initialValue: targetId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: actuatorsMap.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    )).toList(),
                    onChanged: (v) => setMState(() {
                      targetId = v ?? 'fan';
                      if (targetId == 'fan') targetLevel = 3;
                      if (targetId == 'misting') durationSec = 15;
                      if (targetId == 'siren') durationSec = 5;
                      if (targetId == 'pump') durationSec = 300;
                    }),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('act-$conditionType-$actionType'),
                        isExpanded: true,
                        initialValue: actionType,
                        decoration: const InputDecoration(labelText: 'Lệnh', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        items: const [
                          DropdownMenuItem(value: 'ACTUATOR_ON', child: Text('Bật thiết bị')),
                          DropdownMenuItem(value: 'ACTUATOR_OFF', child: Text('Tắt thiết bị')),
                        ],
                        onChanged: (v) => setMState(() => actionType = v ?? 'ACTUATOR_ON'),
                      ),
                    ),
                    if (targetId == 'fan' && actionType == 'ACTUATOR_ON') ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('fan-lvl-$targetLevel'),
                          isExpanded: true,
                          initialValue: targetLevel,
                          decoration: const InputDecoration(labelText: 'Tốc độ', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Cấp 1 - Êm')),
                            DropdownMenuItem(value: 2, child: Text('Cấp 2 - Vừa')),
                            DropdownMenuItem(value: 3, child: Text('Cấp 3 - Mạnh')),
                          ],
                          onChanged: (v) => setMState(() => targetLevel = v ?? 3),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      final val = double.tryParse(threshCtrl.text.replaceAll(',', '.')) ?? 35.0;
                      final icon = conditionType.startsWith('LIGHT')
                          ? 'lightbulb'
                          : (conditionType == 'GAS_GT' || targetId == 'siren'
                              ? 'fire'
                              : (conditionType == 'AQI_GT'
                                  ? 'air'
                                  : (targetId == 'misting'
                                      ? 'water_drop'
                                      : (targetId == 'fan'
                                          ? 'ac_unit'
                                          : (targetId == 'light'
                                              ? 'shield'
                                              : (targetId == 'pump' ? 'eco' : 'bolt'))))));
                      final rule = AutomationRule(
                        id: '',
                        stationId: s.id,
                        name: nameCtrl.text.trim().isEmpty ? 'Kịch bản tự động' : nameCtrl.text.trim(),
                        icon: icon,
                        isEnabled: true,
                        conditionType: conditionType,
                        thresholdValue: val,
                        actionType: actionType,
                        targetId: targetId,
                        targetName: actuatorsMap[targetId] ?? targetId,
                        targetLevel: targetLevel,
                        durationSeconds: durationSec,
                        createdAt: '',
                      );
                      Navigator.pop(ctx, true);
                      setState(() => _busy = true);
                      try {
                        final ok = await Session.I.saveAutomation(rule);
                        if (mounted) {
                          if (ok) {
                            toast(context, '🎉 Đã lưu kịch bản tự động hóa mới!');
                            _loadAutomations();
                          } else {
                            toast(context, 'Không thể lưu kịch bản', error: true);
                          }
                        }
                      } catch (e) {
                        if (mounted) toast(context, e.toString(), error: true);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Lưu & Kích hoạt Kịch bản'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
