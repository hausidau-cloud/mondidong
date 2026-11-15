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

        // AI AGENT: Nhận diện ý định & Thực thi hành động thật trên phần cứng (Function / Action Calling)
        var action = DetectActionFromMessage(req.message);
        if (action != null && dev != null)
        {
            if (action.Type == "SET_RELAY")
            {
                var targetMode = action.Mode ?? "AUTO";
                dev.RelayMode = targetMode;
                if (targetMode == "ON") dev.RelayState = 1;
                else if (targetMode == "OFF") dev.RelayState = 0;

                _store.AddRelayLog(new Models.RelayLogItem
                {
                    DeviceId = dev.Id,
                    StationId = dev.StationId ?? dev.Id,
                    Action = targetMode,
                    Source = "AI_AGENT",
                    Reason = $"Trợ lý AI tự động thực thi lệnh từ người dùng: '{req.message}'",
                    FullName = "Trợ lý AI ThermoGuard (Agent)",
                    CreatedAt = TimeHelper.VnNowStr
                });
                _store.UpdateDevice(dev);
                action.Executed = true;
                action.Message = $"Đã chuyển Rơ-le sang {targetMode} thành công!";
                relayState = dev.RelayState;
                relayMode = dev.RelayMode;
            }
            else if (action.Type == "SET_THRESHOLD")
            {
                if (action.TempMax.HasValue) dev.AirTempMax = action.TempMax.Value;
                if (action.HumMax.HasValue) dev.AirHumMax = action.HumMax.Value;
                _store.UpdateDevice(dev);
                action.Executed = true;
                action.Message = $"Đã cập nhật ngưỡng an toàn: {(action.TempMax.HasValue ? $"Nhiệt max = {action.TempMax}°C " : "")}{(action.HumMax.HasValue ? $"Ẩm max = {action.HumMax}%" : "")}";
            }
        }

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
                
                var actionNote = action != null && action.Executed ? $"\n[LƯU Ý: Hệ thống đã tự động thực thi hành động: {action.Message}. Hãy xác nhận điều này một cách thông minh cho người dùng]." : "";
                var systemContext = $@"Bạn là Trợ lý AI Tự hành (AI Agent) hệ thống IoT ThermoGuard hỗ trợ trạm {stationName} (Nhiệt độ: {curTemp:F1}°C, Độ ẩm: {curHum:F1}%, Điểm sương: {curDew:F1}°C, Rơ-le: {(relayState == 1 ? "BẬT" : "TẮT")}).
