# =====================================================================
#  THERMOGUARD - FIRMWARE ESP32 NODEMCU (MicroPython)
#  KET NOI: CAM BIEN DHT11 + DIEU KHIEN LED (GPIO 23)
#  DONG BO BACKEND C# (.NET CLOUD) & APP FLUTTER
# =====================================================================
import time
import machine
import network
import math
import gc
import json
import hashlib
import binascii

try:
    import dht
except ImportError:
    dht = None

try:
    import requests
except ImportError:
    import urequests as requests

import config

FW_VERSION = "esp32-dht11-ipgps-2.0"
INGEST_URL = config.SERVER_URL.rstrip("/") + "/api/ingest"
TIME_URL   = config.SERVER_URL.rstrip("/") + "/api/time"

print("==================================================")
print(">> KHOI DONG FIRMWARE ESP32 + DINH VI IP (CACH 2)")
print(">> Thiet bi:", config.DEVICE_CODE)
print(">> Phien ban:", FW_VERSION)
print("==================================================")

# ==============================================================
# 1. KHOI TAO PHAN CUNG (DHT11 & LED)
# ==============================================================
# LED bao trang thai / canh bao tren GPIO 23
led_pin = machine.Pin(config.PIN_LED, machine.Pin.OUT)
led_pin.value(0)

# Khoi tao cam bien DHT11 tren GPIO 4
dht_sensor = None
if dht:
    try:
        dht_sensor = dht.DHT11(machine.Pin(config.PIN_DHT))
        print(">> Khoi tao cam bien DHT11 tren chan GPIO", config.PIN_DHT)
    except Exception as e:
        print(">> Loi khoi tao DHT11:", e)
else:
    print(">> Canh bao: Khong tim thay thu vien dht")

# ==============================================================
# 2. QUAN LY TRANG THAI HE THONG
# ==============================================================
state = {
    "temp": None,
    "hum": None,
    "dew": None,
    "led": False,
    "status": "BOOT",
    "mode": "AUTO",
    "reason": "",
    "interval": config.SEND_INTERVAL_DEFAULT,
    "connected_ssid": "",
    "lat": None,
    "lon": None,
    "address": "",
}

time_offset_ms = 0
_key_bytes = config.API_KEY.encode()

def now_ms():
    return time.ticks_ms() + time_offset_ms

def set_led(on, reason=""):
    state["led"] = bool(on)
    if on and reason:
        state["reason"] = reason
    elif not on:
        state["reason"] = ""
    led_pin.value(1 if on else 0)

def dew_point(t, rh):
    if t is None or rh is None or rh <= 0:
        return None
    try:
        b, c = 17.62, 243.12
        g = math.log(rh / 100.0) + (b * t) / (c + t)
        return round((c * g) / (b - g), 1)
    except Exception:
        return None

# ==============================================================
# 3. CHU KY BAO MAT HMAC-SHA256 & DONG BO GIO
# ==============================================================
def hmac_sha256(key, msg):
    block = 64
    if len(key) > block:
        key = hashlib.sha256(key).digest()
    key = key + b"\x00" * (block - len(key))
    o_pad = bytes((b ^ 0x5c) for b in key)
    i_pad = bytes((b ^ 0x36) for b in key)
    inner = hashlib.sha256(i_pad + msg).digest()
    return binascii.hexlify(hashlib.sha256(o_pad + inner).digest()).decode()

def sync_time():
    global time_offset_ms
    if not wlan.isconnected():
        return False
    r = None
    try:
        r = requests.get(TIME_URL, timeout=4)
        if r.status_code == 200:
            srv = int(r.json().get("now", 0))
            if srv > 0:
                time_offset_ms = srv - time.ticks_ms()
                print(">> Dong bo gio thanh cong! Offset:", time_offset_ms, "ms")
                return True
    except Exception as e:
        print(">> Loi dong bo gio:", e)
    finally:
        if r is not None:
            try: r.close()
            except Exception: pass
    return False

# ==============================================================
# 4. KET NOI WI-FI THONG MINH CHO ESP32
# ==============================================================
wlan = network.WLAN(network.STA_IF)

