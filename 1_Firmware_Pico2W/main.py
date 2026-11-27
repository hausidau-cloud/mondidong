# =====================================================================
#  THERMOGUARD - FIRMWARE RASPBERRY PI PICO 2 W (MicroPython)
#  KET NOI TOAN DIEN: SHT30 + DS18B20 + LDR QUANG TRO + RELAY + OLED
#  DONG BO BACKEND C# (.NET WEB API) & APP FLUTTER
# =====================================================================
import time
import machine
import framebuf
import network
import onewire
import ds18x20
import math
import gc
import json
import hashlib
import binascii

try:
    import requests
except ImportError:
    import urequests as requests

import config

FW_VERSION = "pico2w-csharp-2.1"
INGEST_URL = config.SERVER_URL.rstrip("/") + "/api/ingest"
TIME_URL   = config.SERVER_URL.rstrip("/") + "/api/time"

print("==================================================")
print(">> KHOI DONG FIRMWARE PICO 2 W (KET NOI C# BACKEND)")
print(">> Phien ban:", FW_VERSION)
print("==================================================")

# ==============================================================
# 1. DRIVER MAN HINH OLED 128x64 (SSD1306/SSD1315)
# ==============================================================
class SSD1306(framebuf.FrameBuffer):
    def __init__(self, width, height, i2c, addr=0x3c):
        self.width = width
        self.height = height
        self.i2c = i2c
        self.addr = addr
        self.buffer = bytearray(self.height * self.width // 8)
        super().__init__(self.buffer, self.width, self.height, framebuf.MONO_VLSB)
        self.init_display()

    def write_cmd(self, cmd):
        try:
            self.i2c.writeto(self.addr, bytearray([0x80, cmd]))
        except Exception:
            pass

    def init_display(self):
        for cmd in (
            0xAE, 0xD5, 0x80, 0xA8, self.height - 1, 0xD3, 0x00,
            0x40, 0x8D, 0x14, 0x20, 0x00, 0xA1, 0xC8,
            0xDA, 0x12 if self.height == 64 else 0x02,
            0x81, 0xCF, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6, 0xAF
        ):
            self.write_cmd(cmd)
        self.fill(0)
        self.show()

    def show(self):
        for cmd in (0x21, 0, self.width - 1, 0x22, 0, (self.height // 8) - 1):
            try:
                self.i2c.writeto(self.addr, bytearray([0x80, cmd]))
            except Exception:
                pass
        for i in range(0, len(self.buffer), 64):
            try:
                self.i2c.writeto(self.addr, b'\x40' + self.buffer[i:i+64])
            except Exception:
                pass

# ==============================================================
# 2. KHOI TAO PHAN CUNG NGOAI VI (THEO CHAN THUC TE)
# ==============================================================
# LED Onboard
try:
    pico_led = machine.Pin("LED", machine.Pin.OUT)
except Exception:
    pico_led = machine.Pin(25, machine.Pin.OUT)

# OLED GP14 (SDA), GP15 (SCL): Dung Hardware I2C1 tan so 100kHz chuan de chong nhieu tren breadboard
try:
    i2c_oled = machine.I2C(1, scl=machine.Pin(config.PIN_OLED_SCL), sda=machine.Pin(config.PIN_OLED_SDA), freq=100000)
except Exception:
    i2c_oled = machine.SoftI2C(scl=machine.Pin(config.PIN_OLED_SCL), sda=machine.Pin(config.PIN_OLED_SDA), freq=100000)
try:
    oled = SSD1306(128, 64, i2c_oled, addr=config.OLED_ADDR)
except Exception as e:
    print(">> Loi OLED:", e)
    oled = None

# SHT30: Tu dong ho tro ca 2 chieu chan GP16/17 lan GP14/15 va GP11/12
i2c_sht = machine.SoftI2C(scl=machine.Pin(config.PIN_SHT_SCL), sda=machine.Pin(config.PIN_SHT_SDA), freq=100000)
try:
    i2c_sht_rev = machine.SoftI2C(scl=machine.Pin(16 if config.PIN_SHT_SCL == 17 else 17), sda=machine.Pin(17 if config.PIN_SHT_SDA == 16 else 16), freq=100000)
except Exception:
    i2c_sht_rev = None
try:
    i2c_sht_right = machine.SoftI2C(scl=machine.Pin(12), sda=machine.Pin(11), freq=100000) # Hang 16 (SCL), Hang 15 (SDA) ben phai
except Exception:
    i2c_sht_right = None

# DS18B20 GP22
ds_pin = machine.Pin(config.PIN_DS18B20)
ds_sensor = ds18x20.DS18X20(onewire.OneWire(ds_pin))
roms = []
try:
    roms = ds_sensor.scan()
    print(">> Tim thay DS18B20:", len(roms), "que do")
except Exception as e:
    print(">> Loi quet DS18B20:", e)

# Quang tro LDR GP26 (ADC0)
ldr = machine.ADC(machine.Pin(config.PIN_LDR_ADC))

# Relay GP13
relay_pin = machine.Pin(config.PIN_RELAY, machine.Pin.OUT)

# Module GPS U-blox NEO-6M (UART0: GP0-TX, GP1-RX, 9600 baud)
gps_uart = None
try:
    gps_tx_pin = getattr(config, "PIN_GPS_TX", 0)
    gps_rx_pin = getattr(config, "PIN_GPS_RX", 1)
    gps_baud = getattr(config, "GPS_BAUDRATE", 9600)
    gps_uart = machine.UART(0, baudrate=gps_baud, tx=machine.Pin(gps_tx_pin), rx=machine.Pin(gps_rx_pin), timeout=10)
    print(">> Khoi tao UART0 GPS thanh cong (GP0-TX, GP1-RX, 9600 baud)")
except Exception as e:
    print(">> Loi khoi tao UART GPS:", e)

# Cam bien nhiet do chip noi bo tren Raspberry Pi Pico 2 W (RP2040/RP2350 - ADC 4)
try:
    pico_temp_adc = machine.ADC(4)
except Exception:
    pico_temp_adc = None

def read_pico_temp():
    if not pico_temp_adc:
        return None
    try:
        raw = pico_temp_adc.read_u16()
        volt = raw * 3.3 / 65535.0
        # RP2350 (Pico 2 W) Vbe ≈ 0.822V tai 27°C; RP2040 (Pico 1) Vbe ≈ 0.706V
        vbe_ref = 0.822 if volt > 0.76 else 0.706
        temp = 27.0 - (volt - vbe_ref) / 0.001721
        if temp < 10.0 or temp > 80.0:
            temp = 28.5 + (volt - 0.82) * 15
        return round(temp, 1)
    except Exception:
        return None

# ==============================================================
# 3. QUAN LY TRANG THAI HE THONG
# ==============================================================
state = {
    "air_t": None,
    "air_h": None,
    "probe": None,
    "pico_t": None,
    "dew": None,
    "light_raw": 0,
    "light_pct": 0,
    "relay": False,
    "status": "BOOT",      # BOOT, OK, WARNING, DANGER, OFFLINE
    "mode": "AUTO",        # AUTO, ON, OFF
    "alert": "",
    "msg": "",
    "interval": config.SEND_INTERVAL_DEFAULT,
    "offline": True,
    "reason": "",
    "connected_ssid": "",
    "lat": None,
    "lon": None,
    "address": "",
    "gps_fixed": False,
    "gps_sats": 0,         # So ve tinh dang su dung de tinh toa do (GGA)
    "gps_sats_view": 0,    # Tong so ve tinh nhin thay tren bau troi (GSV)
    "gps_lat": None,
    "gps_lon": None,
    "gps_alt_m": None,     # Do cao so voi muc nuoc bien (m)
    "gps_speed_kmh": None, # Toc do di chuyen (km/h)
    "gps_src": "NONE",
    "gps_rx_bytes": 0,     # Tong byte UART0 da nhan (dung chan doan day noi)
    "gps_last_fix_ms": 0,
}

# Dong bo gio server
time_offset_ms = 0
_key_bytes = config.API_KEY.encode()

def now_ms():
    return time.ticks_ms() + time_offset_ms

def set_relay(on, reason=""):
    state["relay"] = bool(on)
    if on and reason:
        state["reason"] = reason
    elif not on:
        state["reason"] = ""
    level = 1 if on else 0 if config.RELAY_ACTIVE_HIGH else (0 if on else 1)
    relay_pin.value(level)
    pico_led.value(1 if on else 0)

set_relay(False)  # Khoi dau an toan tat relay

def dew_point(t, rh):
    if t is None or rh is None or rh <= 0:
        return None
    b, c = 17.62, 243.12
    g = math.log(rh / 100.0) + (b * t) / (c + t)
    return round((c * g) / (b - g), 1)

# ==============================================================
# 4. CHU KY BAO MAT HMAC-SHA256 & DONG BO GIO
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
                print(">> Dong bo gio server thanh cong! Offset:", time_offset_ms, "ms")
                return True
    except Exception as e:
        print(">> Loi dong bo gio:", e)
    finally:
        if r is not None:
            try: r.close()
            except Exception: pass
    return False

# ==============================================================
# 5. KET NOI WI-FI THONG MINH (MULTI-WIFI)
# ==============================================================
wlan = network.WLAN(network.STA_IF)
wifi_connected = False
wifi_ip = "No IP"
wifi_ssid = "None"

def oled_msg(title, l1="", l2="", l3=""):
    if not oled: return
    oled.fill(0)
    oled.rect(0, 0, 128, 64, 1)
    oled.fill_rect(1, 1, 126, 12, 1)
    oled.text(title, 8, 3, 0)
    if l1: oled.text(l1, 6, 20, 1)
    if l2: oled.text(l2, 6, 35, 1)
    if l3: oled.text(l3, 6, 48, 1)
    oled.show()

def connect_wifi_auto():
    global wifi_connected, wifi_ip, wifi_ssid
    wlan.active(True)
    try:
        wlan.config(pm=0xa11140)  # Tat che do tiet kiem pin -> song khoe
    except Exception:
        pass

    oled_msg("PICO 2 W IOT", "Ket noi Wi-Fi...", "Dang quet mang")

    for ssid, password in config.WIFI_LIST:
        print(">> Thu ket noi: '{}' ...".format(ssid))
        oled_msg("WI-FI CONNECT", ssid[:14], "Dang ket noi...")
        wlan.connect(ssid, password)
        wait = 10
        while wait > 0:
            if wlan.isconnected():
                break
            pico_led.toggle()
            time.sleep(1)
            wait -= 1

        if wlan.isconnected():
            wifi_ip = wlan.ifconfig()[0]
            wifi_ssid = ssid
            wifi_connected = True
            state["connected_ssid"] = ssid
            pico_led.value(1)
            print(">> KET NOI WI-FI THANH CONG! IP:", wifi_ip)
            oled_msg("WI-FI ONLINE!", ssid[:14], "IP:", wifi_ip)
            time.sleep(2)
            resolve_auto_location()
            return True

    pico_led.value(0)
    wifi_connected = False
    print(">> Khong ket noi duoc Wi-Fi, chay Offline.")
    oled_msg("WI-FI OFFLINE", "Chay cuc bo", "Offline Mode")
    time.sleep(1.5)
    return False

# ==============================================================
# 5.1 XU LY MODULE GPS NEO-6M & DINH VI DA PHUONG THUC
# ==============================================================
gps_buffer = b""
last_gps_diag_ms = 0

def parse_nmea_coord(coord_str, direction):
    try:
        dot = coord_str.find('.')
        if dot < 0: return None
        deg_len = dot - 2
        deg = float(coord_str[:deg_len])
        minutes = float(coord_str[deg_len:])
        val = deg + (minutes / 60.0)
        if direction in ['S', 'W']:
            val = -val
        return round(val, 5)
    except Exception:
        return None

def poll_gps():
    """Doc va phan tich toan dien ban tin NMEA tu module GPS NEO-6M (Khong chan, non-blocking):
       - Ho tro tat ca talker: $GP (GPS), $GN (Glonass/Da he), $GL, $BD (BeiDou), $GA (Galileo)
       - Ban tin RMC: Toa do, toc do km/h, trang thai Fix (A) / Void (V)
       - Ban tin GGA: So ve tinh dang su dung, do cao so voi muc nuoc bien (m)
       - Ban tin GSV: Tong so ve tinh dang nhin thay tren bau troi (cuc ky huu ich khi o trong nha)
       - Tu dong in nhat ky chan doan phan cung UART moi 15s giup kiem tra ngay day noi
    """
    global gps_buffer, last_gps_diag_ms
    if not gps_uart:
        return

    try:
        n_avail = gps_uart.any()
        if n_avail > 0:
            chunk = gps_uart.read(n_avail)
            if chunk:
                state["gps_rx_bytes"] = state.get("gps_rx_bytes", 0) + len(chunk)
                gps_buffer += chunk
                if len(gps_buffer) > 512:
                    gps_buffer = gps_buffer[-256:]

                while b"\n" in gps_buffer:
                    line, gps_buffer = gps_buffer.split(b"\n", 1)
                    line = line.strip()
                    if not line.startswith(b"$"):
                        continue
                    try:
                        line_str = line.decode('ascii', 'ignore')
                    except Exception:
                        continue

                    # 1. Ban tin RMC: $..RMC,time,status,lat,N/S,lon,E/W,speed_knots,course,date,...
                    if len(line_str) > 6 and line_str[3:6] == "RMC":
                        parts = line_str.split(",")
                        if len(parts) >= 8:
                            status = parts[2] # A = Valid (Fix), V = Void (No fix)
                            if status == 'A' and parts[3] and parts[5]:
                                lat = parse_nmea_coord(parts[3], parts[4])
                                lon = parse_nmea_coord(parts[5], parts[6])
                                if lat is not None and lon is not None:
                                    was_fixed = state.get("gps_fixed", False)
                                    state["gps_fixed"] = True
                                    state["gps_lat"] = lat
                                    state["gps_lon"] = lon
                                    state["lat"] = lat
                                    state["lon"] = lon
                                    state["gps_src"] = "SATELLITE"
                                    state["gps_last_fix_ms"] = time.ticks_ms()
                                    if not was_fixed:
                                        print("🛰️ [GPS-FIX] DA KHOA VE TINH THANH CONG! Lat={}, Lon={}".format(lat, lon))
                                try:
                                    if parts[7]:
                                        knots = float(parts[7])
                                        state["gps_speed_kmh"] = round(knots * 1.852, 1)
                                except Exception:
                                    pass
                            elif status == 'V':
                                # Neu tam thoi mat khoa, duy tri toa do cu neu vua fix duoi 60 giay
                                if time.ticks_diff(time.ticks_ms(), state.get("gps_last_fix_ms", 0)) > 60000:
                                    state["gps_fixed"] = False

                    # 2. Ban tin GGA: $..GGA,time,lat,N/S,lon,E/W,fix_quality,num_sats,hdop,alt,M,...
                    elif len(line_str) > 6 and line_str[3:6] == "GGA":
                        parts = line_str.split(",")
                        if len(parts) >= 10:
                            sats = parts[7]
                            if sats.isdigit():
                                state["gps_sats"] = int(sats)
                            fix_q = parts[6]
                            if fix_q in ['1', '2'] and parts[2] and parts[4]:
                                lat = parse_nmea_coord(parts[2], parts[3])
                                lon = parse_nmea_coord(parts[4], parts[5])
                                if lat is not None and lon is not None:
                                    state["gps_fixed"] = True
                                    state["gps_lat"] = lat
                                    state["gps_lon"] = lon
                                    state["lat"] = lat
                                    state["lon"] = lon
                                    state["gps_src"] = "SATELLITE"
                                    state["gps_last_fix_ms"] = time.ticks_ms()
                            try:
                                if parts[9]:
                                    state["gps_alt_m"] = round(float(parts[9]), 1)
                            except Exception:
                                pass

                    # 3. Ban tin GSV: $..GSV,total_msgs,msg_num,total_sats,... (So ve tinh tren bau troi)
                    elif len(line_str) > 6 and line_str[3:6] == "GSV":
                        parts = line_str.split(",")
                        if len(parts) >= 4:
                            tot_sats = parts[3]
                            if tot_sats.isdigit():
                                state["gps_sats_view"] = int(tot_sats)

        # 4. Tu dong in log chan doan UART moi 15 giay de kiem tra ngay phan cung
        now_ms = time.ticks_ms()
        if time.ticks_diff(now_ms, last_gps_diag_ms) > 15000:
            last_gps_diag_ms = now_ms
            rx_cnt = state.get("gps_rx_bytes", 0)
            if rx_cnt == 0:
                print("⚠️ [GPS-UART] CHUA NHAN BYTE NAO! Kiem tra day: NEO-6M TXD noi GP1 (Pin 2), RXD noi GP0 (Pin 1), VCC/GND da sang den?")
            else:
                s_use = state.get("gps_sats", 0)
                s_view = state.get("gps_sats_view", 0)
                fix_str = "FIX_OK" if state.get("gps_fixed") else ("CHO_FIX({} ve tinh)".format(s_view) if s_view > 0 else "QUET_TIN_HIEU")
                print("🛰️ [GPS-STATUS] UART0: {} bytes | Trang thai: {} | Sats: {} dung / {} nhin | Lat: {} Lon: {}".format(
                    rx_cnt, fix_str, s_use, s_view, state.get("gps_lat"), state.get("gps_lon")
                ))

    except Exception:
        pass

def resolve_auto_location():
    """Tu dong dinh vi:
       1. Neu GPS ve tinh da chot toa do (A/Fix) -> Dung toa do ve tinh thuc te 100%
       2. Neu chua co song ve tinh (trong phong kin) -> Dung bang Wi-Fi da biet (NHA TRO 102...)
       3. Neu la Wi-Fi moi -> Tu dong fallback qua IP Public
    """
    # 1. Uu tien 1: Toa do ve tinh tu phan cung GPS NEO-6M
    if state.get("gps_fixed") and state.get("gps_lat") is not None:
        state["lat"] = state["gps_lat"]
        state["lon"] = state["gps_lon"]
        state["gps_src"] = "SATELLITE"
        print("==================================================")
        print("🛰️ [GPS-SATELLITE] TOA DO VE TINH THUC TE TU NEO-6M:")
        print(">> Toa do (Lat, Lon) : {}, {}".format(state["lat"], state["lon"]))
        print(">> So ve tinh nhan   : {}".format(state.get("gps_sats", 0)))
        print(">> Xem tren Google Maps: https://www.google.com/maps?q={},{}".format(state["lat"], state["lon"]))
        print("==================================================")
        return True

    if not wlan.isconnected():
        return False

    ssid = state.get("connected_ssid", "")
    wifi_locs = getattr(config, "WIFI_LOCATIONS", {})

    # 2. Uu tien 2: Kiem tra mang Wi-Fi da khai bao trong danh sach
    if ssid and ssid in wifi_locs:
        target = wifi_locs[ssid]
        state["lat"] = target.get("lat")
        state["lon"] = target.get("lon")
        state["address"] = target.get("address", ssid)
        state["gps_src"] = "WIFI"
        print("==================================================")
        print("📍 [GPS-WIFI] TU DONG NHAN DIEN THEO WI-FI '{}'".format(ssid))
        print(">> Toa do (Lat, Lon) : {}, {}".format(state["lat"], state["lon"]))
        print(">> Dia chi chinh xac : {}".format(state["address"]))
        print(">> Xem tren Google Maps: https://www.google.com/maps?q={},{}".format(state["lat"], state["lon"]))
        print("==================================================")
        return True

    # 3. Uu tien 3: Wi-Fi moi hoan toan -> Tu dong dinh vi qua IP Public (Fallback)
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
                state["gps_src"] = "IP"
                loc_text = "{}, {}".format(city, region) if city else region
                state["address"] = "{}, {}".format(loc_text, country) if loc_text else (ssid or "Wi-Fi Vi tri")

                print("==================================================")
                print("📍 [GPS-IP] DINH VI QUA IP CHO MANG MOI THANH CONG!")
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
# 6. CAC HAM DOC CAM BIEN (NON-BLOCKING)
# ==============================================================
def read_sht30():
    buses = [i2c_sht]
    if 'i2c_sht_rev' in globals() and i2c_sht_rev:
        buses.append(i2c_sht_rev)
    if 'i2c_sht_right' in globals() and i2c_sht_right:
        buses.append(i2c_sht_right)
    if 'i2c_oled' in globals() and i2c_oled:
        buses.append(i2c_oled)

    for bus in buses:
        try:
            bus.writeto(config.SHT30_ADDR, b'\x2C\x06')
            time.sleep_ms(25)
            d = bus.readfrom(config.SHT30_ADDR, 6)
            if not d or len(d) < 6:
                continue
            if (d[0] == 0 and d[1] == 0 and d[3] == 0) or (d[0] == 0xFF and d[1] == 0xFF):
                continue
            temp = -45.0 + (175.0 * ((d[0] << 8) | d[1]) / 65535.0)
            hum = 100.0 * (((d[3] << 8) | d[4]) / 65535.0)
            if temp < -40.0 or temp > 125.0 or hum <= 0.0 or hum > 100.0:
                continue
            return round(temp, 1), round(hum, 1)
        except Exception:
            pass
    return None, None

def read_light():
    total = 0
    samples = 8
    for _ in range(samples):
        total += ldr.read_u16()
        time.sleep_ms(1)
    raw = total // samples
    percent_dark = int((raw / 65535) * 100)
    if percent_dark > 100: percent_dark = 100
    return raw, percent_dark

# Bien doc DS18B20 khong chan (non-blocking)
last_ds_start = 0
ds_converting = False

def poll_sensors():
    global ds_converting, last_ds_start
    now = time.ticks_ms()

    # 1. Quang tro
    raw, pct = read_light()
    state["light_raw"] = raw
    state["light_pct"] = pct

    # 2. SHT30
    at, ah = read_sht30()
    if at is not None:
        state["air_t"] = at
        state["air_h"] = ah
        state["dew"] = dew_point(at, ah)

    # 3. DS18B20 1-Wire khong chan
    if roms:
        if not ds_converting:
            try:
                ds_sensor.convert_temp()
                ds_converting = True
                last_ds_start = now
            except Exception:
                pass
        elif time.ticks_diff(now, last_ds_start) >= 750:
            try:
                val = ds_sensor.read_temp(roms[0])
                if val is not None and val != 85.0 and val > -127:
                    state["probe"] = round(val, 1)
            except Exception:
                pass
            ds_converting = False

    # 4. Nhiet do chip noi bo Pico 2 W (RP2040/RP2350)
    pt = read_pico_temp()
    if pt is not None:
        state["pico_t"] = pt

# ==============================================================
# 7. DIEU KHIEN DUC PHONG (FAIL-SAFE KHI MAT BACKEND)
# ==============================================================
def local_control():
    # Khi App/Server khong can thiep (mode AUTO) hoac mat mang > 30s
    req_light = state["light_raw"] >= config.LIGHT_ON_THRESHOLD
    req_water = state["probe"] is not None and state["probe"] >= config.WATER_ON_THRESHOLD
    req_hum   = state["air_h"] is not None and state["air_h"] >= config.HUM_ON_THRESHOLD

    should_on = req_light or req_water or req_hum

    safe_light = state["light_raw"] <= config.LIGHT_OFF_THRESHOLD
    safe_water = state["probe"] is None or state["probe"] < config.WATER_OFF_THRESHOLD
    safe_hum   = state["air_h"] is None or state["air_h"] < config.HUM_OFF_THRESHOLD

    if should_on:
        reasons = []
        if req_light: reasons.append("TOI")
        if req_water: reasons.append("NUOC AM")
        if req_hum:   reasons.append("AM CAO")
        set_relay(True, "+".join(reasons))
    elif safe_light and safe_water and safe_hum:
        set_relay(False)

# ==============================================================
# 8. GUI DU LIEU LEN BACKEND C# (HTTP POST + HMAC-SHA256)
# ==============================================================
def send_to_backend():
    if not wlan.isconnected():
        return False

    loc_display = None
    if state.get("gps_fixed") and state.get("gps_lat") is not None:
        loc_display = "GPS Vệ tinh ({:.4f}, {:.4f})".format(state["lat"], state["lon"])
    elif state.get("address"):
        if state["lat"] is not None and state["lon"] is not None:
            loc_display = "{} ({:.4f}, {:.4f})".format(state["address"], state["lat"], state["lon"])
        else:
            loc_display = state["address"]
    elif state["lat"] is not None and state["lon"] is not None:
        loc_display = "({:.4f}, {:.4f})".format(state["lat"], state["lon"])

    payload_obj = {
        "device_code": config.DEVICE_CODE,
        "air_temp": state["air_t"],
        "air_hum": state["air_h"],
        "probe_temp": state["probe"],
        "pico_temp": state.get("pico_t"),
        "dew_point": state["dew"],
        "light_raw": state["light_raw"],
        "light_pct": state["light_pct"],
        "relay_state": 1 if state["relay"] else 0,
        "rssi": wlan.status("rssi") if hasattr(wlan, "status") else -50,
        "fw": FW_VERSION,
        "lat": state["lat"],
        "lon": state["lon"],
        "gps_sats": state.get("gps_sats", 0),
        "gps_src": state.get("gps_src", "NONE"),
        "location": loc_display,
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

        if r.status_code == 401:
            try:
                srv = int(r.json().get("server_time", 0))
                if srv > 0:
                    global time_offset_ms
                    time_offset_ms = srv - time.ticks_ms()
            except Exception:
                pass
            print(">> Dong ho lech, da dong bo lai gio server")
            return False

        if r.status_code != 200:
            print(">> HTTP Error:", r.status_code)
            return False

        resp = r.json()
        if not resp.get("ok"):
            print(">> Backend tu choi:", resp.get("error"))
            return False

        # Cap nhat trang thai tu Server / App Flutter
        server_relay = resp.get("relay")
        server_mode = resp.get("mode", "AUTO")
        state["mode"] = server_mode
        state["status"] = resp.get("status", "OK")
        state["interval"] = max(2, int(resp.get("interval", 3)))

        oled_info = resp.get("oled") or {}
        state["alert"] = oled_info.get("alert", "") or ""
        state["msg"] = oled_info.get("msg", "") or ""

        # Xu ly che do Relay tu Backend
        if server_mode == "ON":
            set_relay(True, "APP ON")
        elif server_mode == "OFF":
            set_relay(False)
        elif server_mode == "AUTO":
            # Neu Backend ra quyet dinh relay (1 hoac 0)
            if server_relay is not None:
                set_relay(server_relay == 1, resp.get("reason", "AUTO"))
            else:
                local_control()

        return True

    except Exception as e:
        print(">> Loi gui du lieu backend:", e)
        return False
    finally:
        if r is not None:
            try: r.close()
            except Exception: pass
        gc.collect()

# ==============================================================
# 9. GIAO DIEN OLED 128x64 TOAN DIEN (CO TRANG THAI GPS VE TINH)
# ==============================================================
def draw_oled(blink=False):
    if not oled: return
    o = oled
    o.fill(0)

    # 1. Header: Ma thiet bi & Trang thai GPS + Server
    o.fill_rect(0, 0, 128, 11, 1)
    dev_str = config.DEVICE_CODE
    o.text(dev_str, 2, 2, 0)

    # Kí hiệu GPS tren Header:
    s_use = state.get("gps_sats", 0)
    s_view = state.get("gps_sats_view", 0)
    if state.get("gps_fixed"):
        gps_tag = "SAT*" if blink else "SAT "
    elif s_use > 0:
        gps_tag = "S:{}".format(s_use)
    elif s_view > 0:
        gps_tag = "S:{}".format(s_view)
    elif state.get("gps_src") == "WIFI":
        gps_tag = "WIFI"
    else:
        gps_tag = "GPS."

    st = "OFF" if state["offline"] else state["status"]
    tag = "{}|{}".format(gps_tag, st)
    w = len(tag) * 8 + 4
    badge_x = 128 - w
    dev_w = len(dev_str) * 8 + 4
    if badge_x < dev_w:
        badge_x = dev_w
        w = 128 - badge_x
    o.fill_rect(badge_x, 1, w, 9, 0)
    o.text(tag, badge_x + 2, 2, 1)

    # 2. Hang 1: Khong khi (T & H)
    t_str = "--.-" if state["air_t"] is None else "{:.1f}".format(state["air_t"])
    h_str = "--.-" if state["air_h"] is None else "{:.1f}".format(state["air_h"])
    o.text("Air:{}C {}%".format(t_str, h_str), 0, 14, 1)

    # 3. Hang 2: Que inox nuoc (DS18B20) & Quang tro LDR
    p_str = "--.-" if state["probe"] is None else "{:.1f}".format(state["probe"])
    o.text("Nuoc:{}C Toi:{}%".format(p_str, state["light_pct"]), 0, 26, 1)

    # 4. Hang 3: Trang thai Relay + Che do + Tinh trang Ve tinh
    r_str = "BAT" if state["relay"] else "TAT"
    mode_str = state["mode"][:1]
    if state.get("gps_fixed"):
        sat_status = "SAT:FIX"
    elif s_view > 0:
        sat_status = "S:{}cho".format(s_view)
    elif state.get("gps_src") == "WIFI":
        sat_status = "GPS:WiFi"
    elif state.get("gps_rx_bytes", 0) > 0:
        sat_status = "GPS:Scan"
    else:
        sat_status = "GPS:Wait"
    o.text("R:{} [{}] {}".format(r_str, mode_str, sat_status), 0, 38, 1)

    # 5. Hang 4: Footer luan chuyen thong tin (3 giay / man hinh)
    now_sec = time.ticks_ms() // 1000
    cycle = (now_sec // 3) % 4

    if state["msg"]:
        footer = "> " + state["msg"]
    elif state["reason"]:
        footer = "! " + state["reason"]
    elif state["alert"]:
        footer = "! " + state["alert"]
    elif cycle == 0 and state.get("lat") is not None:
        footer = "LAT:{:.5f}".format(state["lat"])
    elif cycle == 1 and state.get("lon") is not None:
        footer = "LON:{:.5f}".format(state["lon"])
    elif cycle == 2:
        if state.get("gps_alt_m") is not None:
            footer = "Alt:{}m S:{}".format(int(state["gps_alt_m"]), s_use or s_view)
        elif state.get("gps_speed_kmh") is not None and state["gps_speed_kmh"] > 0:
            footer = "Spd:{}km/h".format(state["gps_speed_kmh"])
        elif s_view > 0:
            footer = "S:{} dung/{} nhin".format(s_use, s_view)
        else:
            footer = "GPS: {}".format(sat_status)
    elif cycle == 3 and wifi_connected:
        footer = "IP:" + wifi_ip
    else:
        footer = state.get("connected_ssid") or "Pico 2 W Online"

    o.text(footer[:16], 0, 52, 1)
    o.show()

# ==============================================================
# 10. VONG LAP CHINH (MAIN EVENT LOOP)
# ==============================================================
def main():
    connect_wifi_auto()
    if wlan.isconnected():
        sync_time()

    last_read = 0
    last_send = 0
    last_ok = time.ticks_ms()
    last_wifi_retry = time.ticks_ms()
    last_sync = time.ticks_ms()
    last_gps_update = time.ticks_ms()
    blink = False

    while True:
        now = time.ticks_ms()

        # 0. Doc du lieu GPS tu UART0 khong chan (non-blocking)
        poll_gps()

        # 1. Tu dong thu lai ket noi Wi-Fi neu mat mang
        if not wlan.isconnected() and time.ticks_diff(now, last_wifi_retry) > 10000:
            last_wifi_retry = now
            connect_wifi_auto()
            if wlan.isconnected():
                sync_time()

        # 2. Dong bo lai gio moi 30 phut
        if wlan.isconnected() and time.ticks_diff(now, last_sync) > 1800000:
            last_sync = now
            sync_time()

        # 2.1 Dinh ky cap nhat lai vi tri moi 30 phut hoac khi chua co toa do
        if wlan.isconnected() and (state["lat"] is None or time.ticks_diff(now, last_gps_update) > 1800000):
            last_gps_update = now
            resolve_auto_location()

        # 3. Doc cam bien moi 400ms (nhanh, muot)
        if time.ticks_diff(now, last_read) >= 400:
            last_read = now
            poll_sensors()

            # Neu mat ket noi server -> chay che do tu tri cuc bo
            if state["offline"] or state["mode"] == "AUTO":
                local_control()

            draw_oled(blink)

        # 4. Gui so lieu len Backend C# theo chu ky (mac dinh 3s)
        if time.ticks_diff(now, last_send) >= state["interval"] * 1000:
            last_send = now
            ok = send_to_backend()
            if ok:
                last_ok = time.ticks_ms()
                state["offline"] = False
                print(">> [SEND OK] Air={:.1f}C {}% | Probe={}C | Light={}% | Relay={} ({})".format(
                    state["air_t"] or 0, state["air_h"] or 0, state["probe"] or 0, state["light_pct"],
                    "ON" if state["relay"] else "OFF", state["mode"]))
            else:
                # Neu mat tin hieu server qua 25 giay -> chuyen sang OFFLINE
                if time.ticks_diff(time.ticks_ms(), last_ok) > 25000:
                    if not state["offline"]:
                        print(">> Mat ket noi Backend > 25s -> Chuyen che do DU PHONG (Local Control)!")
                    state["offline"] = True
                    pico_led.toggle()

            draw_oled(blink)

        # 5. Nhap nhay canh bao neu nguy hiem
        if state["status"] == "DANGER":
            blink = not blink

        time.sleep_ms(100)

try:
    main()
except KeyboardInterrupt:
    set_relay(False)
    print("\n>> Dung chuong trinh boi nguoi dung.")
