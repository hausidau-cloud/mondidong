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
            if (curUser != null && curUser.Role == "viewer")
            {
                var allowedStationIds = _store.GetStationIdsForUser(curUser.Id);
                var isAllowed = allowedStationIds.Contains(dev.Id) || (dev.StationId.HasValue && allowedStationIds.Contains(dev.StationId.Value));
                if (!isAllowed)
                {
                    return Forbid();
                }
            }

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
}
