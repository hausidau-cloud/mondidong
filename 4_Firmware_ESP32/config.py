# =====================================================================
# CAU HINH THIET BI IOT - ESP32 NODEMCU (MicroPython)
# CAM BIEN NHIET DO & DO AM DHT11 + DIEU KHIEN LED (GPIO 23)
# =====================================================================

# 1. DANH SACH WI-FI (Tu dong quet va ket noi mang san co)
WIFI_LIST = [
    ("_hhau.05_", "00000000"),
    ("iPhone", "88888888"),
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

# - Chan dieu khien den LED / Relay (khop voi Arduino code cu cua ban):
PIN_LED     = 23      # GPIO 23 (Chan D23)

# 6. NGUONG DIEU KHIEN CANH BAO CUC BO (FAIL-SAFE KHI MAT MANG)
TEMP_THRESHOLD = 30.0  # Nhiet do >= 30.0 do C -> Bat den canh bao
HUM_THRESHOLD  = 75.0  # Do am >= 75% -> Bat canh bao
