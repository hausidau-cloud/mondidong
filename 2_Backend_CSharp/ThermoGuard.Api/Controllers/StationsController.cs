using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

public class StationCreateRequest
{
    public string device_code { get; set; } = "PICO-02";
    public string name { get; set; } = "Trạm Pico 2 W số 2";
    public string? location { get; set; } = "Phòng Thực Nghiệm IoT";
    public string? relay_label { get; set; } = "Bóng đèn 220V / Rơ-le";
    public string? description { get; set; }
    public string? api_key { get; set; }
    public double air_temp_max { get; set; } = 40.0;
    public double air_hum_max { get; set; } = 75.0;
    public double probe_temp_min { get; set; } = 0.0;
    public double probe_temp_max { get; set; } = 60.0;
    public double dew_margin { get; set; } = 3.0;
    public double hysteresis { get; set; } = 1.5;
    public List<int>? viewer_ids { get; set; }
}

public class StationUpdateRequest
{
    public string? name { get; set; }
    public string? location { get; set; }
    public string? relay_label { get; set; }
    public string? description { get; set; }
    public double? air_temp_max { get; set; }
    public double? air_hum_max { get; set; }
    public double? probe_temp_min { get; set; }
    public double? probe_temp_max { get; set; }
    public double? dew_margin { get; set; }
    public double? hysteresis { get; set; }
}

