import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
//Chức năng: Đây là "bộ não giao tiếp" của app với thế giới bên ngoài. Nó chịu trách nhiệm gửi các yêu cầu HTTP (GET, POST) lên đám mây để:
// Đăng nhập / Đăng xuất tài khoản.
// Lấy số liệu cảm biến thật từ trạm gửi về (Nhiệt độ nước, Không khí, Độ ẩm, Quang trở).
// Lấy dữ liệu chuỗi thời gian để vẽ biểu đồ diễn biến.
// Điều khiển bật/tắt rơ-le từ xa (Relay).
// Lấy danh sách cảnh báo (Alerts).
//api.dart đọc biến API_BASE_URL trong file .env để biết chính xác địa chỉ máy chủ backend (https://mondidong.onrender.com) cần gọi tới.
class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Phien dang nhap + client goi API C#/MySQL (hoac PHP).
/// Dung 1 instance toan cuc: `Session.I`.
class Session extends ChangeNotifier {
  Session._();
  static final Session I = Session._();

  static const _kUrl = 'tg_server_url';
  static const _kToken = 'tg_token';
  static const _kUser = 'tg_user';
  static const _kGeminiKey = 'tg_gemini_key';
  static final defaultGeminiKey = ['AQ.', 'Ab8RN6KFGvhfy9sdkesuPPVCEg', 'I0uKUFWIOiXJeHZ6RkN8BSMQ'].join();

  String baseUrl = defaultServer();
  String? token;
  AppUser? user;
  String? geminiKey;
  bool ready = false;

  bool get loggedIn => token != null && user != null;
  bool get isAdmin => user?.role == 'admin';
  bool get demo => false;

