using System.Globalization;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Tags("Control")]
[Route("api/control")]
public class ControlController : ControllerBase
{
    private readonly DataStore _store;

    public ControlController(DataStore store)
    {
        _store = store;
    }

    private AppUser? GetCurrentUser()
    {
        var authHeader = Request.Headers.Authorization.ToString();
        if (authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            var token = authHeader["Bearer ".Length..].Trim();
            if (_store.ActiveSessions.TryGetValue(token, out var user)) return user;
        }
        return null;
    }

    private static double? ReadDouble(JsonNode? node)
    {
        if (node == null) return null;
        var s = node.ToString().Trim();
        if (double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var v))
            return v;
        return null;
    }

    private static int? ReadInt(JsonNode? node)
    {
        if (node == null) return null;
        var s = node.ToString().Trim();
        if (int.TryParse(s, out var v))
            return v;
        if (double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var dv))
            return (int)Math.Round(dv);
        return null;
    }

    [HttpPost]
    public IActionResult Post([FromQuery] string? action, [FromBody] JsonObject? body)
    {
        var act = action?.ToLowerInvariant() ?? "";
        var devId = ReadInt(body?["device_id"]) ?? 1;
        var dev = _store.GetDevice(devId) ?? _store.Devices.FirstOrDefault(d => d.StationId == devId);
        if (dev == null)
        {
            return NotFound(new { ok = false, error = "Không tìm thấy thiết bị" });
        }

        var curUser = GetCurrentUser();

        if (act == "relay")
        {
            var mode = body?["mode"]?.ToString().ToUpperInvariant() ?? "AUTO";
            if (mode != "AUTO" && mode != "ON" && mode != "OFF") mode = "AUTO";

            dev.RelayMode = mode;
            if (mode == "ON") dev.RelayState = 1;
            if (mode == "OFF") dev.RelayState = 0;

            _store.AddRelayLog(new Models.RelayLogItem
            {
                DeviceId = dev.Id,
                StationId = dev.StationId ?? dev.Id,
                Action = mode == "ON" ? "ON" : (mode == "OFF" ? "OFF" : "AUTO"),
                Source = "MANUAL",
                Reason = $"Đổi chế độ {mode} từ App Flutter",
                FullName = curUser?.FullName ?? "Quản trị viên",
                CreatedAt = TimeHelper.VnNowStr
            });

            _store.UpdateDevice(dev);

            return Ok(new
            {
                ok = true,
                note = "Pico sẽ nhận lệnh ở lần gửi dữ liệu kế tiếp"
            });
        }

        if (act == "oled")
        {
            var msg = body?["msg"]?.ToString() ?? "";
            dev.OledMsg = msg.Length > 21 ? msg[..21] : msg;
            _store.UpdateDevice(dev);

            return Ok(new
            {
                ok = true,
                msg = dev.OledMsg,
                note = "Hiển thị trên OLED ở lần gửi dữ liệu kế tiếp"
            });
        }

        if (act == "thresholds")
        {
            var airTempMax = ReadDouble(body?["air_temp_max"]);
            if (airTempMax.HasValue) dev.AirTempMax = airTempMax.Value;

            var airHumMax = ReadDouble(body?["air_hum_max"]);
            if (airHumMax.HasValue) dev.AirHumMax = airHumMax.Value;

            var probeTempMin = ReadDouble(body?["probe_temp_min"]);
            if (probeTempMin.HasValue) dev.ProbeTempMin = probeTempMin.Value;

            var probeTempMax = ReadDouble(body?["probe_temp_max"]);
            if (probeTempMax.HasValue) dev.ProbeTempMax = probeTempMax.Value;

            var dewMargin = ReadDouble(body?["dew_margin"]);
            if (dewMargin.HasValue) dev.DewMargin = dewMargin.Value;

            var hysteresis = ReadDouble(body?["hysteresis"]);
            if (hysteresis.HasValue) dev.Hysteresis = hysteresis.Value;

            var offsetAir = ReadDouble(body?["offset_air"]);
            if (offsetAir.HasValue) dev.OffsetAir = offsetAir.Value;

            var offsetProbe = ReadDouble(body?["offset_probe"]);
            if (offsetProbe.HasValue) dev.OffsetProbe = offsetProbe.Value;

            var offlineAfter = ReadInt(body?["offline_after"]);
            if (offlineAfter.HasValue && offlineAfter.Value > 0) dev.OfflineAfter = offlineAfter.Value;

            _store.UpdateDevice(dev);

            return Ok(new { ok = true, message = "Cập nhật cấu hình ngưỡng thành công" });
        }

        if (act == "reveal_key")
        {
            return Ok(new
            {
                ok = true,
                device_code = dev.DeviceCode,
                api_key = dev.ApiKey,
                key_version = 1
            });
        }

        return BadRequest(new { ok = false, error = "Hành động không hợp lệ" });
    }

    [HttpGet("schedule/{stationId}")]
    public IActionResult GetSchedules(int stationId)
    {
        var list = _store.GetActiveSchedules(stationId);
        return Ok(new
        {
            ok = true,
            schedules = list
        });
    }

    [HttpPost("schedule")]
    public IActionResult CreateSchedule([FromBody] JsonObject? body)
    {
        var stId = ReadInt(body?["station_id"]) ?? 1;
        var devId = ReadInt(body?["device_id"]);
        var dev = devId.HasValue 
            ? _store.GetDevice(devId.Value) 
            : (_store.Devices.FirstOrDefault(d => d.StationId == stId) ?? _store.GetDevice(stId));

        if (dev == null)
            return NotFound(new { ok = false, error = "Không tìm thấy thiết bị" });

        var minutes = ReadInt(body?["minutes"]) ?? 15;
        var targetMode = body?["target_mode"]?.ToString().ToUpperInvariant() ?? "OFF";
        var type = body?["type"]?.ToString().ToUpperInvariant() ?? "COUNTDOWN";

        var sched = _store.AddSchedule(stId, dev.Id, type, targetMode, minutes);

        return Ok(new
        {
            ok = true,
            message = $"Đã lên lịch hẹn giờ: Chuyển Rơ-le sang {targetMode} sau {minutes} phút",
            schedule = sched
        });
    }

    [HttpDelete("schedule/{scheduleId}")]
    public IActionResult CancelSchedule(int scheduleId)
    {
        var ok = _store.CancelSchedule(scheduleId);
        return Ok(new
        {
            ok,
            message = ok ? "Đã hủy lịch hẹn giờ" : "Không tìm thấy lịch hẹn giờ"
        });
    }

    /// <summary>
    /// GET /api/control/actuators/{stationId}: Danh sách 5 thiết bị chấp hành ngoại vi (Phun sương, Quạt, Đèn sấy, Bơm tưới, Còi hú)
    /// </summary>
    [HttpGet("actuators/{stationId}")]
    public IActionResult GetActuators(int stationId)
    {
        var list = _store.GetStationActuators(stationId);
        return Ok(new
        {
            ok = true,
            station_id = stationId,
            actuators = list
        });
    }

    /// <summary>
    /// POST /api/control/actuator: Điều khiển thiết bị chấp hành (Bật/Tắt, Chế độ Tự động/Thủ công, Cấp độ)
    /// </summary>
    [HttpPost("actuator")]
    public IActionResult UpdateActuator([FromBody] JsonObject? body)
    {
        var stId = ReadInt(body?["station_id"]) ?? 1;
        var actId = body?["actuator_id"]?.ToString()?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(actId))
        {
            return BadRequest(new { ok = false, error = "Mã thiết bị chấp hành không được để trống" });
        }

        bool? state = null;
        if (body?["state"] != null)
        {
            state = body["state"]!.ToString().ToLowerInvariant() == "true" || body["state"]!.ToString() == "1";
        }

        var mode = body?["mode"]?.ToString()?.ToUpperInvariant();
        var level = ReadInt(body?["level"]);

        var curUser = GetCurrentUser();
        var operatorName = curUser?.FullName ?? "Quản trị viên";

        var updated = _store.UpdateActuator(stId, actId, state, mode, level, operatorName);
        if (updated == null)
        {
            return NotFound(new { ok = false, error = $"Không tìm thấy thiết bị chấp hành '{actId}'" });
        }

        return Ok(new
        {
            ok = true,
            message = $"Đã cập nhật {updated.Name}: {(updated.State ? "BẬT" : "TẮT")} (Chế độ {updated.Mode}, Cấp {updated.Level})",
            actuator = updated
        });
    }

    /// <summary>
    /// POST /api/control/actuator/test: Kích hoạt test tức thì thiết bị ngoại vi trong N giây (Ví dụ: Test còi hú, Phun sương test)
    /// </summary>
    [HttpPost("actuator/test")]
    public IActionResult TestActuator([FromBody] JsonObject? body)
    {
        var stId = ReadInt(body?["station_id"]) ?? 1;
        var actId = body?["actuator_id"]?.ToString()?.Trim() ?? "siren";
        var duration = ReadInt(body?["duration_seconds"]) ?? 5;
        if (duration < 1) duration = 5;
        if (duration > 60) duration = 60;

        var curUser = GetCurrentUser();
        var operatorName = curUser?.FullName ?? "Quản trị viên";

        // 1. Bat test
        var item = _store.UpdateActuator(stId, actId, true, "MANUAL", 3, $"{operatorName} (TEST {duration}s)");
        if (item == null)
        {
            return NotFound(new { ok = false, error = $"Không tìm thấy thiết bị '{actId}'" });
        }

        // 2. Tu dong tat sau N giay
        Task.Run(async () =>
        {
            try
            {
                await Task.Delay(duration * 1000);
                _store.UpdateActuator(stId, actId, false, "AUTO", 1, "Hệ thống (Kết thúc TEST)");
            }
            catch { }
        });

        return Ok(new
        {
            ok = true,
            message = $"Đang kích hoạt TEST {item.Name} trong {duration} giây...",
            actuator = item,
            duration_seconds = duration
        });
    }
}
