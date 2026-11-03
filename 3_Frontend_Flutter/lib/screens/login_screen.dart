import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController(text: Session.I.baseUrl);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false, _hide = true, _showServer = false;
  String? _err;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _err = 'Nhập tên đăng nhập và mật khẩu');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Session.I.login(_server.text, _user.text.trim(), _pass.text);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showRegisterDialog() {
    final formKey = GlobalKey<FormState>();
    final uCtrl = TextEditingController();
    final fCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    final pCtrl = TextEditingController();
    final p2Ctrl = TextEditingController();
    bool hideP = true;
    bool saving = false;
    bool sendingOtp = false;
    int countdown = 0;
    Timer? countdownTimer;
    String? dErr;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: AppColors.surface,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.air.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.air, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Đăng ký nhân viên', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('Xác thực OTP qua số điện thoại', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dErr != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(dErr!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))),
                          ],
                        ),
                      ),
                    TextFormField(
                      controller: fCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên nhân viên *',
                        hintText: 'VD: Nguyễn Văn A',
                        prefixIcon: Icon(Icons.badge_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập họ tên' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: uCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên đăng nhập *',
                        hintText: 'VD: nhanvien01',
                        prefixIcon: Icon(Icons.account_circle_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập tên đăng nhập' : null,
                    ),
                    const SizedBox(height: 12),
                    // Email / Số điện thoại & nút gửi OTP
                    TextFormField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email hoặc Số điện thoại *',
                        hintText: 'VD: nhanvien@gmail.com',
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextButton(
                            onPressed: (sendingOtp || countdown > 0)
                                ? null
                                : () async {
                                    final p = phoneCtrl.text.trim();
                                    if (p.length < 5) {
                                      setDState(() => dErr = 'Vui lòng nhập Email hoặc Số điện thoại hợp lệ');
                                      return;
                                    }
                                    setDState(() {
                                      sendingOtp = true;
                                      dErr = null;
                                    });
                                    try {
                                      final res = await Session.I.sendOtp(
                                        server: _server.text,
                                        target: p,
                                        purpose: 'register',
                                      );
                                      final isRealSent = res['email_sent'] == true || res['sms_sent'] == true;
                                      final demoCode = res['otp_demo']?.toString();
                                      if (!isRealSent && demoCode != null) {
                                        otpCtrl.text = demoCode;
                                      }
                                      setDState(() {
                                        sendingOtp = false;
                                        countdown = 60;
                                      });
                                      countdownTimer?.cancel();
                                      countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                                        if (countdown > 1) {
                                          setDState(() => countdown--);
                                        } else {
                                          t.cancel();
                                          setDState(() => countdown = 0);
                                        }
                                      });
                                      if (ctx.mounted) {
                                        final isEmail = p.contains('@');
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text(isRealSent
                                                ? (isEmail
                                                    ? 'Mã OTP đã gửi về hòm thư $p! Vui lòng kiểm tra Gmail.'
                                                    : 'Đã gửi tin nhắn SMS OTP đến số $p! Vui lòng kiểm tra tin nhắn.')
                                                : 'Mã OTP xác thực gửi tới $p: $demoCode'),
                                            backgroundColor: const Color(0xFF133E26),
                                            duration: const Duration(seconds: 5),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setDState(() {
                                        sendingOtp = false;
                                        dErr = e.toString().replaceFirst('Exception: ', '');
                                      });
                                    }
                                  },
                            child: sendingOtp
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(
                                    countdown > 0 ? '${countdown}s' : 'Gửi mã OTP',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: countdown > 0 ? AppColors.muted : AppColors.accent,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.trim().length < 5 ? 'Vui lòng nhập Email hoặc SĐT hợp lệ' : null,
                    ),
                    const SizedBox(height: 12),
                    // Mã OTP
                    TextFormField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Mã xác thực OTP (6 số) *',
                        hintText: 'Nhập mã 6 chữ số từ SMS',
                        prefixIcon: Icon(Icons.password_rounded),
                        counterText: '',
                      ),
                      validator: (v) => v == null || v.trim().length < 6 ? 'Nhập mã OTP 6 số' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: pCtrl,
                      obscureText: hideP,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu *',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(hideP ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setDState(() => hideP = !hideP),
                        ),
                      ),
                      validator: (v) => v == null || v.length < 3 ? 'Mật khẩu tối thiểu 3 ký tự' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: p2Ctrl,
                      obscureText: hideP,
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu *',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      validator: (v) => v != pCtrl.text ? 'Mật khẩu xác nhận không khớp' : null,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.air),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nhân viên sau khi đăng ký sẽ dùng chức năng Quét mã QR dán trên tủ trạm để kết nối.',
                              style: TextStyle(fontSize: 11.5, color: AppColors.text2, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () {
                      countdownTimer?.cancel();
                      Navigator.pop(ctx);
                    },
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDState(() {
                        saving = true;
                        dErr = null;
                      });
                      try {
                        await Session.I.register(
                          _server.text,
                          uCtrl.text.trim(),
                          pCtrl.text,
                          fCtrl.text.trim(),
                          phone: !phoneCtrl.text.trim().contains('@') ? phoneCtrl.text.trim() : null,
                          email: phoneCtrl.text.trim().contains('@') ? phoneCtrl.text.trim() : null,
                          otp: otpCtrl.text.trim(),
                        );
                        countdownTimer?.cancel();
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                      } catch (e) {
                        setDState(() {
                          saving = false;
                          dErr = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Xác nhận đăng ký'),
            ),
          ],
        ),
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final formKey = GlobalKey<FormState>();
    final phoneCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool hideP = true;
    bool saving = false;
    bool sendingOtp = false;
    int countdown = 0;
    Timer? countdownTimer;
    String? dErr;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: AppColors.surface,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warn.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: AppColors.warn, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Quên mật khẩu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('Đặt lại mật khẩu qua mã xác thực OTP', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dErr != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(dErr!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))),
                          ],
                        ),
                      ),
                    TextFormField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email, SĐT hoặc Tên đăng nhập *',
                        hintText: 'VD: nhanvien@gmail.com hoặc admin',
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextButton(
                            onPressed: (sendingOtp || countdown > 0)
                                ? null
                                : () async {
                                    final p = phoneCtrl.text.trim();
                                    if (p.isEmpty) {
                                      setDState(() => dErr = 'Vui lòng nhập Email, SĐT hoặc Tên đăng nhập');
                                      return;
                                    }
                                    setDState(() {
                                      sendingOtp = true;
                                      dErr = null;
                                    });
                                    try {
                                      final res = await Session.I.sendOtp(
                                        server: _server.text,
                                        target: p,
                                        purpose: 'forgot_password',
                                      );
                                      final isRealSent = res['email_sent'] == true || res['sms_sent'] == true;
                                      final demoCode = res['otp_demo']?.toString();
                                      if (!isRealSent && demoCode != null) {
                                        otpCtrl.text = demoCode;
                                      }
                                      setDState(() {
                                        sendingOtp = false;
                                        countdown = 60;
                                      });
                                      countdownTimer?.cancel();
                                      countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                                        if (countdown > 1) {
                                          setDState(() => countdown--);
                                        } else {
                                          t.cancel();
                                          setDState(() => countdown = 0);
                                        }
                                      });
                                      if (ctx.mounted) {
                                        final isEmail = p.contains('@');
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text(isRealSent
                                                ? (isEmail
                                                    ? 'Mã OTP đặt lại mật khẩu đã gửi về hòm thư $p!'
                                                    : 'Đã gửi tin nhắn SMS OTP đến số $p! Vui lòng kiểm tra tin nhắn.')
                                                : 'Mã OTP đặt lại mật khẩu: $demoCode'),
                                            backgroundColor: const Color(0xFF133E26),
                                            duration: const Duration(seconds: 5),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setDState(() {
                                        sendingOtp = false;
                                        dErr = e.toString().replaceFirst('Exception: ', '');
                                      });
                                    }
                                  },
                            child: sendingOtp
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(
                                    countdown > 0 ? '${countdown}s' : 'Gửi mã OTP',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: countdown > 0 ? AppColors.muted : AppColors.accent,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập Email, SĐT hoặc Username' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Mã xác thực OTP (6 số) *',
                        hintText: 'Nhập mã OTP đã nhận',
                        prefixIcon: Icon(Icons.password_rounded),
                        counterText: '',
                      ),
                      validator: (v) => v == null || v.trim().length < 6 ? 'Nhập mã OTP 6 số' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPassCtrl,
                      obscureText: hideP,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu mới *',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(hideP ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setDState(() => hideP = !hideP),
                        ),
                      ),
                      validator: (v) => v == null || v.length < 3 ? 'Mật khẩu tối thiểu 3 ký tự' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPassCtrl,
                      obscureText: hideP,
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu mới *',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      validator: (v) => v != newPassCtrl.text ? 'Mật khẩu xác nhận không khớp' : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () {
                      countdownTimer?.cancel();
                      Navigator.pop(ctx);
                    },
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDState(() {
                        saving = true;
                        dErr = null;
                      });
                      try {
                        final res = await Session.I.forgotPassword(
                          server: _server.text,
                          target: phoneCtrl.text.trim(),
                          otp: otpCtrl.text.trim(),
                          newPassword: newPassCtrl.text.trim(),
                        );
                        countdownTimer?.cancel();
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _pass.clear();
                        if (res['username'] != null) {
                          _user.text = res['username'].toString();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res['message']?.toString() ?? 'Đặt lại mật khẩu thành công!'),
                              backgroundColor: const Color(0xFF133E26),
                            ),
                          );
                        }
                      } catch (e) {
                        setDState(() {
                          saving = false;
                          dErr = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Cập nhật mật khẩu'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = _form();
    return Scaffold(
      body: wide
          ? Row(children: [
              const Expanded(flex: 6, child: _Hero()),
              Expanded(flex: 5, child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: form))),
            ])
          : Stack(children: [
              const Positioned.fill(child: _Glow()),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    child: Column(children: [
                      const BrandLogo(size: 64),
                      const SizedBox(height: 14),
                      const Text('ThermoGuard', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                      const SizedBox(height: 4),
                      const Text('Giám sát nhiệt độ · độ ẩm IoT', style: TextStyle(color: AppColors.text2)),
                      const SizedBox(height: 28),
                      form,
                    ]),
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _form() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Đăng nhập', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 4),
          const Text('Truy cập bảng điều khiển các trạm giám sát', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 24),
          TextField(
            controller: _user,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pass,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.air,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              ),
              child: const Text('Quên mật khẩu?', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 6),
          // Cau hinh dia chi server
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _showServer = !_showServer),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Row(children: [
                const Icon(Icons.dns_outlined, size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Máy chủ: ${Session.normalizeUrl(_server.text)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                ),
                Icon(_showServer ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.muted),
              ]),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _showServer ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Địa chỉ máy chủ', hintText: 'http://192.168.1.17:8080', prefixIcon: Icon(Icons.link_rounded)),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final u in [
                    'https://mondidong.onrender.com',
                    'http://localhost:5000',
                    'http://192.168.110.61:5000',
                  ])
                    ActionChip(
                      label: Text(u.replaceFirst('https://', '').replaceFirst('http://', ''), style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => _server.text = u),
                    ),
                ]),
                const SizedBox(height: 6),
                const Text(
                  'Máy ảo Android dùng 10.0.2.2 · Điện thoại thật dùng IP LAN của máy chạy server (xem bằng ipconfig).',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ]),
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_err!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
              ]),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : const Text('Đăng nhập'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _showRegisterDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Chưa có tài khoản? Đăng ký nhân viên'),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderStrong)),
            child: const Text.rich(
              TextSpan(style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5), children: [
                TextSpan(text: 'Tài khoản mẫu: '),
                TextSpan(text: 'admin / admin123', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                TextSpan(text: ' (toàn quyền) · '),
                TextSpan(text: 'viewer / viewer123', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                TextSpan(text: ' (chỉ xem)'),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(-0.8, -1.0), radius: 1.2, colors: [Color(0x3338BDF8), Color(0x00080C11)]),
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(1.0, 1.0), radius: 1.0, colors: [Color(0x2EFB923C), Color(0x00080C11)]),
        ),
      ),
    );
  }
}

