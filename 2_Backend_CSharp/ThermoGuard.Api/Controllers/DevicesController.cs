using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

public class DeviceCreateRequest
{
    public string device_code { get; set; } = "PICO-02";
    public string name { get; set; } = "Thiết bị Pico 2 W số 2";
    public int? station_id { get; set; }
    public string? location { get; set; } = "Phòng Thực Nghiệm IoT";
    public string? relay_label { get; set; } = "Bóng đèn 220V / Rơ-le";
    public string? description { get; set; }
    public string? api_key { get; set; }
}

public class DeviceUpdateRequest
{
    public string? name { get; set; }
    public int? station_id { get; set; }
    public string? location { get; set; }
    public string? relay_label { get; set; }
    public string? description { get; set; }
}

[ApiController]
[Tags("Devices")]
[Route("api/devices")]
public class DevicesController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly DataStore _store;

    public DevicesController(AppDbContext db, DataStore store)
    {
        _db = db;
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

    /// <summary>
    /// GET /api/devices: Lấy danh sách thiết bị phần cứng IoT
    /// </summary>
    [HttpGet]
    public IActionResult Get([FromQuery] int? id)
    {
        if (id.HasValue)
        {
            var dev = _store.GetDevice(id.Value);
            if (dev == null)
            {
                return NotFound(new { ok = false, error = "Không tìm thấy thiết bị" });
            }

            var devDict = BuildDevicePublic(dev);
            devDict["spark"] = _store.GetSpark(dev.Id);
            devDict["stats24h"] = _store.GetStats24h(dev.Id);
            devDict["relay_logs"] = _store.RelayLogs.Where(l => l.DeviceId == dev.Id || (l.DeviceId == null && l.StationId == null)).Take(30).ToList();

            return Ok(new { ok = true, device = devDict });
        }

        var list = _store.Devices.Select(d =>
        {
            var item = BuildDevicePublic(d);
            item["spark"] = _store.GetSpark(d.Id);
            return item;
        }).ToList();

        return Ok(new { ok = true, total = list.Count, devices = list });
    }

    /// <summary>
    /// POST /api/devices: Thêm thiết bị phần cứng mới vào hệ thống (Admin only)
    /// </summary>
    [HttpPost]
    public IActionResult CreateDevice([FromBody] DeviceCreateRequest req)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        if (string.IsNullOrWhiteSpace(req.device_code) || string.IsNullOrWhiteSpace(req.name))
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập Mã thiết bị (device_code) và Tên thiết bị (name)" });
        }

        var code = req.device_code.Trim().ToUpperInvariant();
        if (_db.Devices.Any(d => d.DeviceCode.ToUpper() == code) || _store.Devices.Any(d => d.DeviceCode.ToUpper() == code))
        {
            return BadRequest(new { ok = false, error = $"Mã thiết bị '{code}' đã tồn tại trong hệ thống!" });
        }

        var apiKey = string.IsNullOrWhiteSpace(req.api_key) ? Guid.NewGuid().ToString("N") : req.api_key.Trim();
        var newDev = new Device
        {
            Id = 0,
            DeviceCode = code,
            ApiKey = apiKey,
            Name = req.name.Trim(),
            StationId = req.station_id,
            Location = string.IsNullOrWhiteSpace(req.location) ? "Phòng Lab" : req.location.Trim(),
            Profile = "cabinet",
            Description = string.IsNullOrWhiteSpace(req.description) ? "Thiết bị phần cứng IoT" : req.description.Trim(),
            RelayLabel = string.IsNullOrWhiteSpace(req.relay_label) ? "Rơ-le / Thiết bị" : req.relay_label.Trim(),
            RelayMode = "AUTO",
            RelayState = 0,
            Status = "OFFLINE",
            AirTempMax = 40.0,
            AirHumMax = 75.0,
            ProbeTempMin = 0.0,
            ProbeTempMax = 60.0,
            DewMargin = 3.0,
            Hysteresis = 1.5,
            SendInterval = 3,
            OfflineAfter = 60
        };

        _db.Devices.Add(newDev);
        _db.SaveChanges();

        _store.AddDevice(newDev);

        var pub = BuildDevicePublic(newDev);
        pub["api_key"] = newDev.ApiKey;

        return Ok(new
        {
            ok = true,
            message = $"Đã thêm thành công thiết bị '{newDev.Name}' ({newDev.DeviceCode})!",
            device = pub,
            api_key = newDev.ApiKey
        });
    }

    /// <summary>
    /// PUT /api/devices/{id}: Cập nhật thông tin thiết bị phần cứng (Admin only)
    /// </summary>
    [HttpPut("{id}")]
    public IActionResult UpdateDevice(int id, [FromBody] DeviceUpdateRequest req)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        var dev = _db.Devices.Find(id);
        if (dev == null) return NotFound(new { ok = false, error = "Không tìm thấy thiết bị" });

        if (!string.IsNullOrWhiteSpace(req.name)) dev.Name = req.name.Trim();
        if (req.station_id.HasValue) dev.StationId = req.station_id.Value > 0 ? req.station_id.Value : null;
        if (req.location != null) dev.Location = req.location.Trim();
        if (req.relay_label != null) dev.RelayLabel = req.relay_label.Trim();
        if (req.description != null) dev.Description = req.description.Trim();

        _db.SaveChanges();

        var storeDev = _store.GetDevice(id);
        if (storeDev != null)
        {
            storeDev.Name = dev.Name;
            storeDev.StationId = dev.StationId;
            storeDev.Location = dev.Location;
            storeDev.RelayLabel = dev.RelayLabel;
            storeDev.Description = dev.Description;
        }

        return Ok(new
        {
            ok = true,
            message = $"Đã cập nhật thiết bị '{dev.Name}' thành công!",
            device = BuildDevicePublic(dev)
        });
    }

    /// <summary>
    /// DELETE /api/devices/{id}: Xóa thiết bị phần cứng khỏi hệ thống (Admin only)
    /// </summary>
    [HttpDelete("{id}")]
    public IActionResult DeleteDevice(int id)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        var dev = _db.Devices.Find(id);
        var storeDev = _store.GetDevice(id);
        if (dev == null && storeDev == null)
        {
            return NotFound(new { ok = false, error = "Không tìm thấy thiết bị" });
        }

        if (dev != null)
        {
            var assigns = _db.StationAssignments.Where(a => a.DeviceId == id).ToList();
            if (assigns.Count > 0) _db.StationAssignments.RemoveRange(assigns);

            var readings = _db.Readings.Where(r => r.DeviceId == id).ToList();
            if (readings.Count > 0) _db.Readings.RemoveRange(readings);

            var alerts = _db.Alerts.Where(a => a.DeviceId == id).ToList();
            if (alerts.Count > 0) _db.Alerts.RemoveRange(alerts);

            _db.Devices.Remove(dev);
            _db.SaveChanges();
        }

        var devName = dev?.Name ?? storeDev?.Name ?? "Thiết bị";
        var devCode = dev?.DeviceCode ?? storeDev?.DeviceCode ?? "";

        _store.DeleteDevice(id);

        return Ok(new
        {
            ok = true,
            message = $"Đã xóa thành công thiết bị '{devName}' ({devCode})!"
        });
    }


    private Dictionary<string, object?> BuildDevicePublic(Device d)
    {
        return new Dictionary<string, object?>
        {
            ["id"] = d.Id,
            ["device_code"] = d.DeviceCode,
            ["name"] = d.Name,
            ["station_id"] = d.StationId,
            ["station_name"] = _store.GetStation(d.StationId ?? 0)?.Name ?? "Chưa gán trạm",
            ["profile"] = d.Profile,
            ["location"] = d.Location,
            ["description"] = d.Description,
            ["relay_label"] = d.RelayLabel,
            ["relay_mode"] = d.RelayMode,
            ["relay_state"] = d.RelayState,
            ["status"] = d.Status,
            ["online"] = d.Online,
            ["air_temp"] = d.AirTemp,
            ["air_hum"] = d.AirHum,
            ["dew_point"] = d.DewPoint,
            ["probe_temp"] = d.ProbeTemp,
            ["pico_temp"] = d.PicoTemp,
            ["light_raw"] = d.LightRaw,
            ["light_pct"] = d.LightPct,
            ["air_temp_max"] = d.AirTempMax,
            ["air_hum_max"] = d.AirHumMax,
            ["probe_temp_min"] = d.ProbeTempMin,
            ["probe_temp_max"] = d.ProbeTempMax,
            ["dew_margin"] = d.DewMargin,
            ["hysteresis"] = d.Hysteresis,
            ["offset_air"] = d.OffsetAir,
            ["offset_probe"] = d.OffsetProbe,
            ["offline_after"] = d.OfflineAfter,
            ["open_alerts"] = d.OpenAlerts,
            ["send_interval"] = d.SendInterval,
            ["rssi"] = d.Rssi,
            ["last_seen"] = d.LastSeen,
            ["firmware"] = d.Firmware,
            ["oled_msg"] = d.OledMsg,
            ["key_version"] = 1,
            ["ingest_auth"] = "hmac",
            ["api_key"] = d.ApiKey,
            ["viewer_ids"] = _store.GetUserIdsForStation(d.Id),
            ["viewers"] = _store.Users.Where(u => _store.GetUserIdsForStation(d.Id).Contains(u.Id)).Select(u => new
            {
                id = u.Id,
                username = u.Username,
                full_name = u.FullName,
                role = u.Role
            }).ToList()
        };
    }
}

