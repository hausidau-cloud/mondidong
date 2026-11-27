# =====================================================================
# CAU HINH TRAM GIAM SAT IOT - RASPBERRY PI PICO 2 W
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

# 2. DIA CHI BACKEND C# (Cloud Server Render hoac Localhost)
# Dung link Cloud: "https://mondidong.onrender.com" (hoac "http://192.168.110.61:5000" khi test local)
SERVER_URL = "https://mondidong.onrender.com"

# 3. THONG TIN THIET BI VA KHOA BAO MAT HMAC-SHA256 (Lay tu App khi bam Them thiet bi)
DEVICE_CODE = "PICO 1"
# API_KEY la BI MAT duoc cap tu Backend/App. Pico dung no de ky so tung goi tin.
API_KEY     = "a1b2c3d4e5f60718293a4b5c6d7e8f90"

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

# - Cam bien Do sach/ban cua nuoc TDS Meter (ADC1):
PIN_TDS_ADC  = 27     # GP27 (Chan 32, ADC1)

# - Module Relay 5V dieu khien den/thiet bi:
PIN_RELAY    = 13     # GP13 (Chan 17)
RELAY_ACTIVE_HIGH = True  # True: Muc 1 (HIGH) la DONG/BAT relay; False neu relay kich muc Thap

# - Module GPS U-blox NEO-6M (UART0):
# Huong dan dau day phan cung cho Pico 2 W:
#   * VCC cua NEO-6M  -> Chan Pin 36 (3V3_OUT) hoac Chan Pin 40 (VBUS 5V)
#   * GND cua NEO-6M  -> Chan Pin 3 / 8 / 38 (GND)
#   * TXD cua NEO-6M  -> Chan GP1 (Pin 2 cua Pico - UART0 RX)
#   * RXD cua NEO-6M  -> Chan GP0 (Pin 1 cua Pico - UART0 TX)
PIN_GPS_TX   = 0      # GP0 (Chan 1 - Pico TX noi vao RXD cua GPS)
PIN_GPS_RX   = 1      # GP1 (Chan 2 - Pico RX noi vao TXD cua GPS)
GPS_BAUDRATE = 9600

# 6. NGUONG DIEU KHIEN DUC PHONG (FAIL-SAFE KHI MAT KET NOI SERVER)
# Khi mat mang hoac backend tat > 30 giay, Pico tu dung cac nguong nay de bat/tat relay:
LIGHT_ON_THRESHOLD   = 30000   # Che toi >= 30.000 -> BAT Relay
LIGHT_OFF_THRESHOLD  = 20000   # Soi sang <= 20.000 -> TAT Relay
WATER_ON_THRESHOLD   = 32.5    # Nhiet do nuoc >= 32.5 C -> BAT Relay
WATER_OFF_THRESHOLD  = 32.4    # Nhiet do nuoc < 32.4 C -> TAT Relay
HUM_ON_THRESHOLD     = 75.0    # Do am khong khi >= 75% -> BAT Relay
HUM_OFF_THRESHOLD    = 70.0    # Do am khong khi < 70% -> TAT Relay

# 7. BANG TRA CUU TOA DO TU DONG THEO TUNG WI-FI
# Cu ket noi vao Wi-Fi nao -> Pico tu dong lay dung toa do & dia chi cua noi do!
# (Neu ket noi vao Wi-Fi la, Pico tu dong dinh vi qua IP cua mang do!)
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