/// Panel gioi thieu ben trai (man hinh rong: web / tablet)
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    Widget scenario(IconData i, Color c, String t, String s) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bg.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, color: c, size: 22),
              const SizedBox(height: 10),
              Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(s, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ]),
          ),
        );
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))),
      child: Stack(children: [
        const Positioned.fill(child: _Glow()),
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              BrandLogo(size: 42),
              SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ThermoGuard', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                Text('IOT MONITORING', style: TextStyle(color: AppColors.muted, fontSize: 11, letterSpacing: 1.2)),
              ]),
            ]),
            const Spacer(),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [AppColors.air, AppColors.probe]).createShader(r),
              child: const Text('Giám sát nhiệt độ\n& độ ẩm thời gian thực',
                  style: TextStyle(fontSize: 42, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1.2, color: Colors.white)),
            ),
            const SizedBox(height: 14),
            const SizedBox(
              width: 520,
              child: Text(
                'Raspberry Pi Pico 2 W + SHT30 + DS18B20. Tính điểm sương, tự động bật quạt/bơm/còi qua relay, hiển thị trên OLED và lưu lịch sử vào MySQL.',
                style: TextStyle(color: AppColors.text2, fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 620,
              child: Row(children: [
                scenario(Icons.dns_rounded, AppColors.air, 'Phòng Lab / Tủ điện', 'Quá nhiệt, đọng sương'),
                const SizedBox(width: 12),
                scenario(Icons.water_drop_rounded, AppColors.dew, 'Môi trường Nước & Đất', 'DS18B20 + Độ ẩm đất + pH'),
                const SizedBox(width: 12),
                scenario(Icons.sensors_rounded, AppColors.hum, 'Không khí & Quang trở', 'SHT30 + Quang trở LDR'),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
