using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

public class StationCreateRequest
{
    public string name { get; set; } = "Trạm Giám Sát Mới";
    public string? location { get; set; } = "Phòng Thực Nghiệm IoT";
    public string? relay_label { get; set; } = "Bóng đèn 220V / Rơ-le";
    public string? description { get; set; }
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

            var st = _store.GetStation(id.Value);
            if (st == null)
            {
                return NotFound(new { ok = false, error = "Không tìm thấy trạm giám sát" });
            }

            var stDict = BuildStationPublic(st);
            var dev = _store.Devices.FirstOrDefault(d => d.StationId == st.Id || (d.StationId == null && d.Id == st.Id));
            if (dev != null)
            {
                stDict["spark"] = _store.GetSpark(dev.Id);
                stDict["stats24h"] = _store.GetStats24h(dev.Id);
            }
            else
            {
                stDict["spark"] = new List<object>();
                stDict["stats24h"] = null;
            }
            stDict["relay_logs"] = _store.RelayLogs.Take(15).ToList();

            return Ok(new { ok = true, station = stDict, device = stDict });
        }

        var source = _store.Stations.AsEnumerable();
        if (allowedStationIds != null)
        {
            source = source.Where(s => allowedStationIds.Contains(s.Id));
        }

        var list = source.Select(s =>
        {
            var item = BuildStationPublic(s);
            var dev = _store.Devices.FirstOrDefault(d => d.StationId == s.Id || (d.StationId == null && d.Id == s.Id));
            item["spark"] = dev != null ? _store.GetSpark(dev.Id) : new List<object>();
            return item;
        }).ToList();

        return Ok(new { ok = true, total = list.Count, stations = list, devices = list });
    }

    /// <summary>
    /// GET /api/stations/{id}: Lấy thông tin chi tiết trạm theo id
    /// </summary>
    [HttpGet("{id}")]
    public IActionResult GetById(int id)
    {
        return Get(id);
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

        if (string.IsNullOrWhiteSpace(req.name))
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập Tên trạm giám sát (name)" });
        }

        var newStation = new StationItem
        {
            Id = 0,
            Name = req.name.Trim(),
            Location = string.IsNullOrWhiteSpace(req.location) ? "Phòng Lab" : req.location.Trim(),
            Description = string.IsNullOrWhiteSpace(req.description) ? "Trạm giám sát IoT" : req.description.Trim(),
            RelayLabel = string.IsNullOrWhiteSpace(req.relay_label) ? "Bóng đèn 220V / Rơ-le" : req.relay_label.Trim(),
            CreatedAt = TimeHelper.VnNowStr
        };

        _db.Stations.Add(newStation);
        _db.SaveChanges();

        // Thêm vào in-memory DataStore
        _store.AddStation(newStation);

        // Phân công nhân viên nếu có truyền viewer_ids
        if (req.viewer_ids != null && req.viewer_ids.Count > 0)
        {
            foreach (var vid in req.viewer_ids)
            {
                var assign = new StationAssignment
                {
                    UserId = vid,
                    DeviceId = newStation.Id,
                    AssignedAt = TimeHelper.VnNow
                };
                _db.StationAssignments.Add(assign);
                _store.Assignments.Add(assign);
            }
            _db.SaveChanges();
        }

        var pub = BuildStationPublic(newStation);

        return Ok(new
        {
            ok = true,
            message = $"Đã tạo thành công trạm giám sát '{newStation.Name}'!",
            station = pub
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

        var st = _db.Stations.Find(id);
        var storeSt = _store.GetStation(id);
        if (st == null && storeSt == null) return NotFound(new { ok = false, error = "Không tìm thấy trạm" });

        if (st != null)
        {
            if (!string.IsNullOrWhiteSpace(req.name)) st.Name = req.name.Trim();
            if (req.location != null) st.Location = req.location.Trim();
            if (req.relay_label != null) st.RelayLabel = req.relay_label.Trim();
            if (req.description != null) st.Description = req.description.Trim();
            _db.SaveChanges();
        }

        if (storeSt != null)
        {
            if (!string.IsNullOrWhiteSpace(req.name)) storeSt.Name = req.name.Trim();
            if (req.location != null) storeSt.Location = req.location.Trim();
            if (req.relay_label != null) storeSt.RelayLabel = req.relay_label.Trim();
            if (req.description != null) storeSt.Description = req.description.Trim();
        }

        // Cập nhật ngưỡng của thiết bị được gán cho trạm này (nếu có)
        var linkedDev = _store.Devices.FirstOrDefault(d => d.StationId == id);
        if (linkedDev != null)
        {
            var dbDev = _db.Devices.Find(linkedDev.Id);
            if (req.air_temp_max.HasValue) { linkedDev.AirTempMax = req.air_temp_max.Value; if (dbDev != null) dbDev.AirTempMax = req.air_temp_max.Value; }
            if (req.air_hum_max.HasValue) { linkedDev.AirHumMax = req.air_hum_max.Value; if (dbDev != null) dbDev.AirHumMax = req.air_hum_max.Value; }
            if (req.probe_temp_min.HasValue) { linkedDev.ProbeTempMin = req.probe_temp_min.Value; if (dbDev != null) dbDev.ProbeTempMin = req.probe_temp_min.Value; }
            if (req.probe_temp_max.HasValue) { linkedDev.ProbeTempMax = req.probe_temp_max.Value; if (dbDev != null) dbDev.ProbeTempMax = req.probe_temp_max.Value; }
            if (req.dew_margin.HasValue) { linkedDev.DewMargin = req.dew_margin.Value; if (dbDev != null) dbDev.DewMargin = req.dew_margin.Value; }
            if (req.hysteresis.HasValue) { linkedDev.Hysteresis = req.hysteresis.Value; if (dbDev != null) dbDev.Hysteresis = req.hysteresis.Value; }
            _db.SaveChanges();
        }

        var resStation = storeSt ?? st;
        return Ok(new
        {
            ok = true,
            message = $"Đã cập nhật thông tin trạm '{resStation?.Name}' thành công!",
            station = resStation != null ? BuildStationPublic(resStation) : null
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

        var st = _db.Stations.Find(id);
        var storeSt = _store.GetStation(id);
        if (st == null && storeSt == null)
        {
            return NotFound(new { ok = false, error = "Không tìm thấy trạm giám sát" });
        }

        if (st != null)
        {
            var assigns = _db.StationAssignments.Where(a => a.DeviceId == id).ToList();
            if (assigns.Count > 0) _db.StationAssignments.RemoveRange(assigns);

            // Gỡ liên kết của các thiết bị trỏ vào trạm này
            var devs = _db.Devices.Where(d => d.StationId == id).ToList();
            foreach (var d in devs)
            {
                d.StationId = null;
            }

            _db.Stations.Remove(st);
            _db.SaveChanges();
        }

        var stName = st?.Name ?? storeSt?.Name ?? "Trạm";

        _store.DeleteStation(id);

        return Ok(new
        {
            ok = true,
            message = $"Đã xóa thành công trạm giám sát '{stName}'!"
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

    private Dictionary<string, object?> BuildStationPublic(StationItem s)
    {
        var d = _store.Devices.FirstOrDefault(x => x.StationId == s.Id || (x.StationId == null && x.Id == s.Id));
        var viewerIds = _store.GetUserIdsForStation(s.Id);
        var viewers = _store.Users.Where(u => viewerIds.Contains(u.Id)).Select(u => new
        {
            id = u.Id,
            username = u.Username,
            full_name = u.FullName,
            role = u.Role
        }).ToList();

        if (d != null)
        {
            return new Dictionary<string, object?>
            {
                ["id"] = s.Id,
                ["name"] = s.Name,
                ["location"] = s.Location ?? d.Location,
                ["description"] = s.Description ?? d.Description,
                ["relay_label"] = s.RelayLabel ?? d.RelayLabel,
                ["device_id"] = d.Id,
                ["device_code"] = d.DeviceCode,
                ["device_name"] = d.Name,
                ["profile"] = d.Profile,
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
                ["viewer_ids"] = viewerIds,
                ["viewers"] = viewers
            };
        }

        // Trường hợp trạm chưa gắn thiết bị vi điều khiển nào
        return new Dictionary<string, object?>
        {
            ["id"] = s.Id,
            ["name"] = s.Name,
            ["location"] = s.Location ?? "Chưa thiết lập",
            ["description"] = s.Description ?? "Trạm giám sát IoT",
            ["relay_label"] = s.RelayLabel ?? "Bóng đèn 220V / Rơ-le",
            ["device_id"] = null,
            ["device_code"] = "",
            ["device_name"] = "Chưa gắn thiết bị vi điều khiển",
            ["profile"] = "cabinet",
            ["relay_mode"] = "AUTO",
            ["relay_state"] = 0,
            ["status"] = "OFFLINE",
            ["online"] = false,
            ["air_temp"] = null,
            ["air_hum"] = null,
            ["dew_point"] = null,
            ["probe_temp"] = null,
            ["pico_temp"] = null,
            ["light_raw"] = 0,
            ["light_pct"] = 0,
            ["air_temp_max"] = 40.0,
            ["air_hum_max"] = 75.0,
            ["probe_temp_min"] = 0.0,
            ["probe_temp_max"] = 60.0,
            ["dew_margin"] = 3.0,
            ["hysteresis"] = 1.5,
            ["offset_air"] = 0.0,
            ["offset_probe"] = 0.0,
            ["offline_after"] = 60,
            ["open_alerts"] = 0,
            ["send_interval"] = 3,
            ["rssi"] = null,
            ["last_seen"] = null,
            ["firmware"] = "None",
            ["oled_msg"] = "",
            ["key_version"] = 1,
            ["ingest_auth"] = "hmac",
            ["viewer_ids"] = viewerIds,
            ["viewers"] = viewers
        };
    }
}
