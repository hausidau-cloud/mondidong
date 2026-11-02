# HƯỚNG DẪN NẠP CODE PICO 2 W - HỆ THỐNG IOT GIÁM SÁT

Thư mục này chứa firmware hoàn chỉnh dành cho **Raspberry Pi Pico 2 W**, đồng bộ trực tiếp với **Backend C# (.NET Web API)** và **App Flutter**.

---

## 1. Các file trong thư mục này
1. **`config.py`**: Cấu hình danh sách Wi-Fi, địa chỉ IP của máy tính chạy Backend C#, mã trạm `DEVICE_CODE`, khóa bí mật `API_KEY`, và sơ đồ chân thực tế.
2. **`main.py`**: Chương trình chính chạy trên Pico 2 W:
   * Tự động quét và kết nối Wi-Fi.
   * Đọc cảm biến: SHT30 (nhiệt/ẩm), DS18B20 (nước inox), Quang trở MKE-S02 (ánh sáng).
   * Điều khiển Relay 5V (GP13).
   * Hiển thị đầy đủ thông số trên màn hình OLED 128x64.
   * Ký số bảo mật HMAC-SHA256 và gửi HTTP POST lên Backend C#.
   * Chế độ tự trị (Fail-safe): Nếu tắt Backend hoặc mất mạng > 25s, Pico tự động đo và bật/tắt relay theo ngưỡng bảo vệ.

---

## 2. Sơ đồ nối dây thực tế
* **OLED 0.96 inch**: SDA $\rightarrow$ GP14 (Pin 19), SCL $\rightarrow$ GP15 (Pin 20)
* **Cảm biến SHT30**: SDA $\rightarrow$ GP17 (Pin 22), SCL $\rightarrow$ GP16 (Pin 21)
* **Cảm biến DS18B20**: Chân Data $\rightarrow$ GP22 (Pin 29) + trở kéo 4.7k lên 3V3
* **Quang trở LDR MKE-S02**: Chân Signal (S) $\rightarrow$ GP26 (Pin 31, ADC0)
* **Module Relay 5V**: Chân IN $\rightarrow$ GP13 (Pin 17)

---

## 3. Cách nạp code bằng Thonny IDE
1. Cắm cáp micro-USB từ Pico 2 W vào máy tính.
2. Mở phần mềm **Thonny IDE**:
   * Vào **Tools** $\rightarrow$ **Options** $\rightarrow$ **Interpreter**.
   * Chọn `MicroPython (Raspberry Pi Pico)`.
3. Mở file `config.py`:
   * Chỉnh sửa lại `SERVER_URL` thành địa chỉ IP máy tính đang chạy Backend C# (ví dụ: `http://192.168.1.15:5000`).
   * Chọn **File** $\rightarrow$ **Save as...** $\rightarrow$ Chọn **Raspberry Pi Pico** $\rightarrow$ Lưu tên `config.py`.
4. Mở file `main.py`:
   * Chọn **File** $\rightarrow$ **Save as...** $\rightarrow$ Chọn **Raspberry Pi Pico** $\rightarrow$ Lưu tên `main.py`.
5. Rút cáp cắm lại hoặc nhấn nút `Stop/Restart` trên Thonny, Pico 2 W sẽ tự động chạy!
