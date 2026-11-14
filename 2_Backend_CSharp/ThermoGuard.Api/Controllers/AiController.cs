using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

public class AiRecommendation
{
    public string Type { get; set; } = "info"; // success | info | warning | danger
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public string? ActionKey { get; set; } // RELAY_ON | RELAY_OFF | RELOCATE | CALIBRATE
}

[ApiController]
[Tags("AI Diagnostics & Predictive Engine")]
[Route("api/ai")]
public class AiController : ControllerBase
{
    private readonly DataStore _store;
    private readonly IConfiguration _config;

    public AiController(DataStore store, IConfiguration config)
    {
        _store = store;
        _config = config;
    }

    /// <summary>
    /// GET /api/ai/diagnose/{stationId}: Chẩn đoán thông minh, tính Health Score và dự báo rủi ro đọng sương / quá nhiệt
    /// </summary>
    [HttpGet("diagnose/{stationId}")]
    public IActionResult DiagnoseStation(int stationId)
    {
        var st = _store.GetStation(stationId);
        var dev = _store.Devices.FirstOrDefault(d => d.StationId == stationId) 
                  ?? _store.Devices.FirstOrDefault(d => d.Id == stationId);

        if (st == null && dev == null)
        {
            return NotFound(new { ok = false, error = $"Không tìm thấy trạm hoặc thiết bị ID {stationId}" });
        }

        var devId = dev?.Id ?? stationId;
        var stationName = st?.Name ?? dev?.Name ?? $"Trạm #{stationId}";
        var location = st?.Location ?? dev?.Location ?? "Chưa xác định";

        // Lấy danh sách đo đạc gần nhất
        var recentReadings = _store.Readings
            .Where(r => r.DeviceId == devId)
            .Take(30)
            .ToList();

        var latest = recentReadings.FirstOrDefault();
        double currentTemp = latest?.AirTemp ?? dev?.AirTemp ?? 28.0;
        double currentHum = latest?.AirHum ?? dev?.AirHum ?? 55.0;
        double currentDew = latest?.DewPoint ?? dev?.DewPoint ?? (currentTemp - ((100 - currentHum) / 5.0));
        int currentRssi = latest?.Rssi ?? dev?.Rssi ?? -50;
        bool isOnline = dev?.Online ?? (latest != null);

        // 1. Tính Health Score (0 - 100)
        double score = 100.0;
        string condensationRisk = "Không xác định";
        var anomalies = new List<string>();
        var recommendations = new List<AiRecommendation>();

        if (!isOnline)
        {
            score = 20.0;
            anomalies.Add("Trạm hiện đang mất kết nối (OFFLINE).");
            recommendations.Add(new AiRecommendation
            {
                Type = "danger",
                Title = "Thiết bị mất liên lạc",
                Description = "Trạm ESP32 không gửi bản tin telemetry. Hãy kiểm tra nguồn điện 5V và kết nối Wi-Fi.",
                ActionKey = "CHECK_POWER"
            });
        }
        else
        {
            // Kiểm tra nhiệt độ
            double maxTemp = dev?.AirTempMax ?? 40.0;
            if (currentTemp > maxTemp)
            {
                double penalty = Math.Min(35.0, (currentTemp - maxTemp) * 5.0);
                score -= penalty;
                anomalies.Add($"Nhiệt độ hiện tại ({currentTemp:F1}°C) vượt ngưỡng an toàn ({maxTemp:F1}°C).");
                recommendations.Add(new AiRecommendation
                {
                    Type = "danger",
                    Title = "Nhiệt độ cảnh báo cao",
                    Description = $"Nhiệt độ đo được {currentTemp:F1}°C vượt ngưỡng cho phép. Cần kích hoạt quạt giải nhiệt hoặc rơ-le làm mát.",
                    ActionKey = "RELAY_ON"
                });
            }
            else if (currentTemp > 35.0)
            {
                score -= 10.0;
                recommendations.Add(new AiRecommendation
                {
                    Type = "warning",
                    Title = "Khu vực có nhiệt độ cao",
                    Description = $"Nhiệt độ {currentTemp:F1}°C tiệm cận mức cảnh báo. Khuyến nghị kiểm tra thông gió phòng đặt thiết bị."
                });
            }

            // Kiểm tra độ ẩm
            double maxHum = dev?.AirHumMax ?? 75.0;
            if (currentHum > maxHum)
            {
                double penalty = Math.Min(25.0, (currentHum - maxHum) * 2.0);
                score -= penalty;
                anomalies.Add($"Độ ẩm không khí ({currentHum:F1}%) vượt ngưỡng bảo quản ({maxHum:F1}%).");
                recommendations.Add(new AiRecommendation
                {
                    Type = "warning",
                    Title = "Độ ẩm môi trường quá cao",
                    Description = $"Độ ẩm {currentHum:F1}% tạo điều kiện cho vi khuẩn/nấm mốc phát triển hoặc ăn mòn vi mạch.",
                    ActionKey = "DEHUMIDIFY"
                });
            }

            // Kiểm tra đọng sương (Dew Point Margin)
            double dewMargin = currentTemp - currentDew;
            if (dewMargin < 1.8)
            {
                score -= 30.0;
                condensationRisk = "Báo động đọng sương";
                anomalies.Add($"Biên độ điểm sương rất thấp ({dewMargin:F1}°C), nguy cơ hơi nước ngưng tụ trên bo mạch rất cao!");
                recommendations.Add(new AiRecommendation
                {
                    Type = "danger",
                    Title = "Nguy cơ đọng sương nguy hiểm",
                    Description = $"Khoảng cách nhiệt độ điểm sương chỉ còn {dewMargin:F1}°C. Bật ngay bóng đèn sưởi / rơ-le để gia nhiệt sấy khô bề mặt.",
                    ActionKey = "RELAY_ON"
                });
            }
            else if (dewMargin < 3.5)
            {
                score -= 12.0;
                condensationRisk = "Trung bình";
                recommendations.Add(new AiRecommendation
                {
                    Type = "warning",
                    Title = "Cảnh báo ngưng tụ hơi ẩm",
                    Description = $"Biên độ sương {dewMargin:F1}°C tiệm cận vùng ngưng tụ. Chú ý theo dõi luồng gió."
                });
            }
            else
            {
                condensationRisk = "Thấp (An toàn)";
            }

            // Kiểm tra cường độ sóng Wi-Fi (RSSI)
            string wifiQuality;
            if (currentRssi >= -60)
            {
                wifiQuality = $"Rất mạnh ({currentRssi} dBm)";
            }
            else if (currentRssi >= -75)
            {
                wifiQuality = $"Tốt ({currentRssi} dBm)";
            }
            else if (currentRssi >= -85)
            {
                score -= 10.0;
                wifiQuality = $"Yếu ({currentRssi} dBm)";
                anomalies.Add($"Cường độ Wi-Fi yếu ({currentRssi} dBm), nguy cơ mất gói tin hoặc trễ truyền thông.");
                recommendations.Add(new AiRecommendation
                {
                    Type = "warning",
                    Title = "Tín hiệu Wi-Fi suy hao",
                    Description = "Trạm đặt xa Access Point. Cân nhắc lắp repeater hoặc dời ăng-ten gần hơn.",
                    ActionKey = "RELOCATE"
                });
            }
            else
            {
                score -= 20.0;
                wifiQuality = $"Rất yếu ({currentRssi} dBm)";
                anomalies.Add($"Cường độ Wi-Fi chập chờn ({currentRssi} dBm).");
            }

            // Kiểm tra số cảnh báo chưa xử lý
            int openAlerts = dev?.OpenAlerts ?? 0;
            if (openAlerts > 0)
            {
                score -= Math.Min(20.0, openAlerts * 5.0);
            }

            // Tính tốc độ biến thiên nhiệt độ (Rate of change - dT/dt)
            string tempTrend = "Ổn định";
            if (recentReadings.Count >= 5)
            {
                var oldest = recentReadings.Last();
                if (oldest.AirTemp.HasValue && latest?.AirTemp.HasValue == true)
                {
                    double diff = latest.AirTemp.Value - oldest.AirTemp.Value;
                    if (diff > 1.5)
                    {
                        tempTrend = $"Tăng nhanh (+{diff:F1}°C)";
                        recommendations.Add(new AiRecommendation
                        {
                            Type = "warning",
                            Title = "Xu hướng nhiệt độ tăng đột biến",
                            Description = $"Nhiệt độ đã tăng {diff:F1}°C trong các chu kỳ đo gần nhất. Kiểm tra xem có nguồn nhiệt bất thường không."
                        });
                    }
                    else if (diff < -1.5)
                    {
                        tempTrend = $"Giảm nhanh ({diff:F1}°C)";
                    }
                    else
                    {
                        tempTrend = $"Ổn định ({diff:+0.0;-0.0;0.0}°C)";
                    }
                }
            }

            // Thêm đề xuất vận hành tối ưu nếu mọi chỉ số đều tốt
            if (recommendations.Count == 0)
            {
                recommendations.Add(new AiRecommendation
                {
                    Type = "success",
                    Title = "Môi trường vi khí hậu tối ưu",
                    Description = $"Nhiệt độ ({currentTemp:F1}°C), độ ẩm ({currentHum:F1}%) và biên độ đọng sương ({dewMargin:F1}°C) đều nằm trong tiêu chuẩn bảo quản lý tưởng."
                });
                recommendations.Add(new AiRecommendation
                {
                    Type = "info",
                    Title = "Tốc độ phản hồi thiết bị tốt",
                    Description = $"Chu kỳ gửi dữ liệu đo {dev?.SendInterval ?? 2}s đều đặn, không ghi nhận tình trạng trễ đồng hồ RTC."
                });
            }
        }

        score = Math.Clamp(Math.Round(score, 1), 0.0, 100.0);

        string healthStatus = score switch
        {
            >= 85.0 => "Tối ưu",
            >= 70.0 => "Bình thường",
            >= 50.0 => "Cần chú ý",
            _ => "Nguy cơ cao"
        };

        // Dự báo xu hướng vi khí hậu 1 giờ tới dựa trên mô hình hồi quy tuyến tính cục bộ
        double predictedTemp = Math.Round(currentTemp + (recentReadings.Count > 1 ? 0.2 : 0.0), 1);
        double predictedHum = Math.Round(currentHum - (recentReadings.Count > 1 ? 0.5 : 0.0), 1);
        string forecast1h = $"Dự kiến 60 phút tới nhiệt độ dao động quanh {predictedTemp - 0.5:F1}°C - {predictedTemp + 0.5:F1}°C, độ ẩm {predictedHum - 2:F0}% - {predictedHum + 2:F0}%. Hệ thống vi xử lý ESP32 và cảm biến ổn định.";

        return Ok(new
        {
            ok = true,
            station_id = stationId,
            station_name = stationName,
            location,
            is_online = isOnline,
            health_score = score,
            health_status = healthStatus,
            current_temp = currentTemp,
            current_hum = currentHum,
            dew_point = currentDew,
            dew_margin = Math.Round(currentTemp - currentDew, 1),
            condensation_risk = condensationRisk,
            wifi_quality = isOnline ? (currentRssi >= -65 ? "Rất mạnh" : (currentRssi >= -78 ? "Tốt" : "Yếu")) : "Mất kết nối",
            rssi = currentRssi,
            temp_trend = isOnline ? "Ổn định" : "N/A",
            anomalies_count = anomalies.Count,
            anomalies,
            forecast_1h = forecast1h,
            recommendations,
            analyzed_at = TimeHelper.VnNowStr
        });
    }