[ApiController]
[Tags("Stations")]
[Route("api/stations")]
public class StationsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly DataStore _store;

    public StationsController(AppDbContext db, DataStore store)
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
    /// GET /api/stations: Lấy danh sách trạm (Tự động lọc nếu là Viewer chỉ thấy trạm được giao)
    /// </summary>
    [HttpGet]
    public IActionResult Get([FromQuery] int? id)
    {
        var curUser = GetCurrentUser();
        List<int>? allowedStationIds = null;
        if (curUser != null && curUser.Role == "viewer")
        {
            allowedStationIds = _store.GetStationIdsForUser(curUser.Id);
        }

        if (id.HasValue)
        {
            if (allowedStationIds != null && !allowedStationIds.Contains(id.Value))
            {
                return Forbid();
            }

            var dev = _store.GetDevice(id.Value);
            if (dev == null)
            {
                return NotFound(new { ok = false, error = "Không tìm thấy trạm giám sát" });
            }

            var devDict = BuildStationPublic(dev);
            devDict["spark"] = _store.GetSpark(dev.Id);
            devDict["stats24h"] = _store.GetStats24h(dev.Id);
            devDict["relay_logs"] = _store.RelayLogs.Take(15).ToList();

            return Ok(new { ok = true, station = devDict, device = devDict });
        }

        var source = _store.Devices.AsEnumerable();
        if (allowedStationIds != null)
        {
            source = source.Where(d => allowedStationIds.Contains(d.Id));
        }

        var list = source.Select(d =>
        {
            var item = BuildStationPublic(d);
            item["spark"] = _store.GetSpark(d.Id);
            return item;
        }).ToList();

        return Ok(new { ok = true, total = list.Count, stations = list, devices = list });
    }

    /// <summary>
    /// GET /api/stations/{id}/viewers: Xem danh sách nhân viên đang giám sát trạm {id}
    /// </summary>
    [HttpGet("{id}/viewers")]
    public IActionResult GetViewers(int id)
    {
        var viewerIds = _store.GetUserIdsForStation(id);
        var viewers = _store.Users.Where(u => viewerIds.Contains(u.Id)).Select(u => new
        {
            id = u.Id,
            username = u.Username,
            full_name = u.FullName,
            role = u.Role
        }).ToList();

        return Ok(new { ok = true, station_id = id, total = viewers.Count, viewers });
    }

    /// <summary>
    /// POST /api/stations: Thêm trạm giám sát mới (Admin only)
    /// </summary>
    [HttpPost]
    public IActionResult CreateStation([FromBody] StationCreateRequest req)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        if (string.IsNullOrWhiteSpace(req.device_code) || string.IsNullOrWhiteSpace(req.name))
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập Mã thiết bị (device_code) và Tên trạm (name)" });
        }

        var code = req.device_code.Trim().ToUpperInvariant();
        if (_db.Devices.Any(d => d.DeviceCode.ToUpper() == code) || _store.Devices.Any(d => d.DeviceCode.ToUpper() == code))
        {
            return BadRequest(new { ok = false, error = $"Mã trạm '{code}' đã tồn tại trong hệ thống!" });
        }

        var apiKey = string.IsNullOrWhiteSpace(req.api_key) ? Guid.NewGuid().ToString("N") : req.api_key.Trim();
        var newDev = new Device
        {
            Id = 0,
            DeviceCode = code,
            ApiKey = apiKey,
            Name = req.name.Trim(),
            Location = string.IsNullOrWhiteSpace(req.location) ? "Phòng Lab" : req.location.Trim(),
            Profile = "cabinet",
            Description = string.IsNullOrWhiteSpace(req.description) ? "Trạm giám sát IoT" : req.description.Trim(),
            RelayLabel = string.IsNullOrWhiteSpace(req.relay_label) ? "Rơ-le / Thiết bị" : req.relay_label.Trim(),
            RelayMode = "AUTO",
            RelayState = 0,
            Status = "OFFLINE",
            AirTempMax = req.air_temp_max > 0 ? req.air_temp_max : 40.0,
            AirHumMax = req.air_hum_max > 0 ? req.air_hum_max : 75.0,
            ProbeTempMin = req.probe_temp_min,
            ProbeTempMax = req.probe_temp_max > 0 ? req.probe_temp_max : 60.0,
            DewMargin = req.dew_margin > 0 ? req.dew_margin : 3.0,
            Hysteresis = req.hysteresis > 0 ? req.hysteresis : 1.5,
            SendInterval = 3,
            OfflineAfter = 60
        };

        _db.Devices.Add(newDev);
        _db.SaveChanges();

        // Thêm vào in-memory DataStore
        _store.AddDevice(newDev);

        // Phân công nhân viên nếu có truyền viewer_ids
        if (req.viewer_ids != null && req.viewer_ids.Count > 0)
        {
            foreach (var vid in req.viewer_ids)
            {
                _store.Assignments.Add(new StationAssignment
                {
                    Id = _store.Assignments.Count > 0 ? _store.Assignments.Max(a => a.Id) + 1 : 1,
                    UserId = vid,
                    DeviceId = newDev.Id,
                    AssignedAt = TimeHelper.VnNow
                });
                _db.StationAssignments.Add(new StationAssignment
                {
                    UserId = vid,
                    DeviceId = newDev.Id,
                    AssignedAt = TimeHelper.VnNow
                });
            }
            _db.SaveChanges();
        }

        var pub = BuildStationPublic(newDev);
        pub["api_key"] = newDev.ApiKey;

        return Ok(new
        {
            ok = true,
            message = $"Đã tạo thành công trạm '{newDev.Name}' ({newDev.DeviceCode})!",
            station = pub,
            api_key = newDev.ApiKey
        });
    }

    /// <summary>
    /// PUT /api/stations/{id}: Cập nhật thông tin và ngưỡng cảnh báo của trạm (Admin only)
    /// </summary>
    [HttpPut("{id}")]
    public IActionResult UpdateStation(int id, [FromBody] StationUpdateRequest req)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        var dev = _db.Devices.Find(id);
        if (dev == null) return NotFound(new { ok = false, error = "Không tìm thấy trạm" });

        if (!string.IsNullOrWhiteSpace(req.name)) dev.Name = req.name.Trim();
        if (req.location != null) dev.Location = req.location.Trim();
        if (req.relay_label != null) dev.RelayLabel = req.relay_label.Trim();
        if (req.description != null) dev.Description = req.description.Trim();
        if (req.air_temp_max.HasValue) dev.AirTempMax = req.air_temp_max.Value;
        if (req.air_hum_max.HasValue) dev.AirHumMax = req.air_hum_max.Value;
        if (req.probe_temp_min.HasValue) dev.ProbeTempMin = req.probe_temp_min.Value;
        if (req.probe_temp_max.HasValue) dev.ProbeTempMax = req.probe_temp_max.Value;
        if (req.dew_margin.HasValue) dev.DewMargin = req.dew_margin.Value;
        if (req.hysteresis.HasValue) dev.Hysteresis = req.hysteresis.Value;

        _db.SaveChanges();

        var storeDev = _store.GetDevice(id);
        if (storeDev != null)
        {
            storeDev.Name = dev.Name;
            storeDev.Location = dev.Location;
            storeDev.RelayLabel = dev.RelayLabel;
            storeDev.Description = dev.Description;
            storeDev.AirTempMax = dev.AirTempMax;
            storeDev.AirHumMax = dev.AirHumMax;
            storeDev.ProbeTempMin = dev.ProbeTempMin;
            storeDev.ProbeTempMax = dev.ProbeTempMax;
            storeDev.DewMargin = dev.DewMargin;
            storeDev.Hysteresis = dev.Hysteresis;
        }

        return Ok(new
        {
            ok = true,
            message = $"Đã cập nhật thông tin trạm '{dev.Name}' thành công!",
            station = BuildStationPublic(dev)
        });
    }

    /// <summary>
    /// DELETE /api/stations/{id}: Xóa trạm giám sát khỏi hệ thống (Admin only)
    /// </summary>
    [HttpDelete("{id}")]
    public IActionResult DeleteStation(int id)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        var dev = _db.Devices.Find(id);
        var storeDev = _store.GetDevice(id);
        if (dev == null && storeDev == null)
        {
            return NotFound(new { ok = false, error = "Không tìm thấy trạm" });
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

        var devName = dev?.Name ?? storeDev?.Name ?? "Trạm";
        var devCode = dev?.DeviceCode ?? storeDev?.DeviceCode ?? "";

        _store.DeleteDevice(id);

        return Ok(new
        {
            ok = true,
            message = $"Đã xóa thành công trạm '{devName}' ({devCode})!"
        });
    }

    /// <summary>
    /// DELETE /api/stations/{deviceId}/viewers/{userId}: Gỡ nhân viên khỏi trạm (Admin only)
    /// </summary>
    [HttpDelete("{deviceId}/viewers/{userId}")]
    public IActionResult RemoveViewer(int deviceId, int userId)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        _store.RemoveAssignment(deviceId, userId, _db);
        return Ok(new { ok = true, message = "Đã gỡ nhân viên khỏi trạm" });
    }

    private Dictionary<string, object?> BuildStationPublic(Device d)
    {
        return new Dictionary<string, object?>
        {
            ["id"] = d.Id,
            ["device_code"] = d.DeviceCode,
            ["name"] = d.Name,
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
