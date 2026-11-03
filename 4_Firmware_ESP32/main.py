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

FW_VERSION = "esp32-dht11-1.0"
INGEST_URL = config.SERVER_URL.rstrip("/") + "/api/ingest"
TIME_URL   = config.SERVER_URL.rstrip("/") + "/api/time"

print("==================================================")
print(">> KHOI DONG FIRMWARE ESP32 (DONG BO APP FLUTTER)")
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

    for ssid, password in config.WIFI_LIST:
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
            print(">> KET NOI WI-FI THANH CONG!")
            print(">> Dia chi IP ESP32:", wlan.ifconfig()[0])
            return True

    print(">> Khong ket noi duoc Wi-Fi nao, chay Offline.")
    return False

# ==============================================================
# 5. DOC CAM BIEN DHT11
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
        "probe_temp": state["temp"],  # Dung nhiet do DHT11 lam probe neu khong co que inox
        "pico_temp": None,
        "dew_point": state["dew"],
        "light_raw": 0,
        "light_pct": 0,
        "relay_state": 1 if state["led"] else 0,
        "rssi": -55,
        "fw": FW_VERSION,
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
    connect_wifi()
    sync_time()

    last_send = 0
    fail_count = 0

    while True:
        try:
            # 1. Kiem tra Wi-Fi neu bi rot mang
            if not wlan.isconnected():
                print(">> Mat Wi-Fi, dang ket noi lai...")
                connect_wifi()

            # 2. Doc cam bien DHT11
            t, h = read_dht()
            state["temp"] = t
            state["hum"] = h
            state["dew"] = dew_point(t, h)

            # 3. Kiem tra chu ky va gui len Cloud
            now = time.ticks_ms()
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