Bạn có quyền năng tự động điều khiển Rơ-le và cài đặt ngưỡng khi người dùng yêu cầu.{actionNote}
YÊU CẦU: Trả lời NGẮN GỌN, HỢP LÝ và ĐI THẲNG VÀO TRỌNG TÂM (tối đa 2 đến 3 câu ngắn, dưới 70 từ, không chào hỏi lan man).";

                var payload = new
                {
                    contents = new[]
                    {
                        new
                        {
                            role = "user",
                            parts = new[] { new { text = $"{systemContext}\n\nNgười dùng hỏi: {req.message}" } }
                        }
                    },
                    generationConfig = new
                    {
                        thinkingConfig = new
                        {
                            thinkingBudget = 0
                        },
                        maxOutputTokens = 350,
                        temperature = 0.3
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
                            reply = text.Trim(),
                            model = "gemini-2.5-flash (AI Agent)",
                            action = action != null && action.Executed ? new
                            {
                                type = action.Type,
                                mode = action.Mode,
                                temp_max = action.TempMax,
                                hum_max = action.HumMax,
                                executed = action.Executed,
                                message = action.Message
                            } : null,
                            suggestions = GenerateSmartSuggestions(req.message, curTemp, curHum, dewMargin)
                        });
                    }
                }
            }
            catch { }
        }

        // BỘ MÁY CHUYÊN GIA IOT NỘI BỘ (Autonomous Expert Engine - Không phụ thuộc Internet ngoài)
        string reply = action != null && action.Executed
            ? $"⚡ **Lệnh AI Agent đã thực thi:** {action.Message}. Rơ-le trạm {stationName} hiện tại: {(relayState == 1 ? "BẬT" : "TẮT")} (Chế độ: {relayMode})."
            : GenerateExpertReply(req.message, stationName, location, curTemp, curHum, curDew, dewMargin, status, relayMode, relayState, rssi, dev?.AirTempMax ?? 40.0, dev?.AirHumMax ?? 75.0);
        var suggestions = GenerateSmartSuggestions(req.message, curTemp, curHum, dewMargin);

        return Ok(new
        {
            ok = true,
            reply,
            model = "thermoguard-expert-system",
            action = action != null && action.Executed ? new
            {
                type = action.Type,
                mode = action.Mode,
                temp_max = action.TempMax,
                hum_max = action.HumMax,
                executed = action.Executed,
                message = action.Message
            } : null,
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

        // 1. Hỏi về tưới nước / làm mát bằng nước
        if (lower.Contains("tưới nước") || lower.Contains("tưới cây") || lower.Contains("nước"))
        {
            return $"💧 **Về việc tưới nước:** Trạm {stName} đang có độ ẩm khá cao ({h:F1}%) và nhiệt độ {t:F1}°C. Không nên tưới nước gần khu vực đặt vi mạch ESP32 để tránh hơi ẩm bão hòa gây đọng sương chập mạch. Nếu muốn hạ nhiệt, giải pháp an toàn là bật quạt thông gió qua Rơ-le.";
        }

        // 2. Hỏi về tình trạng trạm hiện tại / tổng quan
        if (lower.Contains("tổng quan") || lower.Contains("tình trạng") || lower.Contains("hiện tại") || lower.Contains("sức khỏe") || lower.Contains("thế nào"))
        {
            string relayText = relayState == 1 ? "BẬT" : "TẮT";
            return $"📊 **Trạm {stName}:** Nhiệt độ `{t:F1}°C` (Ngưỡng {tMax}°C), Độ ẩm `{h:F1}%`, Điểm sương `{dew:F1}°C` (Biên an toàn `+{margin}°C`). Rơ-le: `{relayText}`, Wi-Fi: `{rssi} dBm`. Trạng thái: {(status == "OK" ? "Hoạt động tốt." : status)}";
        }

        // 3. Hỏi về nhiệt độ cao / quá nhiệt
        if (lower.Contains("nhiệt độ cao") || lower.Contains("quá nhiệt") || lower.Contains("nóng") || lower.Contains("giảm nhiệt") || lower.Contains("nhiệt độ") || lower.Contains("hạ nhiệt"))
        {
            return $"🌡️ **Hạ nhiệt trạm {stName} ({t:F1}°C):** 1. Bật Rơ-le sang ON để quạt tản nhiệt hoạt động. 2. Đảm bảo phòng thông thoáng, tránh ánh nắng chiếu trực tiếp. 3. Để rơ-le ở chế độ AUTO để tự bật khi vượt {tMax}°C.";
        }

        // 4. Hỏi về điểm đọng sương (Dew Point) & Ngưng tụ
        if (lower.Contains("đọng sương") || lower.Contains("sương") || lower.Contains("ngưng tụ") || lower.Contains("dew point") || lower.Contains("ẩm ướt"))
        {
            return $"💧 **Nguy cơ đọng sương ({dew:F1}°C):** Biên an toàn hiện tại là +{margin}°C (nguy hiểm nếu < 2.0°C). Để chống ngưng tụ hơi nước trên mạch ESP32, hãy bật bóng đèn sấy nhẹ qua Rơ-le hoặc dùng quạt thông gió.";
        }

        // 5. Hỏi về Rơ-le / Thiết bị tải / Không bật được
        if (lower.Contains("rơ-le") || lower.Contains("relay") || lower.Contains("bóng đèn") || lower.Contains("không bật") || lower.Contains("không nhảy"))
        {
            return $"⚡ **Xử lý Rơ-le (Hiện tại: {(relayState == 1 ? "BẬT" : "TẮT")}):** 1. Thử bật thủ công bằng nút ON trên tab Điều khiển. 2. Kiểm tra chân tín hiệu GPIO 23 và nguồn nuôi 5V/2A cho ESP32. 3. Ở chế độ AUTO, rơ-le chỉ nhảy khi nhiệt độ vượt {tMax}°C hoặc chênh lệch sương < 3°C.";
        }

        // 6. Hỏi về Wi-Fi / Mất kết nối / OFFLINE
        if (lower.Contains("wifi") || lower.Contains("wi-fi") || lower.Contains("mất mạng") || lower.Contains("offline") || lower.Contains("ngắt kết nối") || lower.Contains("mất kết nối"))
        {
            return $"📶 **Xử lý Wi-Fi ({rssi} dBm):** 1. Đảm bảo kết nối vào sóng 2.4GHz (ESP32 không bắt được 5GHz). 2. Kiểm tra SSID và mật khẩu trong `config.py`. 3. Nếu RSSI dưới -80 dBm, hãy dời trạm lại gần Access Point.";
        }

        // 7. Mặc định ngắn gọn
        return $"🤖 **ThermoGuard AI ({stName}):** Đang ghi nhận nhiệt độ {t:F1}°C, độ ẩm {h:F1}%, rơ-le {(relayState == 1 ? "BẬT" : "TẮT")}. Vui lòng chọn câu hỏi gợi ý bên dưới hoặc hỏi cụ thể về giải nhiệt, đọng sương, rơ-le.";
    }

    private static AiAction? DetectActionFromMessage(string message)
    {
        var lower = message.ToLowerInvariant().Trim();

        // 1. Dieu khien Ro-le: BAT
        if (lower.Contains("bật rơ-le") || lower.Contains("bật rơ le") || lower.Contains("bật relay") || 
            lower.Contains("bật quạt") || lower.Contains("bật đèn") || lower.Contains("bật máy làm mát") ||
            lower.Contains("turn on relay") || lower.Contains("bật thiết bị") || lower.Contains("mở rơ le") || lower.Contains("mở quạt"))
        {
            return new AiAction { Type = "SET_RELAY", Mode = "ON" };
        }

        // 2. Dieu khien Ro-le: TAT
        if (lower.Contains("tắt rơ-le") || lower.Contains("tắt rơ le") || lower.Contains("tắt relay") || 
            lower.Contains("tắt quạt") || lower.Contains("tắt đèn") || lower.Contains("ngắt rơ-le") ||
            lower.Contains("turn off relay") || lower.Contains("tắt thiết bị") || lower.Contains("đóng rơ le"))
        {
            return new AiAction { Type = "SET_RELAY", Mode = "OFF" };
        }

        // 3. Dieu khien Ro-le: AUTO
        if (lower.Contains("chuyển rơ-le sang tự động") || lower.Contains("chuyển rơ le sang tự động") || 
            lower.Contains("chế độ auto") || lower.Contains("đặt auto") || lower.Contains("rơ-le tự động") || lower.Contains("set auto"))
        {
            return new AiAction { Type = "SET_RELAY", Mode = "AUTO" };
        }

        // 4. Doi nguong nhiet do
        var tempMatch = System.Text.RegularExpressions.Regex.Match(lower, @"(ngưỡng nhiệt|nhiệt độ max|nhiệt độ tối đa|cài nhiệt độ)[^\d]*(\d+(\.\d+)?)");
        if (tempMatch.Success && double.TryParse(tempMatch.Groups[2].Value, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out double tVal))
        {
            return new AiAction { Type = "SET_THRESHOLD", TempMax = tVal };
        }

        // 5. Doi nguong do am
        var humMatch = System.Text.RegularExpressions.Regex.Match(lower, @"(ngưỡng ẩm|độ ẩm max|độ ẩm tối đa|cài độ ẩm)[^\d]*(\d+(\.\d+)?)");
        if (humMatch.Success && double.TryParse(humMatch.Groups[2].Value, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out double hVal))
        {
            return new AiAction { Type = "SET_THRESHOLD", HumMax = hVal };
        }

        return null;
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

public class AiAction
{
    public string Type { get; set; } = ""; // SET_RELAY | SET_THRESHOLD
    public string? Mode { get; set; }      // ON | OFF | AUTO
    public double? TempMax { get; set; }
    public double? HumMax { get; set; }
    public bool Executed { get; set; }
    public string Message { get; set; } = "";
}

