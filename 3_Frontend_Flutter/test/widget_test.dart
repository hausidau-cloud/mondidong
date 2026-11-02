import 'package:flutter_test/flutter_test.dart';

import 'package:laptrinhdidong/core/format.dart';
import 'package:laptrinhdidong/models/models.dart';

void main() {
  test('Doc du lieu tram tu JSON cua API', () {
    final s = Station.fromJson({
      'id': 1,
      'device_code': 'PICO-01',
      'name': 'Tủ điện',
      'profile': 'cabinet',
      'relay_label': 'Quạt',
      'relay_mode': 'AUTO',
      'relay_state': 1,
      'status': 'WARNING',
      'online': true,
      'air_temp': 30.5,
      'air_hum': '60.0',
      'dew_point': 22.1,
      'probe_temp': null,
      'air_temp_max': 45,
      'air_hum_max': 70,
      'probe_temp_min': 5,
      'probe_temp_max': 60,
      'dew_margin': 3,
      'hysteresis': 2,
      'offline_after': 60,
      'open_alerts': 2,
      'send_interval': 5,
      'spark': [1, null, 2.5],
    });
    expect(s.relayOn, true);
    expect(s.airHum, 60.0);
    expect(s.probeTemp, isNull);
    expect(s.dewGap, closeTo(8.4, 0.001));
    expect(s.spark.length, 3);
  });

  test('Dinh dang so', () {
    expect(fmt(null), '--');
    expect(fmt(3.14159), '3.1');
    expect(StatusStyle.of('DANGER').label, 'Nguy hiểm');
  });
}
