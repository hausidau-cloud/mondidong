# BACKEND C# (.NET 9) - THERMOGUARD IOT API

Dự án Backend viết bằng **C# ASP.NET Core Web API (.NET 9)**, thay thế toàn bộ backend PHP / Node.js cũ.

---

## 1. Tính năng nổi bật
* **Tương thích 100%:** Hỗ trợ song song cả endpoint chuẩn (`/api/ingest`, `/api/devices`,...) và endpoint dạng `.php` (`/api/ingest.php`, `/api/devices.php`,...) giúp Pico 2 W và App Flutter kết nối mượt mà không cần sửa code mạng.
* **Bảo mật HMAC-SHA256:** Tự động kiểm tra chữ ký số từ Pico 2 W gửi lên bằng khóa bí mật `API_KEY`.
* **Đồng bộ thời gian:** Cung cấp endpoint `/api/time` để Pico đồng bộ timestamp chống replay attack.
* **Swagger UI:** Tích hợp giao diện trực quan tại `http://localhost:5000/swagger` để test trực tiếp trên trình duyệt.
* **CORS Open:** Cho phép App Flutter Web, Android, iOS gọi API không bị chặn cross-origin.
* **Auto Fail-safe Watchdog:** Tự động theo dõi trạng thái trạm, nếu mất kết nối quá thời gian cài đặt (`offline_after`) sẽ chuyển sang `OFFLINE`.

---

## 2. Cách chạy Backend
### Cách 1: Chạy bằng file bat (nhanh nhất)
Nhấp đúp chuột vào file:
```
2_Backend_CSharp/run_backend.bat
```

### Cách 2: Chạy bằng dòng lệnh Terminal
```bash
cd c:\Users\Admin\Documents\LinhKien\2_Backend_CSharp\ThermoGuard.Api
dotnet run
```

Sau khi chạy:
* Link trang chủ: `http://localhost:5000`
* Link giao diện test Swagger: `http://localhost:5000/swagger`

---

## 3. Tài khoản đăng nhập mặc định (dùng trên App Flutter)
* **Tài khoản Admin:**
  * Username: `admin`
  * Mật khẩu: `password123` (hoặc `admin123`)
* **Tài khoản Viewer:**
  * Username: `viewer`
  * Mật khẩu: `password123`
