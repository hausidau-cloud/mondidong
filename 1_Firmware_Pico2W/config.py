# =====================================================================
# CAU HINH TRAM GIAM SAT IOT - RASPBERRY PI PICO 2 W
# =====================================================================

# 1. DANH SACH WI-FI (Tu dong quet va ket noi mang san co)
WIFI_LIST = [
    ("_hhau.05_", "00000000"),
    ("iPhone", "88888888"),
    ("Bekind Coffee", "camonquykhach"),
    ("Quan Buu", "0777803936"),
]

# 2. DIA CHI BACKEND C# (Cloud Server Render hoac Localhost)
# Dung link Cloud: "https://mondidong.onrender.com" (hoac "http://192.168.110.61:5000" khi test local)
SERVER_URL = "https://mondidong.onrender.com"

# 3. THONG TIN THIET BI VA KHOA BAO MAT HMAC-SHA256 (Lay tu App khi bam Them thiet bi)
DEVICE_CODE = "PICO-1"
# API_KEY la BI MAT duoc cap tu Backend/App. Pico dung no de ky so tung goi tin.
API_KEY     = "faf805d549a04998880242db2f1d3948"

# 4. CHU KY GUI DU LIEU LEN SERVER (Giay) - Giam xuong 2s de cap nhat realtime cuc nhanh
SEND_INTERVAL_DEFAULT = 2

# 5. SO DO CHAN PHAN CUNG THUC TE (Chuan 100% tren mach da dau noi)
# - Man hinh OLED 0.96 inch I2C (SSD1306/SSD1315):
PIN_OLED_SDA = 14     # GP14 (Chan 19)
PIN_OLED_SCL = 15     # GP15 (Chan 20)
OLED_ADDR    = 0x3C

# - Cam bien Nhiet do & Do am khong khi SHT30 (Chuan theo ban dang cam):
PIN_SHT_SDA  = 16     # GP16 (Chan 21 - Day Vang SDA)
PIN_SHT_SCL  = 17     # GP17 (Chan 22 - Day Xanh SCL)
SHT30_ADDR   = 0x44

# - Cam bien Nhiet do nuoc que inox DS18B20 (1-Wire):
PIN_DS18B20  = 22     # GP22 (Chan 29 - co tro 4.7k keo len 3V3)

# - Cam bien Cuong do anh sang / Quang tro MKE-S02 (ADC):
PIN_LDR_ADC  = 26     # GP26 (Chan 31, ADC0)

# - Module Relay 5V dieu khien den/thiet bi:
PIN_RELAY    = 13     # GP13 (Chan 17)
RELAY_ACTIVE_HIGH = True  # True: Muc 1 (HIGH) la DONG/BAT relay; False neu relay kich muc Thap

# 6. NGUONG DIEU KHIEN DUC PHONG (FAIL-SAFE KHI MAT KET NOI SERVER)
# Khi mat mang hoac backend tat > 30 giay, Pico tu dung cac nguong nay de bat/tat relay:
LIGHT_ON_THRESHOLD   = 30000   # Che toi >= 30.000 -> BAT Relay
LIGHT_OFF_THRESHOLD  = 20000   # Soi sang <= 20.000 -> TAT Relay
WATER_ON_THRESHOLD   = 32.5    # Nhiet do nuoc >= 32.5 C -> BAT Relay
WATER_OFF_THRESHOLD  = 32.4    # Nhiet do nuoc < 32.4 C -> TAT Relay
HUM_ON_THRESHOLD     = 75.0    # Do am khong khi >= 75% -> BAT Relay
HUM_OFF_THRESHOLD    = 70.0    # Do am khong khi < 70% -> TAT Relay