def connect_wifi():
    global wlan
    try:
        if wlan.isconnected():
            return True
    except Exception:
        pass

    # Reset sach se radio Wi-Fi cua ESP32 de tranh loi "wifi:sta is connecting"
    try:
        wlan.active(False)
        time.sleep_ms(150)
    except Exception:
        pass

    try:
        wlan.active(True)
        time.sleep_ms(300)
    except Exception:
        pass

    try:
        wlan.disconnect()
        time.sleep_ms(200)
    except Exception:
        pass

    visible_ssids = set()
    try:
        scan_results = wlan.scan()
        for item in scan_results:
            try:
                name = item[0].decode('utf-8', 'ignore').strip()
                if name:
                    visible_ssids.add(name)
            except Exception:
                pass
    except Exception as e:
        print(">> Scan loi, fallback thu lan luot:", e)

    candidates = []
    for ssid, pwd in config.WIFI_LIST:
        if not visible_ssids or ssid in visible_ssids:
            candidates.append((ssid, pwd))

    if not candidates:
        candidates = config.WIFI_LIST

    for ssid, password in candidates:
        print(">> ESP32 thu ket noi: '{}' ...".format(ssid))
        try:
            try:
                wlan.disconnect()
                time.sleep_ms(150)
            except Exception:
                pass
            wlan.connect(ssid, password)
        except OSError as e:
            # Xu ly triet de loi Wifi Internal State Error tren chip ESP32
            print(">> Radio ESP32 can reset lai...")
            try:
                wlan.active(False)
                time.sleep_ms(300)
                wlan.active(True)
                time.sleep_ms(500)
                wlan.connect(ssid, password)
            except Exception as ex:
                print(">> Bo qua mang do loi radio:", ex)
                continue
        except Exception as ex:
            print(">> Loi ket noi:", ex)
            continue

        wait = 12
        while wait > 0:
            if wlan.isconnected():
                break
            # Nhay LED nhe de bao hieu dang ket noi
            led_pin.value(1)
            time.sleep_ms(150)
            led_pin.value(0)
            time.sleep(0.85)
            wait -= 1

        if wlan.isconnected():
            state["connected_ssid"] = ssid
            print(">> KET NOI WI-FI THANH CONG: '{}'!".format(ssid))
            print(">> Dia chi IP ESP32:", wlan.ifconfig()[0])
            return True

    print(">> Khong ket noi duoc Wi-Fi nao trong danh sach.")
    # KICH HOAT WEB CAPTIVE PORTAL DE CAU HINH WI-FI NHANH QUA DIEN THOAI
    start_web_config_portal(timeout_sec=40)
    return False

# ==============================================================
# 4.1 WEB CAPTIVE PORTAL (SOFTAP PROVISIONING)
# ==============================================================
def save_wifi_to_config(new_ssid, new_pass):
    try:
        content = ""
        with open("config.py", "r") as f:
            content = f.read()
        target = "WIFI_LIST = [\n"
        if target in content:
            entry = '    ("{}", "{}"),\n'.format(new_ssid, new_pass)
            new_content = content.replace(target, target + entry, 1)
            with open("config.py", "w") as f:
                f.write(new_content)
            print(">> [CONFIG] Da luu Wi-Fi '{}' vao config.py!".format(new_ssid))
    except Exception as e:
        print(">> [CONFIG] Loi ghi file:", e)

