import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'devices_screen.dart';
import 'staff_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final u = Session.I.user;
    final w = MediaQuery.sizeOf(context).width;
    final pad = w >= 600 ? 24.0 : 16.0;
    final initials = (u?.fullName ?? '?').trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final ini = initials.isEmpty ? '?' : initials.skip(initials.length > 1 ? initials.length - 2 : 0).map((e) => e[0]).join().toUpperCase();

    return Scaffold(
      appBar: AppBar(titleSpacing: pad, title: const Text('Tài khoản')),
      body: ListView(padding: EdgeInsets.fromLTRB(pad, 4, pad, 28), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.accent, AppColors.hum])),
                      child: Text(ini, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF04131D))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(u?.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        Text('@${u?.username ?? ''} · ${Session.I.isAdmin ? 'Quản trị viên' : 'Kỹ thuật viên'}', style: const TextStyle(color: AppColors.muted)),
                        if (u?.email != null && u!.email!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              children: [
                                const Icon(Icons.email_outlined, size: 13, color: AppColors.accent),
                                const SizedBox(width: 4),
                                Text(u.email!, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                              ],
                            ),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              // Card thông báo cảnh báo qua Gmail
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA4335).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.mark_email_unread_rounded, color: Color(0xFFEA4335), size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cảnh báo vượt ngưỡng qua Gmail', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                SizedBox(height: 2),
                                Text('Tự động gửi email khi nhiệt độ / độ ẩm nguy hiểm', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface3,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.alternate_email_rounded, size: 18, color: AppColors.accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Gmail nhận cảnh báo:', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                  Text(
                                    u?.email != null && u!.email!.isNotEmpty ? u.email! : 'Chưa cài đặt (nhấn Cài đặt để thêm)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: u?.email != null && u!.email!.isNotEmpty ? AppColors.text : AppColors.warn,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              icon: const Icon(Icons.edit_outlined, size: 14),
                              label: Text(u?.email != null && u!.email!.isNotEmpty ? 'Đổi' : 'Cài đặt'),
                              onPressed: () => _updateEmailDialog(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFEA4335)),
                            foregroundColor: const Color(0xFFEA4335),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 16),
                          label: const Text('📧 Gửi Thử Email Cảnh Báo Ngay', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          onPressed: () => _sendTestAlertEmail(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.dns_outlined, color: AppColors.accent),
                    title: const Text('Máy chủ API'),
                    subtitle: Text(Session.I.demo ? 'Chế độ Demo (không dùng server/MySQL)' : Session.I.baseUrl,
                        style: const TextStyle(color: AppColors.muted)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.password_rounded, color: AppColors.hum),
                    title: const Text('Đổi mật khẩu'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _changePassword(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
                    title: Text(Session.I.demo ? 'Thoát chế độ Demo' : 'Đăng xuất', style: const TextStyle(color: AppColors.danger)),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: AppColors.surface,
                          title: const Text('Đăng xuất?'),
                          content: const Text('Bạn sẽ cần đăng nhập lại để xem các trạm.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
                            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đăng xuất')),
                          ],
                        ),
                      );
                      if (ok == true) await Session.I.logout();
                    },
                  ),
                ]),
              ),
              if (Session.I.isAdmin) ...[
                const SizedBox(height: 16),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.developer_board_rounded, color: AppColors.probe),
                      title: const Text('Quản lý thiết bị phần cứng IoT'),
                      subtitle: const Text('Mã thiết bị Pico 2 W, API Key HMAC, thêm / xóa thiết bị', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesScreen())),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.people_alt_rounded, color: AppColors.accent),
                      title: const Text('Quản lý nhân sự & Phân công trạm'),
                      subtitle: const Text('Thêm nhân viên, đổi trạm phụ trách, xóa tài khoản', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffScreen())),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              const SectionCard(
                title: 'Về hệ thống',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _About(Icons.memory_rounded, 'Phần cứng',
                      'Raspberry Pi Pico 2 W · SHT30 (I²C, nhiệt độ + độ ẩm không khí) · DS18B20 (1-Wire, đầu dò chống nước) · Relay 5V · OLED SSD1306 0.96"'),
                  _About(Icons.storage_rounded, 'Phần mềm', 'App Flutter · API PHP 8 · CSDL MySQL 8 · Firmware MicroPython'),
                  _About(Icons.functions_rounded, 'Điểm sương', 'Công thức Magnus: Td = c·γ / (b − γ), γ = ln(RH/100) + b·T/(c+T), b = 17.62, c = 243.12°C'),
                  _About(Icons.sync_rounded, 'Cập nhật', 'Pico gửi dữ liệu mỗi 5 giây, app tự làm mới mỗi 5 giây'),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final oldC = TextEditingController(), newC = TextEditingController(), new2C = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (c) {
        String? err;
        bool busy = false;
        return StatefulBuilder(builder: (c, set) {
          Future<void> submit() async {
            if (newC.text.length < 6) {
              set(() => err = 'Mật khẩu mới tối thiểu 6 ký tự');
              return;
            }
            if (newC.text != new2C.text) {
              set(() => err = 'Mật khẩu nhập lại không khớp');
              return;
            }
            set(() {
              busy = true;
              err = null;
            });
            try {
              await Session.I.changePassword(oldC.text, newC.text);
              if (c.mounted) {
                Navigator.pop(c);
                toast(context, 'Đã đổi mật khẩu');
              }
            } catch (e) {
              set(() {
                busy = false;
                err = e.toString();
              });
            }
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Đổi mật khẩu'),
            content: SizedBox(
              width: 360,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: oldC, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại')),
                const SizedBox(height: 12),
                TextField(controller: newC, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu mới')),
                const SizedBox(height: 12),
                TextField(controller: new2C, obscureText: true, decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới')),
                if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!, style: const TextStyle(color: AppColors.danger))),
              ]),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(c), child: const Text('Huỷ')),
              FilledButton(onPressed: busy ? null : submit, child: const Text('Cập nhật')),
            ],
          );
        });
      },
    );
  }

  Future<void> _updateEmailDialog(BuildContext context) async {
    final curEmail = Session.I.user?.email ?? '';
    final ctrl = TextEditingController(text: curEmail);
    await showDialog<void>(
      context: context,
      builder: (c) {
        String? err;
        bool busy = false;
        return StatefulBuilder(builder: (c, set) {
          Future<void> submit() async {
            final email = ctrl.text.trim();
            if (email.isEmpty || !email.contains('@')) {
              set(() => err = 'Vui lòng nhập địa chỉ Gmail hợp lệ');
              return;
            }
            set(() {
              busy = true;
              err = null;
            });
            try {
              final ok = await Session.I.updateProfile(email: email);
              if (c.mounted) {
                if (ok) {
                  Navigator.pop(c);
                  toast(context, 'Đã cập nhật email nhận cảnh báo: $email');
                } else {
                  set(() {
                    busy = false;
                    err = 'Không thể lưu email, vui lòng thử lại';
                  });
                }
              }
            } catch (e) {
              set(() {
                busy = false;
                err = e.toString();
              });
            }
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Cài đặt Email nhận cảnh báo'),
            content: SizedBox(
              width: 360,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                  'Hệ thống sẽ tự động gửi email thông báo khẩn cấp tới địa chỉ này khi nhiệt độ hoặc độ ẩm vượt ngưỡng an toàn.',
                  style: TextStyle(fontSize: 13, color: AppColors.text2),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ Gmail của bạn',
                    prefixIcon: Icon(Icons.email_outlined),
                    hintText: 'vidu@gmail.com',
                  ),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(err!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(c), child: const Text('Huỷ')),
              FilledButton(onPressed: busy ? null : submit, child: const Text('Lưu Email')),
            ],
          );
        });
      },
    );
  }

  Future<void> _sendTestAlertEmail(BuildContext context) async {
    final email = Session.I.user?.email?.trim();
    if (email == null || email.isEmpty || !email.contains('@')) {
      toast(context, 'Vui lòng cài đặt địa chỉ Gmail trước khi gửi thử');
      _updateEmailDialog(context);
      return;
    }

    toast(context, 'Đang gửi email cảnh báo thử nghiệm tới $email...');
    final ok = await Session.I.testAlertEmail(email);
    if (context.mounted) {
      if (ok) {
        toast(context, '✅ Đã gửi email cảnh báo vi phạm ngưỡng tới $email! Vui lòng kiểm tra Gmail.');
      } else {
        toast(context, 'Gửi email không thành công. Vui lòng kiểm tra mạng.', error: true);
      }
    }
  }
}

class _About extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const _About(this.icon, this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: text, style: const TextStyle(color: AppColors.text2)),
          ])),
        ),
      ]),
    );
  }
}
