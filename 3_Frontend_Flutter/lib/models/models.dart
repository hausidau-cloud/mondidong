// Cac model du lieu tra ve tu API PHP/MySQL

double? toDbl(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int toInt(dynamic v, [int def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

bool toBool(dynamic v) => toInt(v) == 1 || v == true;

DateTime? toTime(dynamic v) {
  if (v == null) return null;
  var s = v.toString().trim().replaceFirst(' ', 'T');
  if (!s.endsWith('Z') && !s.contains('+') && (!s.contains('-') || (s.length > 10 && !s.substring(10).contains('-')))) {
    s += 'Z';
  }
  final dt = DateTime.tryParse(s);
  return dt?.toLocal();
}

class AppUser {
  final int id;
  final String username;
  final String fullName;
  final String role;
  AppUser({required this.id, required this.username, required this.fullName, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: toInt(j['id']),
        username: (j['username'] ?? '').toString(),
        fullName: (j['full_name'] ?? '').toString(),
        role: (j['role'] ?? 'viewer').toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'full_name': fullName, 'role': role};
}

class RelayLog {
  final String action; // ON | OFF
  final String source; // AUTO | MANUAL
  final String reason;
  final String? by;
  final DateTime? at;
  RelayLog({required this.action, required this.source, required this.reason, this.by, this.at});

  factory RelayLog.fromJson(Map<String, dynamic> j) => RelayLog(
        action: (j['action'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
        reason: (j['reason'] ?? '').toString(),
        by: j['full_name']?.toString(),
        at: toTime(j['created_at']),
      );
}

class SecurityEvent {
  final String kind, detail;
  final String? ip;
  final DateTime? at;
  SecurityEvent({required this.kind, required this.detail, this.ip, this.at});

  factory SecurityEvent.fromJson(Map<String, dynamic> j) => SecurityEvent(
        kind: (j['kind'] ?? '').toString(),
        detail: (j['detail'] ?? '').toString(),
        ip: j['ip']?.toString(),
        at: toTime(j['created_at']),
      );

  /// Mo ta tieng Viet cho tung loai su kien bao mat
  String get label {
    switch (kind) {
      case 'BAD_SIGNATURE':
        return 'Chữ ký sai (gói giả mạo)';
      case 'BAD_KEY':
        return 'Sai API key';
      case 'REPLAY':
        return 'Gói bị phát lại';
      case 'CLOCK_SKEW':
        return 'Đồng hồ thiết bị lệch';
      case 'IP_LOCK':
        return 'Gửi từ IP lạ';
      case 'IMPLAUSIBLE':
        return 'Số đo vô lý (bị chặn)';
      default:
        return kind;
    }
  }
}

class Stats24h {
  final double? pMin, pMax, pAvg, aMin, aMax, hAvg;
  final int n, relayOn;
  Stats24h({this.pMin, this.pMax, this.pAvg, this.aMin, this.aMax, this.hAvg, this.n = 0, this.relayOn = 0});

  factory Stats24h.fromJson(Map<String, dynamic> j) => Stats24h(
        pMin: toDbl(j['p_min']),
        pMax: toDbl(j['p_max']),
        pAvg: toDbl(j['p_avg']),
        aMin: toDbl(j['a_min']),
        aMax: toDbl(j['a_max']),
        hAvg: toDbl(j['h_avg']),
        n: toInt(j['n']),
        relayOn: toInt(j['relay_on']),
      );

  double? get relayPercent => n == 0 ? null : relayOn * 100 / n;
}

class Station {
  final int id;
  final String code, name, profile;
  final String? location, description;
  final String relayLabel, relayMode, status;
  final bool relayOn, online;
  final double? airTemp, airHum, dewPoint, probeTemp;
  final int lightPct, lightRaw;
  final double airTempMax, airHumMax, probeMin, probeMax, dewMargin, hysteresis, offsetAir, offsetProbe;
  final int offlineAfter, openAlerts, sendInterval;
  final int? rssi;
  final DateTime? lastSeen;
  final String? firmware, oledMsg, apiKey;
  // Bao mat (chi admin thay): khoa theo IP + phien ban key. api_key KHONG con nam o day,
  // phai bam "Xem key" va nhap lai mat khau.
  final String? ipLock, allowedIp, lastIp, ingestAuth;
  final int keyVersion;
  final List<SecurityEvent> securityEvents;
  final List<double?> spark;
  final List<RelayLog> relayLogs;
  final Stats24h? stats;

  Station({
    required this.id,
    required this.code,
    required this.name,
    required this.profile,
    this.location,
    this.description,
    required this.relayLabel,
    required this.relayMode,
    required this.status,
    required this.relayOn,
    required this.online,
    this.airTemp,
    this.airHum,
    this.dewPoint,
    this.probeTemp,
    this.lightPct = 0,
    this.lightRaw = 0,
    required this.airTempMax,
    required this.airHumMax,
    required this.probeMin,
    required this.probeMax,
    required this.dewMargin,
    required this.hysteresis,
    required this.offsetAir,
    required this.offsetProbe,
    required this.offlineAfter,
    required this.openAlerts,
    required this.sendInterval,
    this.rssi,
    this.lastSeen,
    this.firmware,
    this.oledMsg,
    this.apiKey,
    this.ipLock,
    this.allowedIp,
    this.lastIp,
    this.ingestAuth,
    this.keyVersion = 1,
    this.securityEvents = const [],
    this.spark = const [],
    this.relayLogs = const [],
    this.stats,
  });

  factory Station.fromJson(Map<String, dynamic> j) => Station(
        id: toInt(j['id']),
        code: (j['device_code'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        profile: (j['profile'] ?? 'cabinet').toString(),
        location: j['location']?.toString(),
        description: j['description']?.toString(),
        relayLabel: (j['relay_label'] ?? 'Relay').toString(),
        relayMode: (j['relay_mode'] ?? 'AUTO').toString(),
        status: (j['status'] ?? 'OFFLINE').toString(),
        relayOn: toBool(j['relay_state']),
        online: j['online'] == true || (j['status'] != null && j['status'] != 'OFFLINE'),
        airTemp: toDbl(j['air_temp']),
        airHum: toDbl(j['air_hum']),
        dewPoint: toDbl(j['dew_point']),
        probeTemp: toDbl(j['probe_temp']),
        lightPct: toInt(j['light_pct']),
        lightRaw: toInt(j['light_raw']),
        airTempMax: toDbl(j['air_temp_max']) ?? 40,
        airHumMax: toDbl(j['air_hum_max']) ?? 75,
        probeMin: toDbl(j['probe_temp_min']) ?? 0,
        probeMax: toDbl(j['probe_temp_max']) ?? 60,
        dewMargin: toDbl(j['dew_margin']) ?? 0,
        hysteresis: toDbl(j['hysteresis']) ?? 1,
        offsetAir: toDbl(j['offset_air']) ?? 0,
        offsetProbe: toDbl(j['offset_probe']) ?? 0,
        offlineAfter: toInt(j['offline_after'], 60),
        openAlerts: toInt(j['open_alerts']),
        sendInterval: toInt(j['send_interval'], 5),
        rssi: j['rssi'] == null ? null : toInt(j['rssi']),
        lastSeen: toTime(j['last_seen']),
        firmware: j['firmware']?.toString(),
        oledMsg: j['oled_msg']?.toString(),
        apiKey: j['api_key']?.toString(),
        ipLock: j['ip_lock']?.toString(),
        allowedIp: j['allowed_ip']?.toString(),
        lastIp: j['last_ip']?.toString(),
        ingestAuth: j['ingest_auth']?.toString(),
        keyVersion: toInt(j['key_version'], 1),
        securityEvents: ((j['security_events'] as List?) ?? const []).map((e) => SecurityEvent.fromJson(e as Map<String, dynamic>)).toList(),
        spark: ((j['spark'] as List?) ?? const []).map(toDbl).toList(),
        relayLogs: ((j['relay_logs'] as List?) ?? const []).map((e) => RelayLog.fromJson(e as Map<String, dynamic>)).toList(),
        stats: j['stats24h'] is Map<String, dynamic> ? Stats24h.fromJson(j['stats24h'] as Map<String, dynamic>) : null,
      );

  /// Bien an toan suong: T - Td
  double? get dewGap => (airTemp != null && dewPoint != null) ? airTemp! - dewPoint! : null;
}

class Series {
  final List<DateTime> t;
  final List<double?> airTemp, airHum, dewPoint, probeTemp, light;
  final List<bool> relay;
  final int bucket;
  Series({
    required this.t,
    required this.airTemp,
    required this.airHum,
    required this.dewPoint,
    required this.probeTemp,
    this.light = const [],
    required this.relay,
    required this.bucket,
  });

  factory Series.fromJson(Map<String, dynamic> j, int bucket) {
    List<double?> l(String k) => ((j[k] as List?) ?? const []).map(toDbl).toList();
    return Series(
      t: ((j['t'] as List?) ?? const []).map((e) => toTime(e) ?? DateTime.now()).toList(),
      airTemp: l('air_temp'),
      airHum: l('air_hum'),
      dewPoint: l('dew_point'),
      probeTemp: l('probe_temp'),
      light: l('light').isNotEmpty ? l('light') : l('light_pct'),
      relay: ((j['relay'] as List?) ?? const []).map(toBool).toList(),
      bucket: bucket,
    );
  }

  static Series empty() => Series(t: [], airTemp: [], airHum: [], dewPoint: [], probeTemp: [], light: [], relay: [], bucket: 0);
}

class Reading {
  final int id;
  final DateTime? at;
  final double? airTemp, airHum, dewPoint, probeTemp;
  final bool relay;
  final String status;
  final int? rssi;
  Reading({required this.id, this.at, this.airTemp, this.airHum, this.dewPoint, this.probeTemp, required this.relay, required this.status, this.rssi});

  factory Reading.fromJson(Map<String, dynamic> j) => Reading(
        id: toInt(j['id']),
        at: toTime(j['recorded_at']),
        airTemp: toDbl(j['air_temp']),
        airHum: toDbl(j['air_hum']),
        dewPoint: toDbl(j['dew_point']),
        probeTemp: toDbl(j['probe_temp']),
        relay: toBool(j['relay_state']),
        status: (j['status'] ?? 'OK').toString(),
        rssi: j['rssi'] == null ? null : toInt(j['rssi']),
      );
}

class Paged<T> {
  final List<T> rows;
  final int total, page, pages;
  Paged(this.rows, this.total, this.page, this.pages);
}

class AlertItem {
  final int id, deviceId;
  final String level, type, message, deviceName, deviceCode, profile;
  final bool resolved;
  final DateTime? createdAt, resolvedAt, ackAt;
  final String? ackBy;
  AlertItem({
    required this.id,
    required this.deviceId,
    required this.level,
    required this.type,
    required this.message,
    required this.deviceName,
    required this.deviceCode,
    required this.profile,
    required this.resolved,
    this.createdAt,
    this.resolvedAt,
    this.ackAt,
    this.ackBy,
  });

  bool get acknowledged => ackAt != null;

  factory AlertItem.fromJson(Map<String, dynamic> j) => AlertItem(
        id: toInt(j['id']),
        deviceId: toInt(j['device_id']),
        level: (j['level'] ?? 'WARNING').toString(),
        type: (j['type'] ?? '').toString(),
        message: (j['message'] ?? '').toString(),
        deviceName: (j['device_name'] ?? '').toString(),
        deviceCode: (j['device_code'] ?? '').toString(),
        profile: (j['profile'] ?? 'cabinet').toString(),
        resolved: toBool(j['is_resolved']),
        createdAt: toTime(j['created_at']),
        resolvedAt: toTime(j['resolved_at']),
        ackAt: toTime(j['acknowledged_at']),
        ackBy: j['ack_name']?.toString(),
      );
}

class AlertPage {
  final List<AlertItem> rows;
  final int total, page, pages;
  final int openTotal, openDanger, unack, last24h;
  AlertPage({
    required this.rows,
    required this.total,
    required this.page,
    required this.pages,
    required this.openTotal,
    required this.openDanger,
    required this.unack,
    required this.last24h,
  });

  factory AlertPage.fromJson(Map<String, dynamic> j) {
    final c = (j['counts'] as Map?) ?? const {};
    return AlertPage(
      rows: ((j['rows'] as List?) ?? const []).map((e) => AlertItem.fromJson(e as Map<String, dynamic>)).toList(),
      total: toInt(j['total']),
      page: toInt(j['page'], 1),
      pages: toInt(j['pages'], 1),
      openTotal: toInt(c['open_total']),
      openDanger: toInt(c['open_danger']),
      unack: toInt(c['unack']),
      last24h: toInt(c['last24h']),
    );
  }
}