def start_web_config_portal(timeout_sec=40):
    """Bat SoftAP va Web Server mini de nguoi dung cau hinh Wi-Fi moi qua dien thoai ma khong can cam cap"""
    try:
        import usocket as socket
    except ImportError:
        import socket

    print("==================================================")
    print("🌐 [SOFTAP] KHOI TAO DIEM PHAT WI-FI CAU HINH NHANH")
    print(">> Ten Wi-Fi (SSID): ThermoGuard-ESP32-Setup")
    print(">> Vao trinh duyet tren dien thoai mo: http://192.168.4.1")
    print(">> Thoi gian cho ket noi: {} giay".format(timeout_sec))
    print("==================================================")

    ap = network.WLAN(network.AP_IF)
    ap.active(True)
    ap.config(essid="ThermoGuard-ESP32-Setup", authmode=network.AUTH_OPEN)

    scanned_ssids = []
    try:
        scan_res = wlan.scan()
        for item in scan_res:
            name = item[0].decode('utf-8', 'ignore').strip()
            if name and name not in scanned_ssids:
                scanned_ssids.append(name)
    except Exception:
        pass

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('', 80))
    s.listen(1)
    s.settimeout(2.0)

    start_time = time.time()
    saved = False

    while (time.time() - start_time) < timeout_sec:
        led_pin.value(1)
        time.sleep_ms(80)
        led_pin.value(0)

        try:
            conn, addr = s.accept()
            req = conn.recv(1024).decode('utf-8', 'ignore')

            if "POST /save" in req:
                body = req.split("\r\n\r\n")[-1] if "\r\n\r\n" in req else ""
                params = {}
                for pair in body.split("&"):
                    if "=" in pair:
                        parts = pair.split("=", 1)
                        params[parts[0]] = parts[1].replace("+", " ").replace("%20", " ")

                new_ssid = params.get("ssid", "").strip()
                new_pass = params.get("pass", "").strip()

                if new_ssid:
                    print(">> [SOFTAP] Nhan Wi-Fi moi tu Web Portal:", new_ssid)
                    save_wifi_to_config(new_ssid, new_pass)
                    resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n" \
                           "<html><body style='font-family:sans-serif;text-align:center;padding:40px;background:#0f172a;color:#f8fafc;'>" \
                           "<h2 style='color:#10b981;'>&#10004; Da luu Wi-Fi thanh cong!</h2>" \
                           "<p>ESP32 dang khoi dong lai de ket noi vao <b>" + new_ssid + "</b>...</p>" \
                           "</body></html>"
                    conn.send(resp)
                    conn.close()
                    saved = True
                    break
            else:
                options_html = "".join(["<option value='{}'>{}</option>".format(ssid, ssid) for ssid in scanned_ssids[:15]])
                html = """HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n
<!DOCTYPE html>
<html>
<head>
    <meta name='viewport' content='width=device-width, initial-scale=1'>
    <title>ThermoGuard Wi-Fi Setup</title>
    <style>
        body { font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px; margin: 0; }
        .card { max-width: 400px; margin: 20px auto; background: #1e293b; padding: 24px; border-radius: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
        h2 { color: #38bdf8; margin-top: 0; font-size: 20px; }
        p { font-size: 13px; color: #94a3b8; line-height: 1.5; }
        label { display: block; margin: 12px 0 6px; font-size: 13px; font-weight: 600; }
        select, input { width: 100%; box-sizing: border-box; padding: 12px; border-radius: 8px; border: 1px solid #334155; background: #0f172a; color: #fff; font-size: 14px; margin-bottom: 12px; }
        button { width: 100%; padding: 12px; background: #0284c7; border: none; border-radius: 8px; color: #fff; font-size: 15px; font-weight: 700; cursor: pointer; margin-top: 10px; }
    </style>
</head>
<body>
    <div class='card'>
        <h2>&#128246; ThermoGuard Wi-Fi Setup</h2>
        <p>Ket noi Wi-Fi cho ESP32 ma khong can cam cap may tinh.</p>
        <form method='POST' action='/save'>
            <label>Chon Wi-Fi gan nhat:</label>
            <select name='ssid' id='ssid_select'>""" + options_html + """</select>
            <label>Mat khau Wi-Fi:</label>
            <input type='password' name='pass' placeholder='Nhap mat khau...'>
            <button type='submit'>Luu &amp; Ket Noi</button>
        </form>
    </div>
</body>
</html>"""
                conn.send(html)
                conn.close()
        except OSError:
            pass
        except Exception:
            pass

    s.close()
    ap.active(False)
    if saved:
        time.sleep(1)
        machine.reset()