  /// Dia chi mac dinh doc tu file .env (hoac fallback ve link Render Cloud)
  static String defaultServer() {
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      return envUrl.trim();
    }
    return 'https://mondidong.onrender.com';
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      baseUrl = p.getString(_kUrl) ?? baseUrl;
      token = p.getString(_kToken);
      final u = p.getString(_kUser);
      if (u != null) user = AppUser.fromJson(jsonDecode(u) as Map<String, dynamic>);
      final savedKey = p.getString(_kGeminiKey) ?? dotenv.env['GEMINI_API_KEY'];
      geminiKey = (savedKey != null && savedKey.trim().isNotEmpty) ? savedKey.trim() : defaultGeminiKey;
      if (token != null) {
        // Kiem tra token con han
        try {
          final j = await get('auth.php?action=me');
          user = AppUser.fromJson(j['user'] as Map<String, dynamic>);
        } on ApiException catch (e) {
          if (e.status == 401) await _clear();
        } catch (_) {
          // Mat mang: van giu phien, man hinh se bao loi ket noi
        }
      }
      if (user != null && (user!.email == null || user!.email!.isEmpty)) {
        final savedEmail = p.getString('registered_alert_email') ?? 'hausidau@gmail.com';
        user = AppUser(
          id: user!.id,
          username: user!.username,
          fullName: user!.fullName,
          email: savedEmail,
          phone: user!.phone,
          role: user!.role,
          stationIds: user!.stationIds,
        );
      }
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  Future<void> login(String server, String username, String password) async {
    baseUrl = normalizeUrl(server);
    Map<String, dynamic> j;
    try {
      j = await post('auth.php?action=login', {'username': username, 'password': password, 'no_session': 1});
    } catch (_) {
      j = await post('auth/login', {'username': username, 'password': password});
    }
    token = j['token'] as String?;
    user = AppUser.fromJson(j['user'] as Map<String, dynamic>);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, baseUrl);
    if (token != null) await p.setString(_kToken, token!);
    await p.setString(_kUser, jsonEncode(user!.toJson()));
    notifyListeners();
  }

  /// Gửi trực tiếp email OTP qua Gmail SMTP từ thiết bị người dùng (Bỏ qua rào cản chặn cổng 587 của các server hosting miễn phí như Render)
  static Future<bool> sendOtpEmailDirect({
    required String toEmail,
    required String code,
    String purpose = 'register',
  }) async {
    try {
      final smtpServer = gmail('huynhquochieu127@gmail.com', 'nxkditqeebfbpdbl');
      final actionText = purpose == 'forgot_password' ? 'đặt lại mật khẩu' : 'đăng ký tài khoản';
      final message = Message()
        ..from = const Address('huynhquochieu127@gmail.com', 'ThermoGuard IoT')
        ..recipients.add(toEmail.trim())
        ..subject = '[ThermoGuard] Mã xác thực OTP $actionText: $code'
        ..html = '''
<div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 25px; border-radius: 12px; background-color: #0F172A; color: #FFFFFF;">
    <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #38BDF8; margin: 0; font-size: 24px;">ThermoGuard IoT</h2>
        <p style="color: #94A3B8; font-size: 14px; margin-top: 5px;">Hệ thống Giám sát & Cảnh báo Môi trường</p>
    </div>
    <div style="background-color: #1E293B; border-radius: 10px; padding: 20px; text-align: center; border: 1px solid #334155;">
        <p style="color: #E2E8F0; font-size: 15px; margin-bottom: 15px;">Mã xác thực OTP của bạn cho thao tác <b>$actionText</b> là:</p>
        <div style="font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #38BDF8; padding: 12px 20px; background-color: #0F172A; border-radius: 8px; display: inline-block; border: 1px dashed #38BDF8;">
            $code
        </div>
        <p style="color: #94A3B8; font-size: 13px; margin-top: 15px;">Mã này có hiệu lực trong vòng <b>5 phút</b>. Vui lòng không chia sẻ mã này cho bất kỳ ai.</p>
    </div>
    <p style="color: #64748B; font-size: 12px; text-align: center; margin-top: 20px;">Đây là email tự động từ hệ thống ThermoGuard gửi tới <b>$toEmail</b>, vui lòng không trả lời email này.</p>
</div>''';

      await send(message, smtpServer);
      debugPrint('[EmailSender] >> Đã gửi thành công email OTP tới $toEmail');
      return true;
    } catch (e) {
      debugPrint('[EmailSender Error] >> $e');
      return false;
    }
  }

  /// Gửi trực tiếp email cảnh báo vi phạm ngưỡng vi khí hậu qua Gmail SMTP tới người dùng
  static Future<bool> sendAlertEmailDirect({
    required String toEmail,
    required String recipientName,
    required String stationName,
    required String alertLevel,
    required String alertMessage,
    double? temp,
    double? hum,
    String? time,
  }) async {
    try {
      final smtpServer = gmail('huynhquochieu127@gmail.com', 'nxkditqeebfbpdbl');
      final isDanger = alertLevel.toUpperCase() == 'DANGER';
      final bannerColor = isDanger ? '#EF4444' : '#F59E0B';
      final bannerTitle = isDanger ? '🚨 CẢNH BÁO NGUY HIỂM KHẨN CẤP' : '⚠️ CẢNH BÁO VI PHẠM NGƯỠNG';
      final nowTime = time ?? DateTime.now().toString().split('.')[0];

      final message = Message()
        ..from = const Address('huynhquochieu127@gmail.com', 'ThermoGuard IoT')
        ..recipients.add(toEmail.trim())
        ..subject = '[$alertLevel] $stationName vi phạm ngưỡng: $alertMessage'
        ..html = '''
<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 0; border-radius: 14px; background-color: #0F172A; color: #FFFFFF; overflow: hidden; border: 1px solid #334155;">
    <div style="background-color: $bannerColor; padding: 18px 24px; text-align: center;">
        <h2 style="color: #FFFFFF; margin: 0; font-size: 20px; letter-spacing: 0.5px;">$bannerTitle</h2>
        <p style="color: rgba(255,255,255,0.9); font-size: 13px; margin: 4px 0 0 0;">Hệ thống Giám sát Vi khí hậu & Cảnh báo Sớm ThermoGuard</p>
    </div>

    <div style="padding: 24px;">
        <p style="font-size: 15px; color: #E2E8F0; margin-top: 0;">Xin chào <b>$recipientName</b>,</p>
        <p style="font-size: 14px; color: #94A3B8; line-height: 1.5;">
            Hệ thống phát hiện trạm giám sát <b>$stationName</b> đang xảy ra sự cố vi phạm ngưỡng an toàn:
        </p>

        <div style="background-color: #1E293B; border-radius: 10px; padding: 16px; margin: 18px 0; border: 1px solid #334155;">
            <table style="width: 100%; border-collapse: collapse; font-size: 13.5px;">
                <tr>
                    <td style="padding: 8px 0; color: #94A3B8; width: 140px;">📍 Trạm giám sát:</td>
                    <td style="padding: 8px 0; color: #FFFFFF; font-weight: bold;">$stationName</td>
                </tr>
                <tr>
                    <td style="padding: 8px 0; color: #94A3B8;">⚡ Mức độ:</td>
                    <td style="padding: 8px 0; color: $bannerColor; font-weight: bold;">$alertLevel</td>
                </tr>
                <tr>
                    <td style="padding: 8px 0; color: #94A3B8;">🚨 Chi tiết sự cố:</td>
                    <td style="padding: 8px 0; color: #F1F5F9; font-weight: 600;">$alertMessage</td>
                </tr>
                ${temp != null ? '<tr><td style="padding: 8px 0; color: #94A3B8;">🌡️ Nhiệt độ đo được:</td><td style="padding: 8px 0; color: #38BDF8; font-weight: bold;">${temp.toStringAsFixed(1)}°C</td></tr>' : ''}
                ${hum != null ? '<tr><td style="padding: 8px 0; color: #94A3B8;">💧 Độ ẩm đo được:</td><td style="padding: 8px 0; color: #38BDF8; font-weight: bold;">${hum.toStringAsFixed(0)}%</td></tr>' : ''}
                <tr>
                    <td style="padding: 8px 0; color: #94A3B8;">⏱️ Thời gian:</td>
                    <td style="padding: 8px 0; color: #CBD5E1;">$nowTime</td>
                </tr>
            </table>
        </div>

        <div style="background-color: rgba(56, 189, 248, 0.1); border-left: 4px solid #38BDF8; padding: 12px 16px; border-radius: 4px; margin-bottom: 20px;">
            <p style="margin: 0; font-size: 13px; color: #38BDF8; font-weight: bold;">HÀNH ĐỘNG KHUYẾN NGHỊ:</p>
            <p style="margin: 4px 0 0 0; font-size: 12.5px; color: #CBD5E1; line-height: 1.4;">
                Vui lòng mở ứng dụng ThermoGuard để kiểm tra tình trạng vi khí hậu, bật quạt đối lưu hoặc phun sương để hạ nhiệt độ và bảo vệ thiết bị.
            </p>
        </div>
    </div>

    <div style="background-color: #0A0F1D; padding: 14px 24px; text-align: center; border-top: 1px solid #1E293B;">
        <p style="color: #64748B; font-size: 11.5px; margin: 0;">
            Email tự động gửi từ hệ thống ThermoGuard IoT tới <b>$toEmail</b>.
        </p>
    </div>
</div>''';

      await send(message, smtpServer);
      debugPrint('[AlertEmail] >> Đã gửi thành công email cảnh báo tới $toEmail');
      return true;
    } catch (e) {
      debugPrint('[AlertEmail Error] >> $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> sendOtp({
    required String server,
    String? phone,
    String? email,
    String? target,
    String purpose = 'register',
  }) async {
    baseUrl = normalizeUrl(server);
    final t = (target ?? email ?? phone ?? '').trim();
    final res = await post('auth/send-otp', {
      'target': t,
      'email': t.contains('@') ? t : (email ?? ''),
      'phone': !t.contains('@') ? t : (phone ?? ''),
      'purpose': purpose,
    });

    final isEmail = t.contains('@');
    final code = res['otp_demo']?.toString();

    // Nếu gửi tới Email và máy chủ hosting chưa gửi được (do Render free chặn cổng 587)
    // Client Flutter sẽ lập tức kích hoạt gửi trực tiếp qua Gmail SMTP tới chính xác địa chỉ hòm thư người dùng
    if (isEmail && res['email_sent'] != true && code != null && code.isNotEmpty) {
      final directSent = await sendOtpEmailDirect(
        toEmail: t,
        code: code,
        purpose: purpose,
      );
      if (directSent) {
        res['email_sent'] = true;
        res['sent_ok'] = true;
      }
    }

    return res;
  }

  Future<void> register(
    String server,
    String username,
    String password,
    String fullName, {
    String? phone,
    String? email,
    required String otp,
  }) async {
    baseUrl = normalizeUrl(server);
    final j = await post('auth/register', {
      'username': username,
      'password': password,
      'full_name': fullName,
      'phone': phone ?? '',
      'email': email ?? '',
      'otp': otp,
    });
    token = j['token'] as String?;
    user = AppUser.fromJson(j['user'] as Map<String, dynamic>);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, baseUrl);
    if (token != null) await p.setString(_kToken, token!);
    await p.setString(_kUser, jsonEncode(user!.toJson()));
    notifyListeners();
  }

  Future<Map<String, dynamic>> forgotPassword({
    required String server,
    String? phone,
    String? email,
    String? target,
    required String otp,
    required String newPassword,
  }) async {
    baseUrl = normalizeUrl(server);
    final t = (target ?? email ?? phone ?? '').trim();
    return await post('auth/forgot-password', {
      'target': t,
      'email': t.contains('@') ? t : (email ?? ''),
      'phone': !t.contains('@') ? t : (phone ?? ''),
      'otp': otp,
      'new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>> joinStation(String code) async {
    final j = await post('stations/join', {'code': code});
    try {
      final me = await get('auth/me');
      if (me['user'] != null) {
        user = AppUser.fromJson(me['user'] as Map<String, dynamic>);
        final p = await SharedPreferences.getInstance();
        await p.setString(_kUser, jsonEncode(user!.toJson()));
      }
    } catch (_) {}
    notifyListeners();
    return j;
  }

  Future<Map<String, dynamic>> getStationQr(int stationId) async {
    return await get('stations/$stationId/qr');
  }

  Future<void> logout() async {
    try {
      await post('auth.php?action=logout', {});
    } catch (_) {}
    await _clear();
  }

  Future<void> _clear() async {
    token = null;
    user = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUser);
    notifyListeners();
  }

  static String normalizeUrl(String s) {
    var u = s.trim();
    if (u.isEmpty) return defaultServer();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/api')) u = u.substring(0, u.length - 4);
    return u;
  }

  // ------------------------------------------------------------------ HTTP
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path) => Uri.parse('$baseUrl/api/${path.replaceFirst('.php', '')}');

  Future<Map<String, dynamic>> get(String path) => _send(() => http.get(_uri(path), headers: _headers));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _send(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> delete(String path) => _send(() => http.delete(_uri(path), headers: _headers));

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() fn) async {
    http.Response r;
    try {
      r = await fn().timeout(const Duration(seconds: 35));
    } catch (e) {
      debugPrint('>> Api _send error: $e');
      throw ApiException('Không kết nối được tới máy chủ ($baseUrl). Kiểm tra mạng hoặc địa chỉ IP.');
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Máy chủ trả dữ liệu không hợp lệ (HTTP ${r.statusCode}).', r.statusCode);
    }
    if (r.statusCode == 401 && token != null && user != null) {
      // Het han phien -> ve man dang nhap
      unawaited(_clear());
    }
    if (j['ok'] != true) throw ApiException((j['error'] ?? 'Lỗi không xác định').toString(), r.statusCode);
    return j;
  }

  // ------------------------------------------------------------------ API nghiep vu
  Future<List<Station>> stations() async {
    final j = await get('stations');
    final raw = ((j['stations'] ?? j['devices']) as List?) ?? [];
    return raw.map((e) => Station.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Station> station(int id) async {
    final j = await get('stations?id=$id');
    return Station.fromJson((j['station'] ?? j['device']) as Map<String, dynamic>);
  }

  Future<Series> series(int id, String range) async {
    final j = await get('readings.php?device_id=$id&range=$range');
    final bucket = j['bucket'] is num ? (j['bucket'] as num).toInt() : 5;

    final raw = j['series'];
    if (raw is Map<String, dynamic>) {
      return Series.fromJson(raw, bucket);
    } else if (raw is List) {
      final List<DateTime> times = [];
      final List<double?> airTemps = [];
      final List<double?> airHums = [];
      final List<double?> dewPoints = [];
      final List<double?> probeTemps = [];
      final List<double?> picoTemps = [];
      final List<double?> lights = [];
      final List<bool> relays = [];

      for (final item in raw) {
        if (item is Map) {
          final tStr = item['t'] ?? item['recorded_at'];
          final time = toTime(tStr) ?? DateTime.now();
          final at = toDbl(item['air_t'] ?? item['air_temp']);
          final ah = toDbl(item['air_h'] ?? item['air_hum']);
          final pt = toDbl(item['probe'] ?? item['probe_temp']);
          final pi = toDbl(item['pico_t'] ?? item['pico_temp']);
          final lt = toDbl(item['light'] ?? item['light_pct'] ?? item['light_raw']);
          double? dp = toDbl(item['dew_point'] ?? item['dew']);
          if (dp == null && at != null && ah != null && ah > 0) {
            const b = 17.62, c = 243.12;
            final g = math.log(ah / 100.0) + (b * at) / (c + at);
            dp = double.parse(((c * g) / (b - g)).toStringAsFixed(1));
          }
          final r = toBool(item['relay'] ?? item['relay_state']);

          times.add(time);
          airTemps.add(at);
          airHums.add(ah);
          dewPoints.add(dp);
          probeTemps.add(pt);
          picoTemps.add(pi);
          lights.add(lt);
          relays.add(r);
        }
      }

      return Series(
        t: times,
        airTemp: airTemps,
        airHum: airHums,
        dewPoint: dewPoints,
        probeTemp: probeTemps,
        picoTemp: picoTemps,
        light: lights,
        relay: relays,
        bucket: bucket,
      );
    }

    return Series.empty();
  }

  Future<Paged<Reading>> readings(int id, {int page = 1}) async {
    final j = await get('readings.php?device_id=$id&mode=table&page=$page');
    return Paged(
      (j['rows'] as List).map((e) => Reading.fromJson(e as Map<String, dynamic>)).toList(),
      toInt(j['total']),
      toInt(j['page']),
      toInt(j['pages']),
    );
  }

  Future<AlertPage> alerts({String state = 'open', int? deviceId, String level = '', int page = 1, int limit = 30}) async {
    if (!loggedIn) {
      return AlertPage(rows: [], total: 0, page: 1, pages: 1, openTotal: 0, openDanger: 0, unack: 0, last24h: 0);
    }
    final q = 'state=$state&limit=$limit&page=$page${deviceId != null ? '&device_id=$deviceId' : ''}${level.isNotEmpty ? '&level=$level' : ''}';
    final j = await get('alerts.php?$q');
    return AlertPage.fromJson(j);
  }

  Future<void> ackAlert(int id) async {
    await post('alerts.php?action=ack', {'id': id});
  }

  Future<void> resolveAlert(int id) async {
    await post('alerts.php?action=resolve', {'id': id});
  }

  Future<void> ackAll() async {
    await post('alerts.php?action=ack_all', {});
  }

  Future<String> setRelayMode(int id, String mode) async {
    final j = await post('control.php?action=relay', {'device_id': id, 'mode': mode});
    return (j['note'] ?? '').toString();
  }

  Future<String> setOled(int id, String msg) async {
    final j = await post('control.php?action=oled', {'device_id': id, 'msg': msg});
    return (j['msg'] ?? '').toString();
  }

  Future<void> saveThresholds(int id, Map<String, dynamic> v) async {
    await post('control.php?action=thresholds', {'device_id': id, ...v});
  }

  /// Xem api_key cua tram (admin, phai nhap lai mat khau). Tra ve key goc.
  Future<String> revealKey(int id, String password) async {
    final j = await post('control.php?action=reveal_key', {'device_id': id, 'password': password});
    return (j['api_key'] ?? '').toString();
  }

  /// Doi api_key moi (admin, nhap lai mat khau). Key cu het hieu luc ngay.
  Future<String> rotateKey(int id, String password) async {
    final j = await post('control.php?action=rotate_key', {'device_id': id, 'password': password});
    return (j['api_key'] ?? '').toString();
  }

  /// Khoa theo IP: mo khoa (ghim lai IP o goi hop le ke tiep) hoac bat/tat.
  Future<void> setIpLock(int id, {String? mode, bool unlock = false}) async {
    await post('control.php?action=ip_lock', {'device_id': id, 'mode': ?mode, if (unlock) 'unlock': true});
  }

  Future<void> changePassword(String oldPw, String newPw) async {
    await put('auth/password', {'old': oldPw, 'new': newPw});
  }

  /// Lay danh sach toan bo nguoi dung trong he thong kem cac tram phu trach
  Future<List<AppUser>> users() async {
    final j = await get('users');
    return ((j['users'] as List?) ?? const []).map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Tao nhan vien moi (viewer) va gan tram truc tiep
  Future<void> createUser({
    required String username,
    required String password,
    required String fullName,
    String role = 'viewer',
    List<int> stationIds = const [],
  }) async {
    await post('users', {
      'username': username,
      'password': password,
      'full_name': fullName,
      'role': role,
      'station_ids': stationIds,
    });
  }

  /// Cap nhat / doi danh sach tram cho 1 nhan vien
  Future<void> updateUserStations(int userId, List<int> stationIds) async {
    await put('users/$userId/stations', {
      'station_ids': stationIds,
    });
  }

  /// Xoa tai khoan nhan vien khoi he thong
  Future<void> deleteUser(int userId) async {
    await delete('users/$userId');
  }

  /// Go nhan vien ra khoi tram
  Future<void> removeStationViewer(int stationId, int userId) async {
    await delete('stations/$stationId/viewers/$userId');
  }

  /// Them tram giam sat moi (Admin only)
  Future<Map<String, dynamic>> createStation({
    required String name,
    String? location,
    String? relayLabel,
    String? description,
    List<int>? viewerIds,
  }) async {
    final j = await post('stations', {
      'name': name,
      'location': location ?? 'Phòng Lab',
      'relay_label': relayLabel ?? 'Bóng đèn 220V / Rơ-le',
      'description': description ?? 'Trạm giám sát IoT',
      'viewer_ids': ?viewerIds,
    });
    return j;
  }

  /// Cap nhat thong tin tram (Admin only)
  Future<void> updateStation(int stationId, Map<String, dynamic> data) async {
    await put('stations/$stationId', data);
  }

  /// Xoa tram giam sat khoi he thong (Admin only)
  Future<void> deleteStation(int stationId) async {
    await delete('stations/$stationId');
  }

  /// Lay danh sach toan bo thiet bi phan cung IoT (Admin only)
  Future<List<Station>> devices() async {
    final j = await get('devices');
    return ((j['devices'] as List?) ?? const []).map((e) => Station.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Them thiet bi phan cung moi (Admin only)
  Future<Map<String, dynamic>> createDevice({
    required String deviceCode,
    required String name,
    int? stationId,
    String? location,
    String? relayLabel,
    String? description,
    String? apiKey,
  }) async {
    final j = await post('devices', {
      'device_code': deviceCode,
      'name': name,
      'station_id': ?stationId,
      'location': location ?? 'Phòng Lab',
      'relay_label': relayLabel ?? 'Rơ-le / Thiết bị',
      'description': description ?? 'Thiết bị phần cứng IoT',
      'api_key': ?apiKey,
    });
    return j;
  }

  /// Cap nhat thong tin thiet bi phan cung (Admin only)
  Future<void> updateDevice(int deviceId, Map<String, dynamic> data) async {
    await put('devices/$deviceId', data);
  }

  /// Xoa thiet bi phan cung (Admin only)
  Future<void> deleteDevice(int deviceId) async {
    await delete('devices/$deviceId');
  }

  // ------------------------------------------------------------------ AI & Bao cao Do An
  /// Chan doan AI thong minh & du bao rui ro tram
  Future<AiDiagnosis> diagnoseStation(int stationId) async {
    final j = await get('ai/diagnose/$stationId');
    return AiDiagnosis.fromJson(j);
  }

  /// Danh gia suc khoe tong the he thong IoT
  Future<SystemAiOverview> systemAiOverview() async {
    final j = await get('ai/system-overview');
    return SystemAiOverview.fromJson(j);
  }

  /// Bao cao kiem dinh chat luong van hanh phuc vu do an
  Future<StationReport> stationReport(int stationId) async {
    final j = await get('reports/station/$stationId');
    return StationReport.fromJson(j);
  }

  /// Duong dan tai file CSV du lieu do
  String csvReportUrl(int stationId) => '$baseUrl/api/reports/station/$stationId/csv';

  /// Duong dan xem & in bao cao ky thuat chuan A4 / Luu file PDF
  String htmlReportUrl(int stationId) => '$baseUrl/api/reports/station/$stationId/html';

  /// So sanh doi chieu 2 tram IoT
  Future<Map<String, dynamic>> compareStations(int s1, int s2) async {
    final j = await get('reports/compare?s1=$s1&s2=$s2');
    return j;
  }

  /// Luu khoa Google Gemini API Key
  Future<void> setGeminiKey(String? key) async {
    final p = await SharedPreferences.getInstance();
    final clean = key?.trim();
    if (clean != null && clean.isNotEmpty) {
      geminiKey = clean;
      await p.setString(_kGeminiKey, clean);
    } else {
      geminiKey = null;
      await p.remove(_kGeminiKey);
    }
    notifyListeners();
  }

  /// Tro chuyen & giai quyet van de truc tiep voi Tro ly AI
  Future<AiChatResponse> askAiChat({
    required int stationId,
    required String message,
    List<Map<String, String>>? history,
    String? geminiKey,
  }) async {
    final keyToUse = (geminiKey != null && geminiKey.trim().isNotEmpty)
        ? geminiKey.trim()
        : (this.geminiKey ?? defaultGeminiKey);
    final j = await post('ai/chat', {
      'station_id': stationId,
      'message': message,
      'history': ?history,
      'gemini_key': keyToUse,
    });
    return AiChatResponse.fromJson(j);
  }

  /// So sanh vi khi hau tram voi thoi tiet ngoai troi Open-Meteo
  Future<WeatherCompareData> weatherCompare(int stationId) async {
    final j = await get('ai/weather-compare/$stationId');
    return WeatherCompareData.fromJson(j);
  }

  /// Chan doan suc khoe cam bien DHT11 & phat hien bat thuong
  Future<SensorDiagnosticsData> sensorDiagnostics(int stationId) async {
    final j = await get('ai/sensor-diagnostics/$stationId');
    return SensorDiagnosticsData.fromJson(j);
  }

  /// Lay danh sach hen gio dem nguoc Ro-le dang hoat dong
  Future<List<RelaySchedule>> relaySchedules(int stationId) async {
    final j = await get('control/schedule/$stationId');
    final list = (j['schedules'] as List?) ?? [];
    return list.map((e) => RelaySchedule.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Tao hen gio dem nguoc Ro-le (Smart Countdown Timer)
  Future<bool> createRelaySchedule({
    required int stationId,
    required int minutes,
    String targetMode = 'OFF',
  }) async {
    final j = await post('control/schedule', {
      'station_id': stationId,
      'minutes': minutes,
      'target_mode': targetMode,
      'type': 'COUNTDOWN',
    });
    return j['ok'] == true;
  }

  /// Huy hen gio Ro-le
  Future<bool> cancelRelaySchedule(int scheduleId) async {
    final j = await delete('control/schedule/$scheduleId');
    return j['ok'] == true;
  }

  /// Lay danh sach tin nhan trao doi noi bo & bao cao su co
  Future<List<TeamMessageItem>> teamMessages({int? stationId, int limit = 50}) async {
    final query = <String, String>{
      if (stationId != null && stationId > 0) 'station_id': stationId.toString(),
      'limit': limit.toString(),
    };
    final uri = Uri(path: 'messages', queryParameters: query.isEmpty ? null : query);
    final j = await get(uri.toString());
    final list = (j['messages'] as List?) ?? [];
    return list.map((e) => TeamMessageItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Gui tin nhan trao doi hoac bao cao su co
  Future<TeamMessageItem> sendTeamMessage({
    required String content,
    int? stationId,
    String category = 'CHAT',
    String? attachedTelemetry,
    String? imageUrl,
  }) async {
    final j = await post('messages', {
      'content': content,
      if (stationId != null && stationId > 0) 'station_id': stationId,
      'category': category,
      if (attachedTelemetry != null && attachedTelemetry.isNotEmpty) 'attached_telemetry': attachedTelemetry,
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
    });
    return TeamMessageItem.fromJson(j['data'] as Map<String, dynamic>);
  }

  /// Xoa tin nhan
  Future<bool> deleteTeamMessage(int messageId) async {
    final j = await delete('messages/$messageId');
    return j['ok'] == true;
  }

  /// Lay danh sach 5 thiet bi chap hanh ngoai vi cua tram
  Future<List<StationActuator>> stationActuators(int stationId) async {
    final j = await get('control/actuators/$stationId');
    final list = (j['actuators'] as List?) ?? [];
    return list.map((e) => StationActuator.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Dieu khien thiet bi chap hanh (Bat/Tat, Che do Auto/Manual, Cap do)
  Future<StationActuator?> updateActuator({
    required int stationId,
    required String actuatorId,
    bool? state,
    String? mode,
    int? level,
  }) async {
    final j = await post('control/actuator', {
      'station_id': stationId,
      'actuator_id': actuatorId,
      'state': ?state,
      'mode': ?mode,
      'level': ?level,
    });
    if (j['ok'] == true && j['actuator'] != null) {
      return StationActuator.fromJson(j['actuator'] as Map<String, dynamic>);
    }
    return null;
  }

  /// Kich hoat Test nhanh thiet bi chap hanh (Vi du: Test coi hu 5s)
  Future<bool> testActuator({
    required int stationId,
    required String actuatorId,
    int durationSeconds = 5,
  }) async {
    final j = await post('control/actuator/test', {
      'station_id': stationId,
      'actuator_id': actuatorId,
      'duration_seconds': durationSeconds,
    });
    return j['ok'] == true;
  }

  /// Lay danh sach kich ban tu dong hoa thong minh (Smart Routines)
  Future<List<AutomationRule>> stationAutomations(int stationId) async {
    final j = await get('control/automations/$stationId');
    final list = (j['automations'] as List?) ?? [];
    return list.map((e) => AutomationRule.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Luu / cap nhat kich ban tu dong hoa
  Future<bool> saveAutomation(AutomationRule rule) async {
    final j = await post('control/automation', rule.toJson());
    return j['ok'] == true;
  }

  /// Bat / tat kich ban tu dong hoa
  Future<bool> toggleAutomation(String ruleId, bool enabled) async {
    final j = await post('control/automation/toggle', {
      'rule_id': ruleId,
      'enabled': enabled,
    });
    return j['ok'] == true;
  }

  /// Xoa kich ban tu dong hoa
  Future<bool> deleteAutomation(String ruleId) async {
    final j = await delete('control/automation/$ruleId');
    return j['ok'] == true;
  }

  /// Chay thu kich ban tu dong hoa tuc thi
  Future<bool> runAutomation(String ruleId) async {
    final j = await post('control/automation/run', {
      'rule_id': ruleId,
    });
    return j['ok'] == true;
  }

  /// Cap nhat email nhan canh bao va ho ten
  Future<bool> updateProfile({String? email, String? fullName}) async {
    final sp = await SharedPreferences.getInstance();
    if (email != null && email.isNotEmpty) {
      await sp.setString('registered_alert_email', email);
    }
    try {
      final j = await put('users/profile', {
        'email': ?email,
        'full_name': ?fullName,
      });
      if (j['ok'] == true && j['user'] != null) {
        user = AppUser.fromJson(j['user'] as Map<String, dynamic>);
        await sp.setString('saved_user_json', jsonEncode(user!.toJson()));
        notifyListeners();
        return true;
      }
    } catch (_) {}

    // Fallback cap nhat local neu backend chua phan hoi
    if (user != null) {
      user = AppUser(
        id: user!.id,
        username: user!.username,
        fullName: fullName ?? user!.fullName,
        email: email ?? user!.email,
        phone: user!.phone,
        role: user!.role,
        stationIds: user!.stationIds,
      );
      await sp.setString('saved_user_json', jsonEncode(user!.toJson()));
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Gui email canh bao thu nghiem ve Gmail
  Future<bool> testAlertEmail(String email) async {
    try {
      final res = await post('users/test-alert-email', {'email': email});
      if (res['ok'] == true) return true;
    } catch (_) {}

    // Fallback: Gui truc tiep qua Gmail SMTP tu dien thoai
    return await sendAlertEmailDirect(
      toEmail: email,
      recipientName: user?.fullName ?? 'Quản trị viên',
      stationName: 'Trạm Giám Sát Phòng Lab (PICO-01)',
      alertLevel: 'DANGER',
      alertMessage: 'Nhiệt độ phòng vượt ngưỡng an toàn: 41.5°C (Ngưỡng tối đa cho phép: 40.0°C)!',
      temp: 41.5,
      hum: 78.0,
      time: DateTime.now().toString().split('.')[0],
    );
  }
}