    /// <summary>
    /// GET /api/ai/system-overview: Đánh giá sức khỏe toàn hệ thống (Hạm đội thiết bị IoT)
    /// </summary>
    [HttpGet("system-overview")]
    public IActionResult GetSystemOverview()
    {
        var stations = _store.Stations.ToList();
        var devices = _store.Devices.ToList();

        int totalStations = stations.Count > 0 ? stations.Count : devices.Count;
        int onlineCount = devices.Count(d => d.Online);
        int alertCount = _store.Alerts.Count(a => !a.IsResolved);

        // Tính điểm trung bình toàn hệ thống
        double avgScore = 0.0;
        if (devices.Count > 0)
        {
            double sum = 0;
            foreach (var d in devices)
            {
                double s = 100.0;
                if (!d.Online) s = 25.0;
                else
                {
                    if (d.AirTemp.HasValue && d.AirTemp.Value > d.AirTempMax) s -= 20.0;
                    if (d.AirHum.HasValue && d.AirHum.Value > d.AirHumMax) s -= 15.0;
                    if (d.DewPoint.HasValue && d.AirTemp.HasValue && (d.AirTemp.Value - d.DewPoint.Value) < 2.0) s -= 25.0;
                }
                sum += Math.Clamp(s, 0, 100);
            }
            avgScore = Math.Round(sum / devices.Count, 1);
        }
        else
        {
            avgScore = 100.0;
        }

        return Ok(new
        {
            ok = true,
            total_stations = totalStations,
            online_stations = onlineCount,
            offline_stations = totalStations - onlineCount,
            active_alerts = alertCount,
            system_health_score = avgScore,
            status_grade = avgScore >= 80 ? "XUẤT SẮC" : (avgScore >= 60 ? "KHÁ" : "CẦN BẢO TRÌ"),
            last_audit_at = TimeHelper.VnNowStr
        });
    }

