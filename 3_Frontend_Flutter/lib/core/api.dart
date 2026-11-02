import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
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

  String baseUrl = defaultServer();
  String? token;
  AppUser? user;
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
      r = await fn().timeout(const Duration(seconds: 15));
    } catch (e) {
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
    final j = await get('devices.php');
    return (j['devices'] as List).map((e) => Station.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Station> station(int id) async {
    final j = await get('devices.php?id=$id');
    return Station.fromJson(j['device'] as Map<String, dynamic>);
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
}


