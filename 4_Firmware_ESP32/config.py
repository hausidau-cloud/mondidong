# =====================================================================
# CAU HINH THIET BI IOT - ESP32 NODEMCU (MicroPython)
# CAM BIEN NHIET DO & DO AM DHT11 + DIEU KHIEN LED (GPIO 23)
# =====================================================================

# 1. DANH SACH WI-FI (Tu dong quet va ket noi mang san co)
WIFI_LIST = [
    ("NHA TRO 102", "0902511322"),
    ("Duy Thuc_2", "thuchuong"),
    ("Duy thuc", "thuchuong"),
    ("_hhau.05_", "00000000"),
  
    ("Bekind Coffee", "camonquykhach"),
    ("Quan Buu", "0777803936"),
]

# 2. DIA CHI BACKEND C# CLOUD RENDER
SERVER_URL = "https://mondidong.onrender.com"

# 3. THONG TIN THIET BI VA KHOA BAO MAT HMAC-SHA256 (Khop 100% voi App Flutter)
DEVICE_CODE = "ESP32-1"
API_KEY     = "esp32_dev_secret_key_8888"

# 4. CHU KY GUI DU LIEU LEN SERVER (Giay)
SEND_INTERVAL_DEFAULT = 2

# 5. SO DO CHAN PHAN CUNG ESP32 NODEMCU (38 CHAN)
# - Chan tin hieu Data cua cam bien DHT11:
PIN_DHT     = 4       # GPIO 4 (Chan D4)

# - Chan dieu khien den LED nho tich hop san tren bo mach ESP32:
PIN_LED     = 2       # GPIO 2 (Den LED nho gan tren mach ESP32 NodeMCU)

# 6. NGUONG DIEU KHIEN CANH BAO CUC BO (FAIL-SAFE KHI MAT MANG)
TEMP_THRESHOLD = 30.0  # Nhiet do >= 30.0 do C -> Bat den canh bao
HUM_THRESHOLD  = 75.0  # Do am >= 75% -> Bat canh bao

# 7. BANG TRA CUU TOA DO TU DONG THEO TUNG WI-FI
# Cu ket noi vao Wi-Fi nao -> ESP32 tu dong lay dung toa do & dia chi cua noi do!
WIFI_LOCATIONS = {
    "NHA TRO 102": {
        "lat": 10.8220,
        "lon": 106.6257,
        "address": "Nhà trọ 102 - TP. Hồ Chí Minh",
    },
    "Duy Thuc_2": {
        "lat": 10.8220,
        "lon": 106.6257,
        "address": "Phòng của bạn - Đường Trường Chinh, TP.HCM",
    },
    "Duy thuc": {
        "lat": 10.8220,
        "lon": 106.6257,
        "address": "Phòng của bạn - Đường Trường Chinh, TP.HCM",
    },
    "Bekind Coffee": {
        "lat": 10.7952,
        "lon": 106.6631,
        "address": "Bekind Coffee - TP. Hồ Chí Minh",
    },
    "Quan Buu": {
        "lat": 10.8150,
        "lon": 106.6320,
        "address": "Quán Bửu - TP. Hồ Chí Minh",
    },
}