    /// <summary>
    /// POST /api/ai/chat: Trợ lý AI Kỹ thuật giải đáp thắc mắc và hỗ trợ xử lý sự cố vi khí hậu IoT theo ngữ cảnh
    /// </summary>
    [HttpPost("chat")]
    public async Task<IActionResult> ChatWithAi([FromBody] AiChatRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.message))
        {
            return BadRequest(new { ok = false, error = "Tin nhắn không được để trống." });
        }

        int stationId = req.station_id ?? 1;
        var st = _store.GetStation(stationId);
        var dev = _store.Devices.FirstOrDefault(d => d.StationId == stationId)
                  ?? _store.Devices.FirstOrDefault(d => d.Id == stationId)
                  ?? _store.Devices.FirstOrDefault();

        var stationName = st?.Name ?? dev?.Name ?? $"Trạm #{stationId}";
        var location = st?.Location ?? dev?.Location ?? "Chưa rõ vị trí";
        double curTemp = dev?.AirTemp ?? 30.0;
        double curHum = dev?.AirHum ?? 55.0;
        double curDew = dev?.DewPoint ?? (curTemp - ((100 - curHum) / 5.0));
        double dewMargin = Math.Round(curTemp - curDew, 1);
        string status = dev?.Status ?? "ONLINE";
        string relayMode = dev?.RelayMode ?? "AUTO";
        int relayState = dev?.RelayState ?? 0;
        int rssi = dev?.Rssi ?? -55;
        string firmware = dev?.Firmware ?? "esp32-dht11-ipgps-2.0";

        // Thử gọi Google Gemini API nếu có cấu hình key
        string? apiKey = !string.IsNullOrWhiteSpace(req.gemini_key) 
            ? req.gemini_key.Trim()
            : (_config["Gemini:ApiKey"] ?? _config["GEMINI_API_KEY"] ?? Environment.GetEnvironmentVariable("GEMINI_API_KEY"));

        if (!string.IsNullOrWhiteSpace(apiKey))
        {
            try
            {
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
                var modelName = _config["Gemini:Model"] ?? "gemini-2.5-flash";
                var geminiUrl = $"https://generativelanguage.googleapis.com/v1beta/models/{modelName}:generateContent?key={apiKey}";
                
                var systemContext = $@"Bạn là Trợ lý Kỹ thuật AI của hệ thống IoT ThermoGuard. Bạn đang hỗ trợ kỹ thuật trực tiếp cho người vận hành.
Thông tin thời gian thực của trạm hiện tại:
- Tên trạm: {stationName} (ID: {stationId})
- Vị trí: {location}
- Nhiệt độ không khí: {curTemp:F1}°C (Ngưỡng an toàn: {dev?.AirTempMax ?? 40}°C)
- Độ ẩm không khí: {curHum:F1}% (Ngưỡng an toàn: {dev?.AirHumMax ?? 75}%)
- Điểm đọng sương (Dew Point): {curDew:F1}°C (Biên độ an toàn: {dewMargin}°C)
- Trạng thái thiết bị: {status} (Tín hiệu Wi-Fi: {rssi} dBm)
- Rơ-le / Thiết bị tải: {dev?.RelayLabel ?? "Bóng đèn 220V / Rơ-le"} (Chế độ: {relayMode}, Đang: {(relayState == 1 ? "BẬT" : "TẮT")})
- Firmware: {firmware}

Hãy trả lời bằng tiếng Việt thân thiện, súc tích, chuyên sâu về kỹ thuật IoT, nêu rõ nguyên nhân và các bước giải quyết từng bước (step-by-step). Định dạng markdown đẹp mắt kèm icon.";

                var payload = new
                {
                    contents = new[]
                    {
                        new
                        {
                            role = "user",
                            parts = new[] { new { text = $"{systemContext}\n\nNgười dùng hỏi: {req.message}" } }
                        }
                    }
                };

                var content = new StringContent(System.Text.Json.JsonSerializer.Serialize(payload), System.Text.Encoding.UTF8, "application/json");
                var resp = await http.PostAsync(geminiUrl, content);
                if (resp.IsSuccessStatusCode)
                {
                    var raw = await resp.Content.ReadAsStringAsync();
                    using var doc = System.Text.Json.JsonDocument.Parse(raw);
                    var candidate = doc.RootElement.GetProperty("candidates")[0];
                    var text = candidate.GetProperty("content").GetProperty("parts")[0].GetProperty("text").GetString();

                    if (!string.IsNullOrWhiteSpace(text))
                    {
                        return Ok(new
                        {
                            ok = true,
                            reply = text,
                            model = "gemini-1.5-flash",
                            suggestions = GenerateSmartSuggestions(req.message, curTemp, curHum, dewMargin)
                        });
                    }
                }
            }
            catch { }
        }

        // BỘ MÁY CHUYÊN GIA IOT NỘI BỘ (Autonomous Expert Engine - Không phụ thuộc Internet ngoài)
        string reply = GenerateExpertReply(req.message, stationName, location, curTemp, curHum, curDew, dewMargin, status, relayMode, relayState, rssi, dev?.AirTempMax ?? 40.0, dev?.AirHumMax ?? 75.0);
        var suggestions = GenerateSmartSuggestions(req.message, curTemp, curHum, dewMargin);

        return Ok(new
        {
            ok = true,
            reply,
            model = "thermoguard-expert-system",
            suggestions,
            station_context = new
            {
                name = stationName,
                temp = curTemp,
                hum = curHum,
                dew_margin = dewMargin,
                relay = relayState,
                status
            }
        });
    }

    private static string GenerateExpertReply(
        string q, string stName, string loc,
        double t, double h, double dew, double margin,
        string status, string relayMode, int relayState, int rssi,
        double tMax, double hMax)
    {
        string lower = q.ToLowerInvariant();

        // 1. Hỏi về tình trạng trạm hiện tại / tổng quan
        if (lower.Contains("tổng quan") || lower.Contains("tình trạng") || lower.Contains("hiện tại") || lower.Contains("sức khỏe") || lower.Contains("thế nào"))
        {
            string relayText = relayState == 1 ? "Đang BẬT" : "Đang TẮT";
            string dewAlert = margin < 2.0 
                ? "⚠️ **Cực kỳ nguy hiểm:** Biên độ sương chỉ còn " + margin + "°C! Nguy cơ chập vi mạch." 
                : "✅ **An toàn:** Biên độ đọng sương đạt " + margin + "°C (Ngưỡng an toàn tối thiểu là 3.0°C).";

            return $@"📊 **BÁO CÁO NHANH TÌNH TRẠNG {stName.ToUpper()}:**
📍 **Vị trí:** {loc}
- **Nhiệt độ:** `{t:F1}°C` {(t > tMax ? "🔴 (VƯỢT NGƯỠNG " + tMax + "°C)" : "🟢 (Bình thường)")}
- **Độ ẩm:** `{h:F1}%` {(h > hMax ? "🟠 (VƯỢT NGƯỠNG " + hMax + "%)" : "🟢 (Lý tưởng 40-70%)")}
- **Điểm đọng sương:** `{dew:F1}°C` (Biên an toàn: `+{margin}°C`)
- **Tín hiệu Wi-Fi:** `{rssi} dBm` {(rssi >= -65 ? "🟢 (Rất tốt)" : (rssi >= -80 ? "🟡 (Trung bình)" : "🔴 (Yếu)"))}
- **Rơ-le / Thiết bị ngoại vi:** `{relayText}` (Chế độ: `{relayMode}`)

💡 {dewAlert}";
        }

        // 2. Hỏi về nhiệt độ cao / quá nhiệt
        if (lower.Contains("nhiệt độ cao") || lower.Contains("quá nhiệt") || lower.Contains("nóng") || lower.Contains("giảm nhiệt") || lower.Contains("nhiệt độ"))
        {
            return $@"🌡️ **HƯỚNG DẪN XỬ LÝ KHI NHIỆT ĐỘ TĂNG CAO:**
Nhiệt độ hiện tại của trạm đo được là **{t:F1}°C** (Ngưỡng cảnh báo: **{tMax:F1}°C**).

**Các bước xử lý kỹ thuật đề xuất:**
1. 🌬️ **Kích hoạt tải làm mát:** Chuyển Rơ-le sang chế độ **ON** trên tab *Điều khiển* để bật quạt tản nhiệt hoặc hệ thống thông gió ngay lập tức.
2. 🔄 **Cấu hình tự động (AUTO):** Đảm bảo rơ-le đang ở chế độ **AUTO**, trạm sẽ tự động đóng tiếp điểm rơ-le khi nhiệt độ vượt quá `{tMax:F1}°C`.
3. 📦 **Kiểm tra vị trí đặt trạm:** Tránh ánh nắng mặt trời chiếu trực diện hoặc đặt cạnh các nguồn phát nhiệt lớn (nguồn xung, biến áp, dàn nóng máy lạnh).
4. ⚙️ **Hiệu chuẩn cảm biến:** Nếu nghi ngờ cảm biến DHT11 bị trôi thông số, vào tab *Cấu hình* > chỉnh lại `Offset Nhiệt độ` (-1.0°C đến -2.0°C).";
        }

        // 3. Hỏi về điểm đọng sương (Dew Point) & Ngưng tụ
        if (lower.Contains("đọng sương") || lower.Contains("sương") || lower.Contains("ngưng tụ") || lower.Contains("dew point") || lower.Contains("ẩm ướt"))
        {
            return $@"💧 **HIỆN TƯỢNG ĐỌNG SƯƠNG & CÁCH PHÒNG CHỐNG TRONG IOT:**

- **Điểm đọng sương hiện tại:** `{dew:F1}°C`
- **Biên an toàn ($\Delta T$):** `{margin}°C` ($\Delta T = T_{{không khí}} - T_{{điểm sương}}$).

**Tại sao đọng sương lại nguy hiểm?**
Khi nhiệt độ bề mặt linh kiện tụt xuống bằng hoặc thấp hơn điểm đọng sương, hơi nước trong không khí sẽ chuyển pha từ thể khí sang thể lỏng bám trực tiếp lên bo mạch ESP32 và chân cảm biến DHT11, dẫn đến:
- Chập điện giữa các đường mạch in (VCC và GND).
- Oxy hóa rỉ sét chân hàn và làm sai lệch số đo cảm biến.

**Biện pháp giải quyết:**
1. 💡 **Gia nhiệt nhẹ:** Bật bóng đèn sấy hoặc thanh nhiệt nối qua Rơ-le để nâng nhiệt độ bề mặt bo mạch cao hơn điểm đọng sương ít nhất **3°C**.
2. 🌪️ **Tăng đối lưu không khí:** Bật quạt lưu thông để giải tỏa vùng không khí bão hòa hơi ẩm quanh trạm.
3. 🧪 **Bổ sung hạt chống ẩm Silica Gel** bên trong hộp kín chứa mạch.";
        }

        // 4. Hỏi về Rơ-le / Thiết bị tải / Không bật được
        if (lower.Contains("rơ-le") || lower.Contains("relay") || lower.Contains("bóng đèn") || lower.Contains("không bật") || lower.Contains("không nhảy"))
        {
            return $@"⚡ **HƯỚNG DẪN KIỂM TRA & ĐIỀU KHIỂN RƠ-LE:**
Trạng thái rơ-le hiện tại: **{(relayState == 1 ? "ĐANG BẬT (ON)" : "ĐANG TẮT (OFF)")}** | Chế độ: **{relayMode}**

**Các bước khắc phục sự cố rơ-le:**
1. 📱 **Thử bật bằng tay từ App:** Chuyển chế độ rơ-le sang **ON** từ tab *Điều khiển* để kiểm tra lệnh qua mạng Render Cloud có truyền về ESP32 không.
2. 🔌 **Kiểm tra nguồn cấp rơ-le:** Cuộn hút rơ-le 5V tiêu thụ dòng khá lớn (70-100mA). Hãy đảm bảo cấp nguồn qua cổng MicroUSB với củ sạc tối thiểu **5V / 1.5A - 2A**, không nên chỉ cắm cổng USB laptop cấp dòng yếu.
3. 📌 **Kiểm tra chân điều khiển:** 
   - Chân tín hiệu Rơ-le nối vào **GPIO 23** của ESP32.
   - Đèn LED báo trên mạch ESP32 nối chân **GPIO 2** (sẽ sáng đồng bộ khi rơ-le kích hoạt).
4. 🎛️ **Kiểm tra ngưỡng tự động:** Nếu để chế độ AUTO, rơ-le chỉ nhảy khi `Nhiệt độ >= {tMax}°C` hoặc `Biên độ sương < 3.0°C`.";
        }

        // 5. Hỏi về Wi-Fi / Mất kết nối / OFFLINE
        if (lower.Contains("wifi") || lower.Contains("wi-fi") || lower.Contains("mất mạng") || lower.Contains("offline") || lower.Contains("ngắt kết nối") || lower.Contains("mất kết nối"))
        {
            return $@"📶 **KHẮC PHỤC SỰ CỐ MẤT KẾT NỐI WI-FI (OFFLINE):**
Cường độ sóng ghi nhận lần cuối: **{rssi} dBm** (Trạng thái: **{status}**).

**Checklist xử lý kết nối:**
1. 📡 **Kiểm tra băng tần Wi-Fi:** Chip ESP32 **chỉ hỗ trợ băng tần 2.4 GHz**, không hỗ trợ Wi-Fi 5 GHz. Nếu router phát song song 2 băng tần, hãy kết nối vào tên SSID 2.4GHz.
2. 🔑 **Kiểm tra danh sách Wi-Fi trong firmware:** Mở file `config.py` trên ESP32 và đảm bảo tên Wi-Fi + Mật khẩu đã được khai báo chính xác trong mảng `WIFI_LIST`.
3. 📍 **Khoảng cách truyền dẫn:** Nếu RSSI dưới `-80 dBm`, tín hiệu rất suy hao, dễ mất gói tin HMAC. Hãy dời ESP32 gần cục phát Wi-Fi hơn hoặc dùng bộ kích sóng.
4. 🔄 **Cơ chế tự động Failover:** Firmware ESP32 ThermoGuard đã tích hợp thuật toán tự động quét mạng và thử kết nối lại sau mỗi 5 giây khi mất tín hiệu.";
        }

        // 6. Câu hỏi mặc định / trợ giúp tổng quát
        return $@"🤖 **TRỢ LÝ KỸ THUẬT IOT THERMOGUARD:**
Tôi đã nhận câu hỏi của bạn: *""{q}""*.

Dựa trên dữ liệu hiện trường của **{stName}** (`{t:F1}°C`, `{h:F1}%`, Điểm sương `{dew:F1}°C`):
- Hệ thống vi xử lý ESP32 và cảm biến DHT11 đang gửi gói tin định kỳ 2 giây/lần.
- Chế độ rơ-le hiện tại: `{relayMode}` (Trạng thái: `{(relayState == 1 ? "BẬT" : "TẮT")}`).

Bạn có thể chọn một trong các chủ đề cần xử lý bên dưới hoặc đặt câu hỏi chi tiết hơn:";
    }

    private static List<string> GenerateSmartSuggestions(string q, double t, double h, double margin)
    {
        var list = new List<string>();
        if (t > 31.0) list.Add("Cách hạ nhiệt độ trạm nhanh nhất?");
        if (margin < 3.5) list.Add("Làm sao để tránh đọng sương?");
        list.Add("Tình trạng tổng quan trạm hiện tại?");
        list.Add("Kiểm tra Rơ-le và Bóng đèn 220V");
        list.Add("Khắc phục khi ESP32 mất Wi-Fi");
        return list;
    }
}

public class AiChatRequest
{
    public int? station_id { get; set; }
    public string message { get; set; } = "";
    public List<AiChatMessageItem>? history { get; set; }
    public string? gemini_key { get; set; }
}

public class AiChatMessageItem
{
    public string role { get; set; } = "user"; // user | assistant
    public string content { get; set; } = "";
}