# ==============================================================
# 5. DINH VI VI TRI TU DONG THEO TUNG WI-FI & IP FALLBACK
# ==============================================================
def resolve_auto_location():
    """Tu dong dinh vi: Neu la Wi-Fi da biet thi lay toa do chuan 100%, neu la mang la thi fallback qua IP"""
    if not wlan.isconnected():
        return False

    ssid = state.get("connected_ssid", "")
    wifi_locs = getattr(config, "WIFI_LOCATIONS", {})

    # 1. Kiem tra xem mang Wi-Fi vua ket noi co trong danh sach dinh vi chinh xac khong
    if ssid and ssid in wifi_locs:
        target = wifi_locs[ssid]
        state["lat"] = target.get("lat")
        state["lon"] = target.get("lon")
        state["address"] = target.get("address", ssid)
        print("==================================================")
        print("📍 [GPS-AUTO] TU DONG NHAN DIEN THEO WI-FI '{}'".format(ssid))
        print(">> Toa do (Lat, Lon) : {}, {}".format(state["lat"], state["lon"]))
        print(">> Dia chi chinh xac : {}".format(state["address"]))
        print(">> Xem tren Google Maps: https://www.google.com/maps?q={},{}".format(state["lat"], state["lon"]))
        print("==================================================")
        return True

    # 2. Neu la mang Wi-Fi moi hoan toan -> Tu dong dinh vi qua IP (Fallback)
    print(">> [GPS-AUTO] Wi-Fi '{}' la mang moi, dang dinh vi tu dong qua IP...".format(ssid or "Moi"))
    r = None
    try:
        r = requests.get("http://ip-api.com/json", timeout=6)
        if r.status_code == 200:
            res = r.json()
            if res.get("status") == "success":
                lat = res.get("lat")
                lon = res.get("lon")
                city = res.get("city", "")
                region = res.get("regionName", "")
                country = res.get("country", "")
                ip_addr = res.get("query", "")

                state["lat"] = lat
                state["lon"] = lon
                loc_text = "{}, {}".format(city, region) if city else region
                state["address"] = "{}, {}".format(loc_text, country) if loc_text else country

                print("==================================================")
                print("📍 [GPS-IP] DINH VI QUA IP CHO MANG LA THANH CONG!")
                print(">> Dia chi IP Public :", ip_addr)
                print(">> Khu vuc           :", state["address"])
                print(">> Toa do (Lat, Lon) : {}, {}".format(lat, lon))
                print(">> Xem tren Google Maps: https://www.google.com/maps?q={},{}".format(lat, lon))
                print("==================================================")
                return True
    except Exception as e:
        print(">> [GPS-IP] Loi dinh vi IP:", e)
    finally:
        if r is not None:
            try: r.close()
            except Exception: pass
    return False

# ==============================================================
# 6. DOC CAM BIEN DHT11
# ==============================================================
def read_dht():
    if not dht_sensor:
        return None, None
    try:
        dht_sensor.measure()
        t = dht_sensor.temperature()
        h = dht_sensor.humidity()
        if t is not None and h is not None and h > 0:
            return round(float(t), 1), round(float(h), 1)
    except Exception as e:
        pass
    return None, None

# ==============================================================
# 6. DIEU KHIEN DUC PHONG (FAIL-SAFE)
# ==============================================================
def local_control():
    # Neu nhiet do vuot nguong -> tu dong bat den canh bao (giong code Arduino cu)
    if state["temp"] is not None and state["temp"] >= config.TEMP_THRESHOLD:
        set_led(True, "QUA NHIET (>= {} C)".format(config.TEMP_THRESHOLD))
    elif state["hum"] is not None and state["hum"] >= config.HUM_THRESHOLD:
        set_led(True, "QUA AM (>= {} %)".format(config.HUM_THRESHOLD))
    else:
        set_led(False)

