import 'package:flutter/material.dart';

import 'theme.dart';

String fmt(double? v, [int d = 1]) => v == null || v.isNaN ? '--' : v.toStringAsFixed(d);

String two(int n) => n.toString().padLeft(2, '0');

String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
String hhmmss(DateTime t) => '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
String ddmmHhmm(DateTime? t) => t == null ? '--' : '${two(t.day)}/${two(t.month)} ${hhmmss(t)}';

String ago(DateTime? t) {
  if (t == null) return 'chưa có dữ liệu';
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 5) return 'vừa xong';
  if (s < 60) return '$s giây trước';
  if (s < 3600) return '${s ~/ 60} phút trước';
  if (s < 86400) return '${s ~/ 3600} giờ trước';
  return '${s ~/ 86400} ngày trước';
}

/// Thong tin hien thi cho tung trang thai
class StatusStyle {
  final String label;
  final Color color;
  final IconData icon;
  const StatusStyle(this.label, this.color, this.icon);

  static StatusStyle of(String s) => switch (s) {
        'OK' => const StatusStyle('Ổn định', AppColors.ok, Icons.verified_user_rounded),
        'WARNING' => const StatusStyle('Cảnh báo', AppColors.warn, Icons.warning_amber_rounded),
        'DANGER' => const StatusStyle('Nguy hiểm', AppColors.danger, Icons.emergency_rounded),
        _ => const StatusStyle('Mất kết nối', AppColors.off, Icons.wifi_off_rounded),
      };
}

/// Thong tin hien thi cho tung kich ban ung dung
class ProfileStyle {
  final String label, probeLabel, relayVerb;
  final IconData icon, relayIcon;
  final Color color;
  const ProfileStyle(this.label, this.probeLabel, this.relayVerb, this.icon, this.relayIcon, this.color);

  static ProfileStyle of(String p) => switch (p) {
        'aquarium' => const ProfileStyle('Hồ cá / Thủy canh', 'Nhiệt độ nước', 'Quạt / Bơm', Icons.set_meal_rounded, Icons.toys_rounded, AppColors.dew),
        'pharma' => const ProfileStyle('Tủ bảo quản', 'Nhiệt độ lõi tủ', 'Còi', Icons.vaccines_rounded, Icons.campaign_rounded, AppColors.hum),
        _ => const ProfileStyle('Hệ thống giám sát IoT', 'Nhiệt độ nước', 'Rơ-le / Bơm', Icons.water_drop_rounded, Icons.toys_rounded, AppColors.probe),
      };

  static const all = ['cabinet', 'aquarium', 'pharma'];
}

const alertTypeLabels = {
  'AIR_TEMP_HIGH': 'Nhiệt độ không khí cao',
  'AIR_HUM_HIGH': 'Độ ẩm cao',
  'PROBE_HIGH': 'Nhiệt độ nước cao',
  'PROBE_LOW': 'Nhiệt độ nước thấp',
  'DEW_RISK': 'Nguy cơ đọng sương',
  'SENSOR_ERROR': 'Lỗi cảm biến',
  'OFFLINE': 'Mất kết nối',
};

void toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: error ? AppColors.danger : AppColors.ok, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(msg)),
    ]),
    duration: Duration(seconds: error ? 4 : 2),
  ));
}
