# FRONTEND FLUTTER - THERMOGUARD IOT APP

Dự án ứng dụng di động & Web viết bằng **Flutter (Dart 3)** dành cho hệ thống giám sát môi trường IoT ThermoGuard.

---

## 1. Kết nối Backend C#
App đã được cấu hình mặc định trỏ vào Backend C# (.NET 9) trên cổng **5000**:
* Trên máy tính / Flutter Web: `http://localhost:5000`
* Trên máy ảo Android Emulator: `http://10.0.2.2:5000`
* Trên điện thoại thật (cùng mạng Wi-Fi): Nhập địa chỉ IPv4 của máy tính (ví dụ `http://192.168.1.15:5000` ở màn hình Cài đặt).

---

## 2. Các tính năng chính
1. **Màn hình Hub & Tổng quan:**
   * Xem thời gian thực các cảm biến: Nhiệt độ que inox nước DS18B20, Nhiệt độ không khí SHT30, Độ ẩm tương đối SHT30, Cường độ ánh sáng / Độ tối Quang trở MKE-S02, Điểm đọng sương (Dew point).
   * Xem trạng thái trạm: `OK`, `WARNING`, `DANGER`, `OFFLINE`.
2. **Điều khiển Relay từ xa:**
   * Chế độ `AUTO`: Tự động ngắt mở relay theo ngưỡng bảo vệ.
   * Chế độ `BẬT (ON)` / `TẮT (OFF)`: Bật tắt cưỡng bức từ điện thoại xuống Pico 2 W.
3. **Cài đặt ngưỡng & Thông điệp OLED:**
   * Thay đổi ngưỡng nhiệt độ tối đa, độ ẩm tối đa từ xa.
   * Gõ chữ gửi thông báo hiển thị trực tiếp lên màn hình OLED 128x64 của Pico.
4. **Biểu đồ & Nhật ký:**
   * Vẽ biểu đồ đường biến thiên nhiệt độ 1h, 6h, 24h, 7 ngày.
   * Lịch sử nhật ký đóng ngắt relay.

---

## 3. Cách chạy ứng dụng
### Cách 1: Chạy trên trình duyệt Web (Chrome)
```bash
cd c:\Users\Admin\Documents\LinhKien\3_Frontend_Flutter
flutter run -d chrome
```

### Cách 2: Chạy trên máy ảo hoặc điện thoại Android
```bash
cd c:\Users\Admin\Documents\LinhKien\3_Frontend_Flutter
flutter run
```

---

## 4. Tài khoản đăng nhập
* **Admin:** `admin` / `password123`
* **Viewer:** `viewer` / `password123`