# ==============================================================
# 7. GUI DU LIEU LEN SERVER CLOUD & DONG BO VOI APP FLUTTER
# ==============================================================
def send_to_backend():
    if not wlan.isconnected():
        return False

    payload_obj = {
        "device_code": config.DEVICE_CODE,
        "air_temp": state["temp"],
        "air_hum": state["hum"],
        "probe_temp": None,  # ESP32 NodeMCU chi co DHT11, khong co dau do DS18B20
        "pico_temp": None,
        "dew_point": state["dew"],
        "light_raw": 0,
        "light_pct": 0,
        "relay_state": 1 if state["led"] else 0,
        "rssi": -55,
        "fw": FW_VERSION,
        "lat": state["lat"],
        "lon": state["lon"],
        "location": "{} ({:.4f}, {:.4f})".format(state["address"], state["lat"], state["lon"]) if (state["lat"] is not None and state["lon"] is not None) else state["address"],
    }
    payload_str = json.dumps(payload_obj)
    ts = now_ms()
    sig = hmac_sha256(_key_bytes, "{}|{}|{}".format(config.DEVICE_CODE, ts, payload_str).encode())

    body = {
        "device_code": config.DEVICE_CODE,
        "ts": ts,
        "payload": payload_str,
        "sig": sig,
    }

    r = None
    try:
        r = requests.post(
            INGEST_URL,
            json=body,
            headers={"Content-Type": "application/json"},
            timeout=5
        )

        if r.status_code == 200:
            resp = r.json()
            if resp.get("ok"):
                # Nhan lenh dieu khien LED tu App
                server_mode = resp.get("mode", "AUTO")
                server_relay = resp.get("relay")
                state["mode"] = server_mode
                state["status"] = resp.get("status", "OK")
                state["interval"] = max(2, int(resp.get("interval", 2)))

                if server_mode == "ON":
                    set_led(True, "APP ON")
                elif server_mode == "OFF":
                    set_led(False)
                elif server_mode == "AUTO":
                    if server_relay is not None:
                        set_led(server_relay == 1, resp.get("reason", "AUTO"))
                    else:
                        local_control()

                print(">> [CLOUD] Gui thanh cong | Temp: {} C | Hum: {} % | LED: {}".format(
                    state["temp"], state["hum"], "BAT" if state["led"] else "TAT"))
                return True
        else:
            print(">> [CLOUD] HTTP Error:", r.status_code)

    except Exception as e:
        print(">> [CLOUD] Loi truyen:", e)
    finally:
        if r is not None:
            try: r.close()
            except Exception: pass
    return False

# ==============================================================
# 8. VONG LAP CHINH
# ==============================================================
def main():
    # 1. Ket noi vao Wi-Fi
    connect_wifi()
    sync_time()

    # 2. Tu dong dinh vi ngay khi ket noi mang
    if wlan.isconnected():
        resolve_auto_location()

    last_send = 0
    fail_count = 0
    last_gps_update = time.ticks_ms()

    while True:
        try:
            # 1. Kiem tra Wi-Fi neu bi rot mang hoac chuyen sang Wi-Fi khac
            if not wlan.isconnected():
                print(">> Mat Wi-Fi, dang ket noi lai...")
                connect_wifi()
                if wlan.isconnected():
                    resolve_auto_location()

            # 2. Dinh ky cap nhat lai vi tri moi 30 phut
            now = time.ticks_ms()
            if state["lat"] is None or time.ticks_diff(now, last_gps_update) >= 1800000:
                last_gps_update = now
                if wlan.isconnected():
                    resolve_auto_location()

            # 3. Doc cam bien DHT11
            t, h = read_dht()
            state["temp"] = t
            state["hum"] = h
            state["dew"] = dew_point(t, h)

            # 4. Kiem tra chu ky va gui len Cloud
            interval_ms = state["interval"] * 1000

            if time.ticks_diff(now, last_send) >= interval_ms:
                last_send = now
                ok = send_to_backend()
                if ok:
                    fail_count = 0
                else:
                    fail_count += 1
                    # Neu mat mang Cloud > 3 lan thi chay che do fail-safe cuc bo
                    if fail_count >= 3:
                        local_control()

            gc.collect()
            time.sleep_ms(200)

        except Exception as e:
            print(">> Loi vong lap:", e)
            time.sleep(1)

if __name__ == "__main__":
    main()
